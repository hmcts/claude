#!/usr/bin/env bash
#
# record-c4-check.sh — cp-architecture PreToolUse MCP-check recorder.
#
# Fired by Claude Code on PreToolUse with an MCP-tool-name matcher for
# the `cp-c4-architecture` server (see hooks.json). Purpose: stamp the
# turn-state file with the "check happened" marker so the Stop hook's
# ordering comparison can distinguish a check that covers the latest
# structural edit from one that does not.
#
# This hook is a pure sequence recorder: it writes one field pair in the
# turn-state file and emits NOTHING. The MCP call then proceeds normally.
#
# Contract / rationale:
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-design.md
#     "Stop hook — missed-check catch" section
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md
#     "Turn state contract" (Phase 5 Task 5.1)

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Dynamic source paths; see classify-change.sh for the rationale on the
# paired source= / disable=SC1091 comments.
# shellcheck source=lib/require-jq.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/require-jq.sh"
# shellcheck source=lib/turn-state.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/turn-state.sh"

INPUT=$(cat)

# Drift mode gate (notes "Drift mode" section). In `off` mode the
# MCP check tracker is inert; neither `warn` nor `block` mode needs
# to write state only if we're about to disable the whole pipeline.
# `warn` still records so the ordering data is available for
# diagnostics / tuning and for a mid-session mode flip to `block`.
MODE=$(ts_drift_mode)
if [ "$MODE" = "off" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')

# Without a session id we cannot key the state file. Fail soft — let the
# MCP call proceed.
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# One atomic read-modify-write per the Task 5.1 contract. Same write
# algorithm as the classifier (Task 5.2), differing only in which field
# pair is updated. Soft-fails on infra error — hooks never block the
# edit path.
ts_record_write "$SESSION_ID" "latest_c4_check_seq" "latest_c4_check_at" || true

# No stdout. Let the MCP call proceed.
exit 0
