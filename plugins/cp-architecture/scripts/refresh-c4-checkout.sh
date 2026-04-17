#!/usr/bin/env bash
#
# refresh-c4-checkout.sh — forced refresh of the cp-c4-architecture checkout.
#
# Invoked by the /refresh-c4-model command (Phase 4). Runs a fast-forward
# pull inside the wrapper-managed checkout, updates the last-pull sentinel,
# and prints a summary of what moved. Shares the wrapper lockdir so a manual
# refresh cannot race a session startup.
#
# NB: the running MCP server still holds the pre-refresh model in memory
# until the next session restart — that caveat is printed on stdout.

set -eu

if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  echo "[refresh-c4-checkout] CLAUDE_PLUGIN_DATA is not set; run via the /refresh-c4-model command" >&2
  exit 1
fi

CHECKOUT_DIR="${CLAUDE_PLUGIN_DATA}/cp-c4-architecture"
STATE_DIR="${CLAUDE_PLUGIN_DATA}/state"
LAST_PULL_FILE="${STATE_DIR}/last-pull"
WRAPPER_LOCKDIR="${STATE_DIR}/wrapper.lock.d"

# Must match the wrapper's WRAPPER_LOCK_STALE_SECONDS (notes "Lockfile TTL"
# section). A 60s threshold here would let a manual refresh steal the lock
# from a still-active wrapper doing a cold `npm ci`.
LOCK_STALE_SECONDS=300
# Wait budget is deliberately shorter than the wrapper's 180s. A user who
# typed /refresh-c4-model shouldn't be held for three minutes; the right
# UX is to fail fast with "another process is installing — retry in a moment".
LOCK_MAX_ATTEMPTS=30
LOCK_SLEEP_SECONDS=0.1

log_warn() { echo "[refresh-c4-checkout] $*" >&2; }
die() {
  echo "[refresh-c4-checkout] $*" >&2
  exit 1
}

stat_mtime() {
  # See c4-mcp-wrapper.sh stat_mtime for rationale — GNU `stat -f` means
  # --file-system and leaks multi-line stdout, so each branch must capture
  # its stdout into a local and only echo on success.
  local out
  if out=$(stat -c %Y "$1" 2>/dev/null); then echo "$out"; return 0; fi
  if out=$(stat -f %m "$1" 2>/dev/null); then echo "$out"; return 0; fi
  return 0
}

command -v git >/dev/null 2>&1 || die "git not found in PATH; install git and retry"

acquire_lock() {
  local lockdir="$1"
  local attempt=0
  mkdir -p "$(dirname "$lockdir")" 2>/dev/null || true

  while [ "$attempt" -lt "$LOCK_MAX_ATTEMPTS" ]; do
    if mkdir "$lockdir" 2>/dev/null; then
      return 0
    fi
    if [ -d "$lockdir" ]; then
      local mtime
      mtime=$(stat_mtime "$lockdir")
      if [ -n "$mtime" ]; then
        local now age
        now=$(date +%s)
        age=$((now - mtime))
        if [ "$age" -gt "$LOCK_STALE_SECONDS" ]; then
          rmdir "$lockdir" 2>/dev/null || true
          continue
        fi
      fi
    fi
    sleep "$LOCK_SLEEP_SECONDS"
    attempt=$((attempt + 1))
  done
  return 1
}

release_lock() { rmdir "$1" 2>/dev/null || true; }

if ! acquire_lock "$WRAPPER_LOCKDIR"; then
  die "could not acquire ${WRAPPER_LOCKDIR} after 3s; another process appears to hold it — try again in a moment"
fi
trap 'release_lock "$WRAPPER_LOCKDIR"' EXIT INT TERM

# Checkout presence must be tested inside the lock: a first-session wrapper
# may currently be cloning into ${CHECKOUT_DIR}, in which case .git might
# not exist yet. Checking outside the lock would race that clone and die
# with a misleading "not a git checkout" message instead of waiting/failing
# on the lock contention.
if [ ! -d "${CHECKOUT_DIR}/.git" ]; then
  die "${CHECKOUT_DIR} is not a git checkout; start a Claude Code session with the cp-architecture plugin so the wrapper can clone it first"
fi

# Pre-pull dirty check — refuse to pull on top of hand edits.
status_output=$(git -C "$CHECKOUT_DIR" status --porcelain 2>/dev/null || true)
if [ -n "$status_output" ]; then
  echo "[refresh-c4-checkout] ${CHECKOUT_DIR} has uncommitted changes:" >&2
  echo "$status_output" >&2
  die "refusing to pull on top of a dirty checkout; commit, discard, or wipe ${CHECKOUT_DIR} and retry"
fi

before_sha=$(git -C "$CHECKOUT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

if ! pull_output=$(git -C "$CHECKOUT_DIR" pull --ff-only 2>&1); then
  echo "$pull_output" >&2
  die "git pull --ff-only failed in ${CHECKOUT_DIR}; upstream may have diverged"
fi

after_sha=$(git -C "$CHECKOUT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")

mkdir -p "$STATE_DIR"
touch "$LAST_PULL_FILE"

if [ "$before_sha" = "$after_sha" ]; then
  echo "cp-c4-architecture is already up to date (HEAD=${after_sha})."
  changed_count=0
else
  changed_count=$(git -C "$CHECKOUT_DIR" diff --name-only "${before_sha}..${after_sha}" 2>/dev/null | wc -l | tr -d ' ')
  echo "cp-c4-architecture refreshed: ${before_sha} → ${after_sha} (${changed_count} files changed)."
fi

echo "last-pull sentinel updated at ${LAST_PULL_FILE}."
echo
echo "Note: the running MCP server still holds the pre-refresh model in memory."
echo "Restart this Claude Code session to pick up the new model."
