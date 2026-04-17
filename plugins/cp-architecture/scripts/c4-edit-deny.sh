#!/usr/bin/env bash
#
# c4-edit-deny.sh — cp-architecture PreToolUse safety hook.
#
# Fired by Claude Code on PreToolUse with matcher Edit|Write|MultiEdit.
# Denies writes that target a `.c4` file INSIDE the plugin-managed
# checkout at ${CLAUDE_PLUGIN_DATA}/cp-c4-architecture/.
#
# Why narrow the scope: this plugin loads across every CP repo a
# developer opens. A developer may legitimately hold their own clone of
# cp-c4-architecture on disk and run the `c4-model-maintenance` skill
# against it to author the LikeC4 model. A global block on `.c4` edits
# would fight that workflow. Scoping the block to the plugin-managed
# checkout only protects OUR mirror (which is read-only plugin state
# overwritten by pulls) without interfering with legitimate authoring.
#
# Contract / rationale:
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-design.md
#     "PreToolUse hook — block .c4 edits inside the plugin-managed
#      checkout" section.
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md
#     "Hook JSON shapes" → PreToolUse deny shape (Task 0.2).

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Dynamic source path; see classify-change.sh for the rationale on the
# paired source= / disable=SC1091 comments.
# shellcheck source=lib/require-jq.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/require-jq.sh"

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path → allow-through (not our concern).
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only .c4 files are candidates.
case "$FILE_PATH" in
  *.c4) ;;
  *) exit 0 ;;
esac

# Only files inside the plugin-managed checkout are denied. CLAUDE_PLUGIN_DATA
# is exported to hook processes by the harness (notes Task 0.3); if it is
# missing we cannot confidently identify the plugin checkout path, so we
# fall through to allow — a hook infra error must never block the user.
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  exit 0
fi

CHECKOUT_DIR="${CLAUDE_PLUGIN_DATA}/cp-c4-architecture/"

case "$FILE_PATH" in
  "${CHECKOUT_DIR}"*) ;;   # target is inside the plugin checkout → deny
  *) exit 0 ;;              # anywhere else on disk → allow
esac

# Emit the PreToolUse deny shape verified in notes Task 0.2. The reason
# wording is taken verbatim from the design spec. Exit 0 + JSON on stdout
# is honoured; exit 2 would also block but is reserved for "hook failed".
REASON="This file is inside the plugin-managed c4 model checkout, which is read-only plugin state. If you intended to edit the LikeC4 model, open the real cp-c4-architecture repository and use the c4-model-maintenance skill."

jq -nc \
  --arg reason "$REASON" \
  '{hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
   }}'

exit 0
