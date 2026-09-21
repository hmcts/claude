#!/usr/bin/env bash
# Record a human-gate decision against a pipeline stage.
#
# This is the only thing that changes gate state, and gate state is what
# enforce-gate.sh reads to decide whether the next pipeline stage may start.
# It is invoked by the user through the /gate command — never by the assistant
# to clear its own block.
#
# Usage:
#   record-gate.sh <stage> <accept|approve|edit|reject|skip> [reason-code]
#   record-gate.sh --status
#
# Stages:  requirements architecture user-story test-specs code
#          code-review build-test deploy-sandbox
# Reasons: incomplete wrong-pattern missed-standard hallucinated
#          style scope-creep other        (optional, fixed vocabulary)
#
# Free text is not accepted — the reason is a fixed code. The state file is
# retained and the hard rule against PII and case data applies here too.

set -uo pipefail

STAGES="requirements architecture user-story test-specs code code-review build-test deploy-sandbox"
DECISIONS="accept approve edit reject skip"
REASONS="incomplete wrong-pattern missed-standard hallucinated style scope-creep other"

usage() {
  cat >&2 <<EOF
usage: record-gate.sh <stage> <decision> [reason]
       record-gate.sh --status

  stage     one of: $STAGES
  decision  one of: $DECISIONS
  reason    optional, one of: $REASONS

  accept   the artefact was used as produced          -> gate approved
  approve  alias for accept                           -> gate approved
  edit     the artefact was usable but needed changes -> gate approved
  reject   the artefact was discarded or redone       -> gate rejected, downstream reset
  skip     the stage does not apply to this change    -> gate skipped
EOF
  exit 64
}

in_set() { grep -qw -- "$2" <<<"$1"; }

STATE_DIR="${CPP_HARNESS_STATE_DIR:-$HOME/.cpp-harness}"
GATE_DIR="$STATE_DIR/gates"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$repo_root" ]] && repo_root="$PWD"
repo="$(basename "$repo_root")"
# symbolic-ref (not rev-parse --abbrev-ref) so an unborn branch resolves cleanly
# instead of printing "HEAD" and exiting non-zero.
branch="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[[ -z "$branch" ]] && branch="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || true)"
[[ -z "$branch" ]] && branch="-"
key="$(printf '%s|%s' "$repo_root" "$branch" | shasum | cut -c1-16)"
STATE_FILE="$GATE_DIR/$key.json"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 69; }

# --- status ------------------------------------------------------------------
if [[ "${1:-}" == "--status" ]]; then
  echo "repo: $repo   branch: $branch"
  for s in $STAGES; do
    st="pending"
    [[ -f "$STATE_FILE" ]] && st="$(jq -r --arg s "$s" '.gates[$s] // "pending"' "$STATE_FILE" 2>/dev/null)"
    printf '  %-16s %s\n' "$s" "$st"
  done
  exit 0
fi

stage="${1:-}"; decision="${2:-}"; reason="${3:-}"
[[ -z "$stage" || -z "$decision" ]] && usage
in_set "$STAGES" "$stage" || { echo "error: unknown stage '$stage'" >&2; usage; }
in_set "$DECISIONS" "$decision" || { echo "error: unknown decision '$decision'" >&2; usage; }
if [[ -n "$reason" ]]; then
  in_set "$REASONS" "$reason" || { echo "error: unknown reason '$reason'" >&2; usage; }
fi

# `approve` is a convenience alias; accept/edit/reject/skip stay the recorded
# vocabulary so the decision history is consistent.
[[ "$decision" == "approve" ]] && decision="accept"

case "$decision" in
  accept|edit) gate_state="approved" ;;
  skip)        gate_state="skipped"  ;;
  reject)      gate_state="rejected" ;;
esac

mkdir -p "$GATE_DIR" || exit 74
[[ -f "$STATE_FILE" ]] || printf '{"gates":{}}' >"$STATE_FILE"

# A rejection rewinds the pipeline: every stage after this one returns to pending,
# so an approved-then-invalidated downstream gate cannot keep a later stage unlocked.
downstream=""
if [[ "$gate_state" == "rejected" ]]; then
  seen=0
  for s in $STAGES; do
    if (( seen )); then downstream="$downstream $s"; fi
    [[ "$s" == "$stage" ]] && seen=1
  done
fi

tmp="$STATE_FILE.tmp.$$"
jq --arg repo "$repo" --arg branch "$branch" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg stage "$stage" --arg state "$gate_state" --arg reason "$reason" \
   --arg downstream "$downstream" \
   '.repo = $repo | .branch = $branch | .updated = $ts
    | .gates[$stage] = $state
    | .history = ((.history // []) + [{ts:$ts, stage:$stage, state:$state, reason:$reason}])
    | reduce ($downstream | split(" ") | .[] | select(length > 0)) as $d (.; .gates[$d] = "pending")' \
   "$STATE_FILE" >"$tmp" 2>/dev/null && mv "$tmp" "$STATE_FILE" || { rm -f "$tmp"; echo "error: could not update gate state" >&2; exit 74; }

echo "recorded: $stage -> $decision${reason:+ ($reason)}  [gate: $gate_state]"
[[ -n "$downstream" ]] && echo "reset to pending:${downstream}"
exit 0
