#!/usr/bin/env bash
# Record a human-gate decision against a pipeline stage.
#
# Gate rejection rate is the one metric in the framework that nothing
# off-the-shelf produces, and the only direct quality signal for each agent.
# It cannot be inferred reliably from tool calls, so it is recorded explicitly
# — by the `/gate` command, or by hand.
#
# Usage:
#   record-gate.sh <stage> <accept|edit|reject> [reason-code]
#
# Stages:  requirements architecture user-story test-specs code
#          code-review build-test deploy-sandbox
# Reasons: incomplete wrong-pattern missed-standard hallucinated
#          style scope-creep other        (optional, fixed vocabulary)
#
# Free text is not accepted — commit messages and logs are permanent, and the
# hard rule against PII and case data applies here too.

set -uo pipefail

STAGES="requirements architecture user-story test-specs code code-review build-test deploy-sandbox"
DECISIONS="accept edit reject"
REASONS="incomplete wrong-pattern missed-standard hallucinated style scope-creep other"

usage() {
  cat >&2 <<EOF
usage: record-gate.sh <stage> <decision> [reason]

  stage     one of: $STAGES
  decision  one of: $DECISIONS
  reason    optional, one of: $REASONS

  accept  the artefact was used as produced
  edit    the artefact was usable but needed changes
  reject  the artefact was discarded or redone
EOF
  exit 64
}

in_set() { grep -qw -- "$2" <<<"$1"; }

stage="${1:-}"; decision="${2:-}"; reason="${3:-}"
[[ -z "$stage" || -z "$decision" ]] && usage
in_set "$STAGES" "$stage" || { echo "error: unknown stage '$stage'" >&2; usage; }
in_set "$DECISIONS" "$decision" || { echo "error: unknown decision '$decision'" >&2; usage; }
if [[ -n "$reason" ]]; then
  in_set "$REASONS" "$reason" || { echo "error: unknown reason '$reason'" >&2; usage; }
fi

[[ "${CPP_HARNESS_TELEMETRY:-on}" == "off" ]] && { echo "telemetry off — not recorded"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 69; }

STATE_DIR="${CPP_HARNESS_STATE_DIR:-$HOME/.cpp-harness}"
LOG_DIR="$STATE_DIR/events"
mkdir -p "$LOG_DIR" || exit 74

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
repo="$([[ -n "$repo_root" ]] && basename "$repo_root" || echo "")"
branch="$([[ -n "$repo_root" ]] && git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

install_id="$(tr -cd 'a-fA-F0-9' <"$STATE_DIR/installation-id" 2>/dev/null | tr 'A-F' 'a-f' | cut -c1-12)"

session=""
if [[ -n "$repo_root" ]]; then
  key="$(printf '%s' "$repo_root" | shasum | cut -c1-16)"
  pointer="$STATE_DIR/by-repo/$key.json"
  [[ -f "$pointer" ]] && session="$(jq -r '.session // empty' "$pointer" 2>/dev/null)"
fi

jq -c -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sid "$session" --arg inst "$install_id" --arg repo "$repo" --arg branch "$branch" \
  --arg stage "$stage" --arg decision "$decision" --arg reason "$reason" \
  '{ts:$ts, event:"gate_decision", session:$sid, install:$inst, repo:$repo, branch:$branch,
    stage:$stage, decision:$decision, reason:$reason}' \
  >>"$LOG_DIR/events-$(date -u +%Y-%m).jsonl" || exit 74

echo "recorded: $stage → $decision${reason:+ ($reason)}"
