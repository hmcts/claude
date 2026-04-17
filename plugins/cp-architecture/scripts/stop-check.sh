#!/usr/bin/env bash
#
# stop-check.sh — cp-architecture Stop hook.
#
# Fired by Claude Code on Stop (no matcher — Stop hooks always run).
# Purpose in `block` mode: catch the case where a structural edit
# happened this turn but no `cp-c4-architecture` MCP check followed
# it. When caught, block the turn once, forcing Claude to run the
# exploring-cp-architecture skill in check-mode before the turn can
# complete.
#
# In `off` and `warn` modes this hook never blocks. It still runs on
# every Stop so that turn-state cleanup happens on the same code path
# regardless of mode — see the delete matrix in the notes file.
# CP_ARCHITECTURE_DRIFT_MODE is the runtime switch; unset/invalid
# values default to `warn`.
#
# Correctness hinges on a strict ORDERING comparison, not merely on
# "an edit happened" and "a check happened". If Claude checked the
# model earlier in the turn (e.g. answering a question) and THEN made a
# structural edit, both markers would exist and a naive presence check
# would incorrectly allow completion. The Task 5.1 turn state contract
# defines a monotonic `seq` counter for exactly this reason — the
# comparison is `latest_c4_check_seq > latest_structural_edit_seq`, an
# integer comparison, not a wall-clock comparison. Second-precision
# timestamps cannot resolve events inside the same second and BSD
# `date` lacks `%N` (notes Task 0.9), so wall-clock was never a viable
# primitive.
#
# Contract / rationale:
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-design.md
#     "Stop hook — missed-check catch" section — reason wording here
#     is verbatim.
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md
#     "Turn state contract" (Phase 5 Task 5.1) — decision tree and
#     delete matrix live there; this script implements them verbatim.

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

SESSION_ID=$(printf '%s' "$INPUT"  | jq -r '.session_id // empty')
STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')
MODE=$(ts_drift_mode)

# --- yield path ---------------------------------------------------------
# stop_hook_active == true means this is the second Stop of a turn-
# recovery loop. The first Stop already blocked (or allowed); we must
# NOT block again — the loop-prevention rule from notes Hook JSON
# shapes section. Delete the state file so the next turn starts clean.
#
# The yield check runs BEFORE the mode gate so a block-mode session
# that recovered into warn mode mid-flight still yields correctly.
# See notes "Mode-gate ordering matters" block in the Stop-hook
# decision tree.
if [ "$STOP_ACTIVE" = "true" ]; then
  if [ -n "$SESSION_ID" ]; then
    ts_delete "$SESSION_ID"
  fi
  exit 0
fi

# --- allow_nonblock_mode path ------------------------------------------
# In `off` and `warn` modes the Stop hook is never an enforcement point.
# The classifier may have written structural-edit state (warn mode still
# records for diagnostics / mode-flip support), but this hook must NOT
# emit `decision: "block"`. Delete any leftover state so the next turn
# starts fresh regardless of mode.
if [ "$MODE" != "block" ]; then
  if [ -n "$SESSION_ID" ]; then
    ts_delete "$SESSION_ID"
  fi
  exit 0
fi

# --- block-mode decision tree ------------------------------------------
# From here on, MODE == "block". Everything below is gated on that.

# No session id → cannot locate state. Allow-through.
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Read state without holding the lock; atomic-rename writes guarantee
# the reader sees either the full pre-write or full post-write file.
STATE=$(ts_read "$SESSION_ID")

EDIT_SEQ=$(printf '%s' "$STATE"  | jq -r '.latest_structural_edit_seq // empty')
CHECK_SEQ=$(printf '%s' "$STATE" | jq -r '.latest_c4_check_seq // empty')

# allow_no_state / allow_no_edit: nothing to enforce on. Delete leftover
# state (from e.g. a stray MCP-check-only write) so the next turn is
# clean.
if [ -z "$EDIT_SEQ" ]; then
  ts_delete "$SESSION_ID"
  exit 0
fi

# allow_covered: integer comparison is the strict ordering primitive.
# Absent CHECK_SEQ behaves as -infinity and falls through to
# block_uncovered below.
if [ -n "$CHECK_SEQ" ] && [ "$CHECK_SEQ" -gt "$EDIT_SEQ" ] 2>/dev/null; then
  ts_delete "$SESSION_ID"
  exit 0
fi

# --- block_uncovered ---------------------------------------------------
# CRITICAL INVARIANT: do NOT delete state on the block path. Deleting
# here would let Claude unblock by doing nothing, which defeats the
# entire mechanism. State persists across the block → recovery → re-Stop
# cycle; the recovery Stop either sees a fresh check (allow_covered,
# deletes) or sees stop_hook_active=true (yield path, deletes).
REASON="[architecture] Structural edits were made this turn but the C4 model was not checked. Run the exploring-cp-architecture skill in check-mode for the affected changes, then complete the turn."

jq -nc \
  --arg reason "$REASON" \
  '{decision: "block", reason: $reason}'

exit 0
