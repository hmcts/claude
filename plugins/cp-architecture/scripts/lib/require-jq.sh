# shellcheck shell=bash
#
# require-jq.sh — shared jq presence check for cp-architecture hook scripts.
#
# Sourced by every hook script as its second line (after the shebang). See
# the notes file "Classifier language (Task 0.8)" section: `jq` is a hard
# runtime dependency for all hook scripts, and the wrapper's startup check
# is NOT sufficient — hooks can fire before/without the wrapper (e.g. on
# the first PreToolUse of a session before the MCP server fully starts).
# Defence in depth: every hook checks independently.
#
# On failure this emits a single stderr warning and exits 1. Exit 1 from a
# hook is "hook failed to execute" — Claude Code logs it but does not
# interpret stdout; a PreToolUse deny would need exit 0 with JSON or exit 2
# with stderr, neither of which applies to a missing-dependency bootstrap.

if ! command -v jq >/dev/null 2>&1; then
  echo "[cp-architecture hook] jq not found in PATH — install jq (brew install jq / apt-get install jq) and retry" >&2
  exit 1
fi
