# shellcheck shell=bash
#
# turn-state.sh — shared turn-state primitives for cp-architecture hooks.
#
# Implements the "Turn state contract" defined in the notes file under
# Phase 5 Task 5.1. Tasks 5.2 (classifier), 5.4 (MCP tracker), and 5.5
# (Stop hook) source this file so the atomic-write algorithm lives in
# exactly one place and is audited against the notes contract once.
#
# Exported functions:
#   ts_state_dir                              → state directory path
#   ts_state_file    <session_id>             → state file path
#   ts_lockdir       <session_id>             → turn-state lockdir path
#   ts_acquire_lock  <lockdir>                → 0 on acquire, 1 on timeout
#   ts_release_lock  <lockdir>                → always 0
#   ts_read          <session_id>             → echoes state JSON or `{}`
#   ts_delete        <session_id>             → removes state file
#   ts_record_write  <session_id> <seq_field> <at_field>
#                                             → one atomic read/modify/
#                                               write per the Task 5.1
#                                               contract; 0 on success,
#                                               1 on timeout / jq / mv
#                                               failure.
#   ts_drift_mode                             → echoes the effective
#                                               drift mode ("off",
#                                               "warn", or "block") per
#                                               the notes contract;
#                                               unset / invalid values
#                                               default to "warn".
#
# Caller requirements:
#   - ${CLAUDE_PLUGIN_DATA} is set (hook harness provides this).
#   - jq is on PATH (require-jq.sh should be sourced first).
#
# Failure posture: every function soft-fails and logs a single stderr
# warning on infra trouble. Hooks never block the developer edit path on
# turn-state errors — the Phase 3 wrapper is the hard dependency-check
# entry point; hooks are advisory.

# Task 0.9 defaults — 30 × 100ms = 3s wait, 60s stale threshold. Tighter
# than the wrapper's 300s / 180s budgets because hooks hold this lock for
# microseconds, never seconds.
_TS_LOCK_MAX_ATTEMPTS=30
_TS_LOCK_SLEEP=0.1
_TS_LOCK_STALE_SECONDS=60

_ts_warn() { echo "[cp-architecture hook] $*" >&2; }

# ts_drift_mode
# Reads CP_ARCHITECTURE_DRIFT_MODE and echoes one of "off", "warn",
# or "block". An unset or unrecognised value defaults to "warn" — see
# the notes file "Drift mode" section for the rationale (the plugin
# is advisory by default; `block` is deliberate opt-in).
#
# Every hook script calls this helper exactly once at entry and caches
# the result in a local variable; no script looks at
# CP_ARCHITECTURE_DRIFT_MODE directly, so a typo in a branch cannot
# silently behave like an "unknown mode".
ts_drift_mode() {
  case "${CP_ARCHITECTURE_DRIFT_MODE:-}" in
    off|warn|block) printf '%s' "$CP_ARCHITECTURE_DRIFT_MODE" ;;
    *)              printf 'warn' ;;
  esac
}

# Portable mtime: GNU `stat -c %Y` (Linux) first, BSD `stat -f %m` (macOS)
# fallback. Capture each branch's stdout into a local so the failing branch
# (on the other platform) cannot leak `stat -f`'s --file-system output into
# our caller's arithmetic comparisons. No `%N` anywhere — Task 0.9 forbids
# sub-second arithmetic because BSD `date` lacks `%N`.
_ts_stat_mtime() {
  local out
  if out=$(stat -c %Y "$1" 2>/dev/null); then printf '%s' "$out"; return 0; fi
  if out=$(stat -f %m "$1" 2>/dev/null); then printf '%s' "$out"; return 0; fi
  return 0
}

ts_state_dir() {
  printf '%s/state' "${CLAUDE_PLUGIN_DATA}"
}

ts_state_file() {
  printf '%s/state/turn-%s.json' "${CLAUDE_PLUGIN_DATA}" "$1"
}

ts_lockdir() {
  printf '%s/state/turn-%s.lock.d' "${CLAUDE_PLUGIN_DATA}" "$1"
}

