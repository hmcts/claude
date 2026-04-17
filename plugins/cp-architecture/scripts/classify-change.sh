#!/usr/bin/env bash
#
# classify-change.sh — cp-architecture PostToolUse classifier.
#
# Fired by Claude Code on PostToolUse with matcher Edit|Write|MultiEdit,
# after every tool-driven edit. This script is a ROUTER, not a reasoner:
# it decides whether the edited file is structurally interesting and, if
# so, records the edit in the turn-state file and injects a non-blocking
# `additionalContext` message for Claude's next turn. All LikeC4
# reasoning stays in the exploring-cp-architecture skill — keeping this
# script within the latency budgets is load-bearing.
#
# Contract / rationale:
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-design.md
#     "PostToolUse hook — per-edit warning" section
#   docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md
#     "Hook JSON shapes" + "Classifier language" + "Turn state contract"
#
# Latency budgets (notes Task 0.8):
#   - quiet path (no glob match):     < 100ms
#   - warn  path (match + emit):      < 500ms

set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Dynamic source paths: shellcheck cannot resolve ${SCRIPT_DIR} at lint
# time, so SC1091 ("Not following") fires by default. The source=…
# directive below points shellcheck at the resolved path when it is
# invoked with -x, and the inline disable keeps plain `shellcheck`
# clean without requiring the -x flag or an -e exclusion at the CLI.
# shellcheck source=lib/require-jq.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/require-jq.sh"
# shellcheck source=lib/turn-state.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/turn-state.sh"

INPUT=$(cat)

# Drift mode gate (notes "Drift mode" section). In `off` mode the
# classifier is fully inert: no glob match, no state write, no
# additionalContext. The `.c4` edit-deny hook is a separate script
# and is NOT affected by this gate.
MODE=$(ts_drift_mode)
if [ "$MODE" = "off" ]; then
  exit 0
