#!/usr/bin/env bash
#
# c4-mcp-wrapper.sh — cp-architecture plugin MCP lifecycle entrypoint.
#
# Invoked by Claude Code via plugins/cp-architecture/.mcp.json on every
# session startup. Owns the clone, pull, install, and exec of the LikeC4 MCP
# server that cp-c4-architecture ships via its own `mcp` npm script.
#
# Contract and rationale for every decision in this file live in:
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md
# Consult the notes file before changing behaviour. Cross-references below.

set -eu

# ---------------------------------------------------------------------------
# Environment prerequisites (before anything else — fail fast with a clear
# message if the plugin harness didn't export what we expect).
# ---------------------------------------------------------------------------
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  echo "[c4-mcp-wrapper] CLAUDE_PLUGIN_DATA is not set; this script must run under a Claude Code plugin harness" >&2
  exit 1
fi

if [ -z "${C4_REPO_URL:-}" ]; then
  echo "[c4-mcp-wrapper] C4_REPO_URL is not set; it must be supplied via .mcp.json env" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Path constants (notes file "State layout" section — keep in sync).
# ---------------------------------------------------------------------------
CHECKOUT_DIR="${CLAUDE_PLUGIN_DATA}/cp-c4-architecture"
NPM_CACHE_DIR="${CLAUDE_PLUGIN_DATA}/npm-cache"
STATE_DIR="${CLAUDE_PLUGIN_DATA}/state"
LAST_PULL_FILE="${STATE_DIR}/last-pull"
WRAPPER_LOCKDIR="${STATE_DIR}/wrapper.lock.d"
LOGS_DIR="${CLAUDE_PLUGIN_DATA}/logs"
WRAPPER_LOG="${LOGS_DIR}/wrapper.log"

# Tuning constants.
PULL_STALENESS_SECONDS=$((24 * 60 * 60)) # 24h — notes "last-pull staleness window"
LOCK_SLEEP_SECONDS=0.1
# Wrapper-lock budgets are deliberately longer than the hook budgets documented
# in notes Task 0.9. The wrapper can legitimately hold its lock for the whole
# clone+npm ci duration on a cold cache (30–90s observed), and a concurrent
# second session must block through that instead of racing in.
#   - WRAPPER_LOCK_MAX_ATTEMPTS: 180s wait budget (1800 * 100ms) — longer than
#     any plausible cold install so a second session can ride out the first.
#   - WRAPPER_LOCK_STALE_SECONDS: 300s stale threshold — longer than the wait
#     budget so a legitimately-held lock is never stolen from an actively
#     installing first session. Genuinely crashed wrappers are still swept
#     within 5 minutes (much shorter than the 24h state GC).
WRAPPER_LOCK_MAX_ATTEMPTS=1800           # 1800 * 100ms = 180s
WRAPPER_LOCK_STALE_SECONDS=300           # 5 min — longer than the longest cold install
# Turn state lockdirs (Phase 5) are held for microseconds by hooks, so the GC
# treats them as stale at the Task 0.9 default of 60s — NOT the wrapper's
# 300s budget. Keeping these in sync with the notes "Lockfile TTL" section
# avoids a 5-minute cleanup window for orphaned hook locks.
TURN_LOCK_STALE_SECONDS=60
STATE_GC_AGE_SECONDS=$((24 * 60 * 60))   # notes Task 0.4 / state layout
LOG_ROTATE_BYTES=$((1024 * 1024))        # 1 MB — notes "Log rotation policy"