# acquire_lock <lockdir>
# Returns 0 on acquire, 1 on timeout after 30 attempts (≈3s).
ts_acquire_lock() {
  local lockdir="$1"
  local attempt=0
  local parent
  parent=$(dirname "$lockdir")
  mkdir -p "$parent" 2>/dev/null || true

  while [ "$attempt" -lt "$_TS_LOCK_MAX_ATTEMPTS" ]; do
    if mkdir "$lockdir" 2>/dev/null; then
      return 0
    fi
    if [ -d "$lockdir" ]; then
      local mtime now age
      mtime=$(_ts_stat_mtime "$lockdir")
      if [ -n "$mtime" ]; then
        now=$(date +%s)
        age=$((now - mtime))
        if [ "$age" -gt "$_TS_LOCK_STALE_SECONDS" ]; then
          rmdir "$lockdir" 2>/dev/null || true
          continue
        fi
      fi
    fi
    sleep "$_TS_LOCK_SLEEP"
    attempt=$((attempt + 1))
  done
  return 1
}

ts_release_lock() {
  rmdir "$1" 2>/dev/null || true
}

# Stop hook reads without holding the lock. The atomic-rename write
# algorithm guarantees the file is never half-written; a reader sees the
# pre- or post-rename version, never a partial mix.
ts_read() {
  local state_file
  state_file=$(ts_state_file "$1")
  if [ -s "$state_file" ]; then
    cat "$state_file"
  else
    printf '{}'
  fi
}

ts_delete() {
  local state_file
  state_file=$(ts_state_file "$1")
  rm -f "$state_file" 2>/dev/null || true
}

# ts_record_write <session_id> <seq_field> <at_field>
#
# One atomic read-modify-write per the notes "Atomic-write algorithm"
# under Phase 5 Task 5.1. Both writers (classifier + MCP tracker) call
# this with their own field pair; the pairing determines which slot is
# updated while preserving the peer writer's slot.
ts_record_write() {
  local session_id="$1"
  local seq_field="$2"
  local at_field="$3"

  if [ -z "$session_id" ] || [ -z "$seq_field" ] || [ -z "$at_field" ]; then
    _ts_warn "ts_record_write: missing required arg (session_id/seq_field/at_field)"
    return 1
  fi
  if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
    _ts_warn "ts_record_write: CLAUDE_PLUGIN_DATA not set; skipping turn-state write"
    return 1
  fi

  local state_dir state_file lockdir tmpfile
  state_dir=$(ts_state_dir)
  state_file=$(ts_state_file "$session_id")
  lockdir=$(ts_lockdir "$session_id")
  tmpfile="${state_file}.tmp.$$"

  if ! mkdir -p "$state_dir" 2>/dev/null; then
    _ts_warn "ts_record_write: could not create ${state_dir}; skipping"
    return 1
  fi

  if ! ts_acquire_lock "$lockdir"; then
    _ts_warn "could not acquire turn-state lock ${lockdir} after 3s; skipping"
    return 1
  fi

  local now
  now=$(date +%s)

  local old='{}'
  if [ -s "$state_file" ]; then
    old=$(cat "$state_file" 2>/dev/null || printf '{}')
  fi

  # First attempt: merge with the existing state. One jq invocation keeps
  # lock hold-time under ~20ms on typical hardware.
  if ! printf '%s' "$old" | jq -c \
      --arg session "$session_id" \
      --argjson now "$now" \
      --arg seq_fld "$seq_field" \
      --arg at_fld  "$at_field" \
      '((.seq // 0) + 1) as $s |
       . + { session_id: $session, seq: $s, updated_at: $now,
             ($seq_fld): $s, ($at_fld): $now }' \
      > "$tmpfile" 2>/dev/null
  then
    # Malformed existing file: retry once from an empty base. If this
    # also fails, something more fundamental is broken — release the lock
    # and soft-fail.
    if ! printf '{}' | jq -c \
        --arg session "$session_id" \
        --argjson now "$now" \
        --arg seq_fld "$seq_field" \
        --arg at_fld  "$at_field" \
        '((.seq // 0) + 1) as $s |
         . + { session_id: $session, seq: $s, updated_at: $now,
               ($seq_fld): $s, ($at_fld): $now }' \
        > "$tmpfile" 2>/dev/null
    then
      _ts_warn "ts_record_write: jq failed to render new state for session ${session_id}; skipping"
      rm -f "$tmpfile" 2>/dev/null || true
      ts_release_lock "$lockdir"
      return 1
    fi
  fi

  # Atomic rename on the same filesystem. A reader either sees the old
  # complete file or the new complete file, never a partial mix.
  if ! mv -f "$tmpfile" "$state_file" 2>/dev/null; then
    _ts_warn "ts_record_write: mv -f failed for ${state_file}; skipping"
    rm -f "$tmpfile" 2>/dev/null || true
    ts_release_lock "$lockdir"
    return 1
  fi

  ts_release_lock "$lockdir"
  return 0
}