fi

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
FILE_PATH=$(printf '%s' "$INPUT"  | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Glob matching (design spec "PostToolUse hook — per-edit warning").
# We use bash `case` patterns, which are fnmatch-style globs — fast, no
# subshell fork, and matches the exact list in the design spec.
# ---------------------------------------------------------------------------
matches_any_glob() {
  case "$1" in
    *pom.xml)                             return 0 ;;
    *build.gradle)                        return 0 ;;
    *application.yml|*application.yaml)   return 0 ;;
    *EventSource.java)                    return 0 ;;
    *Client.java)                         return 0 ;;
    *Producer.java)                       return 0 ;;
    *Consumer.java)                       return 0 ;;
    */src/raml/*)                         return 0 ;;
    */src/main/resources/json/schema/*)   return 0 ;;
    */db/changelog/*)                     return 0 ;;
  esac
  return 1
}

if ! matches_any_glob "$FILE_PATH"; then
  # Quiet path: file is not structurally interesting. No JSON, no state
  # write. This is the common case and it must be effectively free.
  exit 0
fi

# ---------------------------------------------------------------------------
# Probe the edit payload. We need BOTH sides of the diff so we can
# detect the "only the version changed" case (see classify() below).
#
#   Edit      → tool_input.old_string / tool_input.new_string
#   MultiEdit → tool_input.edits[].old_string / new_string (list)
#   Write     → tool_input.content only; no old side exists. In that
#               case OLD_TEXT is empty and the classifier treats the
#               payload as a fresh authoring case.
#
# Concatenate each side with a separator so MultiEdits are handled
# uniformly. The classifier only scans for signal tokens — it never
# parses structure — so concatenation is lossless for its purposes.
# ---------------------------------------------------------------------------
NEW_TEXT=$(printf '%s' "$INPUT" | jq -r '
  ([.tool_input.new_string, .tool_input.content]
   + ((.tool_input.edits // []) | map(.new_string)))
  | map(select(. != null and . != ""))
  | join("\n")
')
OLD_TEXT=$(printf '%s' "$INPUT" | jq -r '
  ([.tool_input.old_string]
   + ((.tool_input.edits // []) | map(.old_string)))
  | map(select(. != null and . != ""))
  | join("\n")
')

# ---------------------------------------------------------------------------
# Per-path classification. Outcomes:
#   quiet  → file type matched but the change is structurally uninteresting
#   warn   → generic structural edit; ask Claude to check the model
#   strong → high-signal change (new @Handles, new cross-context client,
#            new outbound producer); instruct Claude to run the skill in
#            check-mode before proceeding
# ---------------------------------------------------------------------------

# Strip `<version>…</version>` pairs from a pom payload. Used to detect
# "the only difference between old and new is inside the version tag".
# POSIX sed with a single class-based pattern — no backrefs, no ERE.
strip_pom_versions() {
  printf '%s' "$1" | sed -e 's|<version>[^<]*</version>||g'
}

classify() {
  local p="$1"
  local new_text="$2"
  local old_text="$3"

  case "$p" in
    *pom.xml)
      # The spec's intent: a bare version bump on an existing dependency
      # (`<version>1.2.3</version>` → `<version>1.2.4</version>`) is quiet
      # even if the Edit payload happens to contain the whole enclosing
      # `<dependency>` block. Many editors, including Claude's own Edit
      # tool, replace the full block rather than just the version tag —
      # so a `<groupId>` presence check is NOT sufficient to mean "new
      # coordinate".
      #
      # Correct test: strip `<version>…</version>` from both sides of
      # the diff. If old and new are then identical, the only thing that
      # changed was inside a version tag → quiet. Otherwise the edit
      # touched a coordinate, a scope, a new dependency, or any other
      # structural element → warn.
      #
      # ACCEPTED v1 GAP: this means a version-only bump on an existing
      # inter-context dependency (e.g. cp-context-scheduling-client
      # 1.12.0 → 2.0.0) is quiet — no warning, no turn-state write, no
      # stop-hook block. The relationship already exists in the C4 model;
      # what changes is the contract version, which is better caught by
      # API-contract checks than the architecture drift pipeline. The
      # skill text still lists "version bump" in the Check-mode triggers,
      # so a developer who reads the skill can invoke Check mode manually.
      # If this gap proves too wide in practice, the fix is to make this
      # branch coordinate-aware for cp-context-* groupIds.
      if [ -n "$old_text" ]; then
        if [ "$(strip_pom_versions "$old_text")" = "$(strip_pom_versions "$new_text")" ]; then
          printf 'quiet'; return
        fi
        printf 'warn'; return
      fi
      # Write (whole-file rewrite) has no old side to diff against.
      # Rare in practice; we warn on any rewrite that mentions a
      # coordinate, and keep a bare `<version>` payload quiet.
      if printf '%s' "$new_text" | grep -q '<groupId>'; then
        printf 'warn'; return
      fi
      if printf '%s' "$new_text" | grep -q '<version>'; then
        printf 'quiet'; return
      fi
      printf 'warn'; return
      ;;

    *build.gradle)
      printf 'warn'; return
      ;;

    *application.yml|*application.yaml)
      printf 'warn'; return
      ;;

    *EventSource.java|*Client.java|*Producer.java|*Consumer.java)
      # Strong-warn signals: an Edit/Write that introduces (a) a new
      # @Handles event subscription, (b) a new @RestClient/@RegisterRest-
      # Client cross-context client binding, or (c) a new outbound
      # producer class-level annotation. Any of these mean the relationship
      # graph has almost certainly changed.
      if printf '%s' "$new_text" | grep -qE '@Handles|@RegisterRestClient|@RestClient\b'; then
        printf 'strong'; return
      fi
      printf 'warn'; return
      ;;

    */src/raml/*|*/src/main/resources/json/schema/*)
      printf 'warn'; return
      ;;

    */db/changelog/*)
      printf 'warn'; return
      ;;
  esac
  printf 'quiet'
}

LEVEL=$(classify "$FILE_PATH" "$NEW_TEXT" "$OLD_TEXT")

if [ "$LEVEL" = "quiet" ]; then
  exit 0
fi

case "$LEVEL" in
  warn)
    MESSAGE="[architecture] Structural edit at ${FILE_PATH}. Check the C4 model with the exploring-cp-architecture skill for affected relationships before continuing."
    ;;
  strong)
    MESSAGE="[architecture] Strong signal in ${FILE_PATH}: this edit introduces a cross-context handler, client, or producer. Run the exploring-cp-architecture skill in check-mode against the affected element and report findings before proceeding."
    ;;
  *)
    exit 0
    ;;
esac

# Record the structural edit in the turn-state file. One write; atomic
# under the turn-state lockdir. If this soft-fails, we still emit the
# context — a hook infra error must never silence a genuine warning.
if [ -n "$SESSION_ID" ]; then
  ts_record_write "$SESSION_ID" "latest_structural_edit_seq" "latest_structural_edit_at" || true
fi

# Emit the PostToolUse additionalContext shape verified in notes Task 0.2.
# Plain stdout from PostToolUse is NOT seen by Claude; only
# hookSpecificOutput.additionalContext reaches the next turn.
jq -nc \
  --arg msg "$MESSAGE" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'

exit 0