log_warn() { echo "[c4-mcp-wrapper] $*" >&2; }
die() {
  echo "[c4-mcp-wrapper] $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# stat(1) portability wrappers. GNU/Linux uses `-c`, BSD (macOS) uses `-f`.
# Each branch's stdout is captured separately and only echoed on success —
# otherwise the GNU `-f` mode (which means --file-system) leaks multi-line
# filesystem output into the pipeline and breaks later integer comparisons.
# Notes file Task 0.9 forbids `date +%s%N`; we do the same by only ever asking
# for second-precision mtime/size.
# ---------------------------------------------------------------------------
stat_mtime() {
  # Prints seconds-since-epoch mtime of $1, or empty string if not found.
  local out
  if out=$(stat -c %Y "$1" 2>/dev/null); then echo "$out"; return 0; fi
  if out=$(stat -f %m "$1" 2>/dev/null); then echo "$out"; return 0; fi
  return 0
}

stat_size() {
  # Prints size in bytes of $1, or 0 if not found.
  local out
  if out=$(stat -c %s "$1" 2>/dev/null); then echo "$out"; return 0; fi
  if out=$(stat -f %z "$1" 2>/dev/null); then echo "$out"; return 0; fi
  echo 0
}

# ---------------------------------------------------------------------------
# Dependency presence checks (run BEFORE acquiring the lock so we fail fast
# on a broken dev box without blocking concurrent sessions).
# Notes "Failure modes" section (1, 2, 3).
# ---------------------------------------------------------------------------
require_dependencies() {
  command -v git >/dev/null 2>&1 || die "git not found in PATH; install git and retry"
  command -v node >/dev/null 2>&1 || die "node/npm not found in PATH; install Node.js >=22 and retry"
  command -v npm >/dev/null 2>&1 || die "node/npm not found in PATH; install Node.js >=22 and retry"
  command -v jq >/dev/null 2>&1 || die "jq not found in PATH; install jq (brew install jq / apt-get install jq) and retry"

  # likec4 declares engines.node >= 22.22.1. We enforce major >= 22 only —
  # three-part version comparison in bash without `sort -V` is brittle and
  # not worth the maintenance cost. Any Node 22.x release has worked in
  # practice (tested on node:22-slim in Phase 8). If a specific minor/patch
  # boundary causes a real failure, npm ci will surface the engine-mismatch
  # warning downstream, so developers are not silently broken.
  # Parameter expansion only — no sed (which is not guaranteed to be in
  # every hook PATH).
  local node_version node_major
  node_version=$(node -v 2>/dev/null)
  node_version=${node_version#v}
  node_major=${node_version%%.*}
  if [ -z "$node_major" ] || ! [ "$node_major" -ge 22 ] 2>/dev/null; then
    die "node ${node_version:-unknown} is too old; install Node.js >=22 and retry"
  fi
}

# ---------------------------------------------------------------------------
# Log rotation (notes "Log rotation policy"). Runs after deps are checked and
# before locks are acquired; rotating is cheap and doesn't touch shared state.
# ---------------------------------------------------------------------------
setup_logging() {
  if ! mkdir -p "$LOGS_DIR" 2>/dev/null; then
    log_warn "could not create ${LOGS_DIR}; continuing without log tee"
    return 0
  fi
  if [ -f "$WRAPPER_LOG" ]; then
    local size
    size=$(stat_size "$WRAPPER_LOG")
    if [ "${size:-0}" -gt "$LOG_ROTATE_BYTES" ]; then
      mv -f "$WRAPPER_LOG" "${WRAPPER_LOG}.1" 2>/dev/null || true
    fi
  fi
  # Append all subsequent stderr both to the log and to the original fd so
  # Claude Code still surfaces the messages live. `tee -a` never truncates.
  exec 2> >(tee -a "$WRAPPER_LOG" >&2)
}

# ---------------------------------------------------------------------------
# Lock helpers (notes Task 0.9 "Acquisition algorithm"). Fixed retry counter;
# no sub-second arithmetic anywhere.
# ---------------------------------------------------------------------------
acquire_lock() {
  local lockdir="$1"
  local max_attempts="${2:-$WRAPPER_LOCK_MAX_ATTEMPTS}"
  local attempt=0
  local parent
  parent=$(dirname "$lockdir")
  mkdir -p "$parent" 2>/dev/null || true

  while [ "$attempt" -lt "$max_attempts" ]; do
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
        if [ "$age" -gt "$WRAPPER_LOCK_STALE_SECONDS" ]; then
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

release_lock() {
  rmdir "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# State-dir GC (notes "GC sweep scope"). Runs inside the wrapper lock so we
# don't race another instance starting up.
# ---------------------------------------------------------------------------
gc_state_dir() {
  [ -d "$STATE_DIR" ] || return 0
  local now
  now=$(date +%s)

  # Sweep stale files (not last-pull, not lockdirs).
  for entry in "$STATE_DIR"/*; do
    [ -e "$entry" ] || continue
    local base
    base=$(basename "$entry")
    case "$base" in
      last-pull) continue ;;
      *.lock.d)
        # Handled in the second loop to keep the conditions legible.
        continue
        ;;
    esac
    if [ -f "$entry" ]; then
      local mtime age
      mtime=$(stat_mtime "$entry")
      [ -n "$mtime" ] || continue
      age=$((now - mtime))
      if [ "$age" -gt "$STATE_GC_AGE_SECONDS" ]; then
        rm -f "$entry" 2>/dev/null || true
      fi
    fi
  done

  # Sweep stale lockdirs. Thresholds are per-category (notes "Lockfile TTL"):
  #   - wrapper.lock.d:       300s (held through cold `npm ci`)
  #   - turn-*.lock.d (Phase 5): 60s (held for microseconds by hooks)
  # Do NOT touch the wrapper's own lockdir — this function runs while we
  # hold it, and it's fresh by definition.
  for lockdir in "$STATE_DIR"/*.lock.d; do
    [ -d "$lockdir" ] || continue
    [ "$lockdir" = "$WRAPPER_LOCKDIR" ] && continue
    local mtime age base threshold
    mtime=$(stat_mtime "$lockdir")
    [ -n "$mtime" ] || continue
    age=$((now - mtime))
    base=$(basename "$lockdir")
    case "$base" in
      turn-*.lock.d)    threshold=$TURN_LOCK_STALE_SECONDS ;;
      wrapper.lock.d)   threshold=$WRAPPER_LOCK_STALE_SECONDS ;;
      *)                threshold=$WRAPPER_LOCK_STALE_SECONDS ;;
    esac
    if [ "$age" -gt "$threshold" ]; then
      rmdir "$lockdir" 2>/dev/null || true
    fi
  done
}

# ---------------------------------------------------------------------------
# Clone / pull / install / exec. Every step is ordered deliberately — see the
# notes file "Wrapper flow" section. Do not reorder without updating the
# notes first.
# ---------------------------------------------------------------------------
ensure_checkout() {
  if [ ! -d "$CHECKOUT_DIR/.git" ]; then
    mkdir -p "$(dirname "$CHECKOUT_DIR")"
    # All output to stderr — stdout is reserved for the MCP stdio transport
    # once we exec. git clone/pull and npm ci are noisy; the wrapper log
    # already captures stderr via setup_logging's tee.
    if ! git clone --quiet "$C4_REPO_URL" "$CHECKOUT_DIR" >&2; then
      die "failed to clone ${C4_REPO_URL} into ${CHECKOUT_DIR}; check network/auth and retry"
    fi
  fi
}

pre_install_dirty_check() {
  local status
  status=$(git -C "$CHECKOUT_DIR" status --porcelain 2>/dev/null || true)
  if [ -n "$status" ]; then
    echo "[c4-mcp-wrapper] checkout ${CHECKOUT_DIR} has uncommitted changes BEFORE install:" >&2
    echo "$status" >&2
    die "refusing to pull/install on top of a dirty c4 checkout; commit, discard, or wipe ${CHECKOUT_DIR} and retry"
  fi
}

post_install_dirty_check() {
  local status
  status=$(git -C "$CHECKOUT_DIR" status --porcelain 2>/dev/null || true)
  if [ -n "$status" ]; then
    echo "[c4-mcp-wrapper] checkout ${CHECKOUT_DIR} became dirty AFTER npm ci:" >&2
    echo "$status" >&2
    die "npm ci or postinstall modified tracked files — file an upstream issue against cp-c4-architecture and wipe ${CHECKOUT_DIR} to recover"
  fi
}

pull_if_stale() {
  local now last age
  now=$(date +%s)
  if [ -f "$LAST_PULL_FILE" ]; then
    last=$(stat_mtime "$LAST_PULL_FILE")
  else
    last=""
  fi
  if [ -n "$last" ]; then
    age=$((now - last))
    if [ "$age" -lt "$PULL_STALENESS_SECONDS" ]; then
      return 0
    fi
  fi
  # stdout → stderr (MCP stdio protection); stderr already tee'd to wrapper.log.
  if ! git -C "$CHECKOUT_DIR" pull --ff-only --quiet >&2; then
    die "git pull --ff-only failed in ${CHECKOUT_DIR}; upstream may have diverged — inspect manually or wipe the checkout and retry"
  fi
  mkdir -p "$STATE_DIR"
  touch "$LAST_PULL_FILE"
}

install_if_needed() {
  local pkg_lock="${CHECKOUT_DIR}/package-lock.json"
  local pkg_json="${CHECKOUT_DIR}/package.json"
  local sentinel="${CHECKOUT_DIR}/node_modules/.package-lock.json"

  local need_install=0
  if [ ! -d "${CHECKOUT_DIR}/node_modules" ]; then
    need_install=1
  elif [ ! -f "$sentinel" ]; then
    need_install=1
  elif [ "$pkg_lock" -nt "$sentinel" ]; then
    need_install=1
  elif [ "$pkg_json" -nt "$sentinel" ]; then
    need_install=1
  fi

  if [ "$need_install" -eq 0 ]; then
    return 0
  fi

  # npm_config_cache MUST be exported BEFORE `npm ci` so the first-run
  # tarballs land in the plugin-managed cache, not the developer's global
  # npm cache. Notes file "Wrapper flow" step 5.
  export npm_config_cache="$NPM_CACHE_DIR"
  mkdir -p "$NPM_CACHE_DIR"

  # npm ci writes installation progress and postinstall output to stdout.
  # We're about to `exec npm run mcp` as the MCP stdio transport, so any
  # stdout bytes here would pollute the JSON-RPC handshake. Send all output
  # to stderr; the log tee set up by setup_logging captures it in
  # wrapper.log for post-mortem.
  #
  # --ignore-scripts skips the root project's `postinstall` (which runs
  # `likec4 gen model` and triggers a full view-layout pass needing the
  # native `dot` binary from graphviz — a dependency the MCP runtime does
  # not need). `npm rebuild` afterwards runs the lifecycle scripts for
  # packages in node_modules (e.g. esbuild's native binary install) but
  # NOT for the root package, so we get working native binaries without
  # triggering upstream's model codegen.
  if ! ( cd "$CHECKOUT_DIR" && npm ci --no-audit --no-fund --prefer-offline --ignore-scripts ) >&2; then
    die "npm ci failed in ${CHECKOUT_DIR}; pull the latest cp-c4-architecture commit (a stale package-lock.json may have drifted from package.json) and retry"
  fi
  if ! ( cd "$CHECKOUT_DIR" && npm rebuild --no-audit --no-fund ) >&2; then
    die "npm rebuild failed in ${CHECKOUT_DIR}; a dependency's install script could not complete — inspect ${WRAPPER_LOG} and retry"
  fi
}

verify_binary_and_script() {
  local bin="${CHECKOUT_DIR}/node_modules/.bin/likec4-mcp-server"
  if [ ! -x "$bin" ]; then
    die "expected ${bin} after npm ci — check that cp-c4-architecture@main declares @likec4/mcp in devDependencies and that the mcp script exists in package.json scripts"
  fi
  if ! jq -e '.scripts.mcp' "${CHECKOUT_DIR}/package.json" >/dev/null 2>&1; then
    die "cp-c4-architecture/package.json is missing the required \"mcp\": \"likec4-mcp-server\" script entry"
  fi
}

launch_server() {
  export LIKEC4_WORKSPACE="$CHECKOUT_DIR"
  cd "$CHECKOUT_DIR"
  exec npm run --silent mcp -- --no-watch
}

# ---------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------
main() {
  require_dependencies
  mkdir -p "$STATE_DIR" "$LOGS_DIR"
  setup_logging

  if ! acquire_lock "$WRAPPER_LOCKDIR"; then
    die "could not acquire ${WRAPPER_LOCKDIR} after 180s; another process appears to hold it — retry in a moment or check ${WRAPPER_LOG}"
  fi
  trap 'release_lock "$WRAPPER_LOCKDIR"' EXIT INT TERM

  gc_state_dir
  ensure_checkout
  pre_install_dirty_check
  pull_if_stale
  install_if_needed
  post_install_dirty_check
  verify_binary_and_script

  # Release the lock BEFORE exec so a second instance can proceed as soon as
  # the first one is past install. exec replaces the shell, so the EXIT trap
  # would never fire; release explicitly here.
  release_lock "$WRAPPER_LOCKDIR"
  trap - EXIT INT TERM

  launch_server
}

main "$@"
