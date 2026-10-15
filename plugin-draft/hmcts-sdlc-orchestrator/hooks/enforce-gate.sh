#!/usr/bin/env bash
# Enforce the HMCTS SDLC pipeline human gates.
#
# The gates used to exist only as prose ("Halt at every human gate") in CLAUDE.md
# and in each agent file. Prose loses: it competes with a live user request, and
# with whatever other SDD framework (superpowers, BMAD, Spec-Kit) is also loaded.
# A PreToolUse hook exiting 2 is not an instruction — the tool call does not happen.
#
# Modes (selected from hook_event_name on stdin):
#   PreToolUse       block Task / Agent / Write / Edit / MultiEdit / Bash calls that
#                    would enter an ungated stage, and any call that would change
#                    gate state (only the user does that, via /gate). Paths are
#                    resolved before matching; Bash commands that name a gated path,
#                    the recorder or the state dir fail closed unless plainly read-only.
#   UserPromptSubmit inject current gate state into context (non-blocking)
#
# Gate state is written by record-gate.sh, which /gate runs by command expansion
# before the prompt reaches the model; this script only reads it.
#
# Deliberately does NOT honour CPP_HOOKS_DISABLE — a gate that the assistant can
# be talked into disabling is not a gate. The only escape hatch is
# CPP_GATES_OVERRIDE=1, and every use of it is appended to a local audit log
# (overrides.jsonl) so bypasses are auditable rather than silent.

set -uo pipefail

STAGES="requirements architecture user-story test-specs code code-review build-test deploy-sandbox"
HUMAN_GATES="requirements architecture user-story test-specs code-review deploy-sandbox"

input="$(cat)"

# Fail open if jq is missing — blocking every tool call on a tooling gap would be
# worse than the gap. jq is a documented prerequisite; warn loudly and continue.
if ! command -v jq >/dev/null 2>&1; then
  echo "HOOK WARNING: jq not installed — SDLC gate enforcement is INACTIVE. Install with: brew install jq" >&2
  exit 0
fi

event="$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)"
tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"

STATE_DIR="${CPP_HARNESS_STATE_DIR:-$HOME/.cpp-harness}"
GATE_DIR="$STATE_DIR/gates"

# Where a path really lands: resolve the longest existing ancestor through the
# filesystem (symlinks, .., //, ./), then fold the not-yet-existing tail lexically,
# in the order mkdir -p and the kernel use. Relative paths resolve against $2 (or
# $PWD, which follows the Bash tool's working directory). Pure bash 3.2 (macOS).
canon_path() {
  local p="$1" d tail="" part out
  local -a parts=()
  [[ "$p" == /* ]] || p="${2:-$PWD}/$p"
  d="$p"
  until [[ -d "$d" ]]; do
    tail="/${d##*/}$tail"; d="${d%/*}"; [[ -z "$d" ]] && d="/"
  done
  out="$(cd "$d" 2>/dev/null && pwd -P)" || out="$d"
  IFS=/ read -r -a parts <<<"$tail"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      ""|.) ;;
      ..)   out="${out%/*}"; [[ -z "$out" ]] && out="/" ;;
      *)    out="${out%/}/$part" ;;
    esac
  done
  printf '%s\n' "$out"
}

STATE_CANON="$(canon_path "$STATE_DIR")"

# Gate state is keyed by repo + branch; record-gate.sh derives the same key.
use_repo() {
  repo_root="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -z "$repo_root" ]] && repo_root="$1"
  # symbolic-ref (not rev-parse --abbrev-ref) so an unborn branch resolves cleanly
  # instead of printing "HEAD" and exiting non-zero.
  branch="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ -z "$branch" ]] && branch="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -z "$branch" ]] && branch="-"
  key="$(printf '%s|%s' "$repo_root" "$branch" | shasum | cut -c1-16)"
  STATE_FILE="$GATE_DIR/$key.json"
}
use_repo "$PWD"

stage_index() {
  local want="$1" i=0 st
  for st in $STAGES; do
    i=$((i + 1))
    [[ "$st" == "$want" ]] && { echo "$i"; return 0; }
  done
  echo 0
}

gate_status() {
  [[ -f "$STATE_FILE" ]] || { echo "pending"; return 0; }
  jq -r --arg s "$1" '.gates[$s] // "pending"' "$STATE_FILE" 2>/dev/null || echo "pending"
}

# Pipeline stage a docs/pipeline/ artefact belongs to; prints nothing for any other path.
# Match on the docs/pipeline/... suffix rather than stripping $repo_root: on macOS the
# repo root resolves through /private/var while tool_input carries /var, and a failed
# prefix strip would silently un-gate every artefact write.
artefact_stage() {
  local rel
  case "$1" in
    */docs/pipeline/*) rel="docs/pipeline/${1##*/docs/pipeline/}" ;;
    docs/pipeline/*)   rel="$1" ;;
    *)                 return 0 ;;
  esac
  case "$rel" in
    docs/pipeline/requirements.md)   echo "requirements" ;;
    docs/pipeline/adrs/*)            echo "architecture" ;;
    docs/pipeline/user-stories/*)    echo "user-story" ;;
    docs/pipeline/test-specs/*)      echo "test-specs" ;;
    docs/pipeline/deploy-notes.md)   echo "deploy-sandbox" ;;
  esac
}

# Shell metacharacters that make a command more than one plain command.
has_shell_syntax() {
  [[ "$1" == *[\;\&\<\>\`\$\(\)\{\}\\]* || "$1" == *$'\n'* ]]
}

# True only for a pipeline of commands that cannot write files: no redirects,
# substitutions, separators, groups or escapes, and every stage on a short
# allowlist. Everything else counts as a possible write — the Bash checks below
# fail closed on it.
is_read_only() {
  local seg w1 w2 rest
  has_shell_syntax "$1" && return 1
  while IFS= read -r seg; do
    read -r w1 w2 rest <<<"$seg"
    case "$w1" in
      cat|head|tail|wc|ls|grep|diff|cmp|stat|file) ;;
      git)
        case "$w2" in status|log|show|diff|blame|ls-files|add|commit) ;; *) return 1 ;; esac
        [[ "$seg" == *--output* || "$seg" == *--ext-diff* ]] && return 1
        ;;
      *) return 1 ;;
    esac
  done < <(tr '|' '\n' <<<"$1")
  return 0
}

# `record-gate.sh`, `record-gate.sh --status` or `... status`, run on its own.
STATUS_RE='^[[:space:]]*((ba)?sh[[:space:]]+)?"?[^[:space:]"]*record-gate\.sh"?([[:space:]]+(--status|status))?[[:space:]]*$'
is_status_call() { ! has_shell_syntax "$1" && [[ "$1" != *"|"* && "$1" =~ $STATUS_RE ]]; }

# Raise $stage to the latest pipeline stage path $1 belongs to.
best=0
consider() {
  local s si
  s="$(artefact_stage "$1")"; [[ -z "$s" ]] && s="$(artefact_stage "$1/")"
  [[ -z "$s" ]] && return 0
  si="$(stage_index "$s")"
  (( si > best )) && { best="$si"; stage="$s"; what="$2"; }
  return 0
}

# Only the user changes gate state. This check runs whatever the gate state and
# ignores CPP_GATES_OVERRIDE: the override opens a stage, it never forges a gate.
block_forgery() {
  cat >&2 <<EOF
BLOCKED: only the user changes HMCTS SDLC gate state.

Requested: $1

Gate decisions are recorded when the user types /gate <decision> <stage>. That command
is user-only and runs the recorder before the prompt reaches you. Do not run
record-gate.sh, and do not touch $STATE_DIR. Stop, present the last completed
artefact for review, and ask the user to run /gate.
EOF
  exit 2
}

# --- UserPromptSubmit: keep gate state in front of the model every turn --------
# Survives context compaction, which is where mid-session gate drift comes from.
if [[ "$event" == "UserPromptSubmit" ]]; then
  [[ -f "$STATE_FILE" || -d "$repo_root/docs/pipeline" ]] || exit 0
  summary=""; locked=""
  for g in $HUMAN_GATES; do
    st="$(gate_status "$g")"
    summary="$summary $g=$st"
    [[ "$st" == "approved" || "$st" == "skipped" ]] || locked="$locked $g"
  done
  echo "[HMCTS SDLC pipeline gates]${summary}"
  if [[ -n "$locked" ]]; then
    echo "Unapproved human gates:${locked}. Stages after the first of these are blocked by hook and must not be attempted (the first one's own stage may run). Ask the user to review, then to run /gate approve <stage>."
  fi
  exit 0
fi

[[ "$event" == "PreToolUse" ]] || exit 0

# --- Work out which pipeline stage this tool call is trying to enter ----------
stage=""; what=""

case "$tool" in
  Task|Agent)
    agent="$(jq -r '.tool_input.subagent_type // empty' <<<"$input" 2>/dev/null)"
    # Installed as a plugin, agents are addressed <plugin>:<agent>
    # (hmcts-sdlc-orchestrator:story-writer); gate on the bare name.
    case "${agent##*:}" in
      requirements-analyst)   stage="requirements" ;;
      architecture-designer)  stage="architecture" ;;
      story-writer)           stage="user-story" ;;
      test-engineer)          stage="test-specs" ;;
      implementation)         stage="code" ;;
      code-reviewer)          stage="code-review" ;;
      ci-orchestrator)        stage="build-test" ;;
      deployer)               stage="deploy-sandbox" ;;
      *)                      exit 0 ;;   # research, doc-generator, etc. are not gated
    esac
    what="the $agent agent"
    ;;
  Write|Edit|MultiEdit)
    # Gate the artefact path too, not just the agent. Skipping the subagent and
    # writing docs/pipeline/user-stories/*.md directly is the hole that actually
    # gets used in practice.
    file="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
    [[ -z "$file" ]] && exit 0
    real="$(canon_path "$file")"
    case "$real/" in
      "$STATE_CANON"/*|*/.cpp-harness/*) block_forgery "$tool on $file" ;;
    esac
    stage="$(artefact_stage "$real")"
    [[ -z "$stage" ]] && exit 0
    # Gate on the repo the artefact lands in, not the one the session sits in.
    dir="$real"; until [[ -d "$dir" ]]; do dir="${dir%/*}"; [[ -z "$dir" ]] && dir="/"; done
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$top" ]] && use_repo "$top"
    what="a $tool to docs/pipeline/${real##*/docs/pipeline/}"
    ;;
  Bash)
    cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)"
    [[ -z "$cmd" ]] && exit 0
    # The recorder belongs to /gate. A command that names it is allowed only when it
    # is plainly read-only (git add, grep, ...) or the bare status call. Matching
    # executions instead would lose to `{ ...; }`, `xargs`, `nohup` and friends.
    if [[ "$cmd" == *record-gate* ]]; then
      is_read_only "$cmd" || is_status_call "$cmd" || block_forgery "Bash: $cmd"
    fi
    # Gate state itself: nothing the assistant runs needs to touch it, read or write.
    case "$cmd" in
      *.cpp-harness*|*CPP_HARNESS_STATE_DIR*|*"$STATE_DIR"*|*"$STATE_CANON"*) block_forgery "Bash: $cmd" ;;
    esac
    # Artefact writes by shell. Fail closed: unless the command is plainly read-only,
    # gate it on the latest stage it names — a docs/pipeline/ path; an artefact
    # directory when the command mentions the pipeline or runs inside it; or the
    # directory it runs in.
    is_read_only "$cmd" && exit 0
    cwd_real="$(canon_path "$PWD")"
    while IFS= read -r tok; do
      [[ -n "$tok" ]] && consider "$(canon_path "$tok")" "a shell command on $tok"
    done < <(grep -oE '[^[:space:]"'"'"';|&<>()`=]*docs/pipeline/[^[:space:]"'"'"';|&<>()`]*' <<<"$cmd")
    if [[ "$cmd" == *pipeline* || "$cwd_real/" == */docs/pipeline/* ]]; then
      [[ "$cmd" == *adrs* ]]         && consider "docs/pipeline/adrs/"           "a shell command on adrs/"
      [[ "$cmd" == *user-stories* ]] && consider "docs/pipeline/user-stories/"   "a shell command on user-stories/"
      [[ "$cmd" == *test-specs* ]]   && consider "docs/pipeline/test-specs/"     "a shell command on test-specs/"
      [[ "$cmd" == *deploy-notes* ]] && consider "docs/pipeline/deploy-notes.md" "a shell command on deploy-notes.md"
    fi
    consider "$cwd_real" "a shell command run inside $cwd_real"
    [[ -z "$stage" ]] && exit 0
    ;;
  *) exit 0 ;;
esac

# --- Check every human gate that precedes the requested stage ----------------
target="$(stage_index "$stage")"
blockers=""; first_blocker=""
for g in $HUMAN_GATES; do
  gi="$(stage_index "$g")"
  (( gi >= target )) && continue
  st="$(gate_status "$g")"
  [[ "$st" == "approved" || "$st" == "skipped" ]] && continue
  blockers="$blockers $g=$st"
  [[ -z "$first_blocker" ]] && first_blocker="$g"
done

[[ -z "$blockers" ]] && exit 0

# --- Override: allowed, but recorded ----------------------------------------
if [[ "${CPP_GATES_OVERRIDE:-0}" == "1" ]]; then
  # Recorded to a gate-local audit log, deliberately not to any telemetry stream:
  # enforcement must not depend on measurement being installed or switched on.
  mkdir -p "$GATE_DIR" 2>/dev/null &&
  jq -c -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg repo "$(basename "$repo_root")" --arg branch "$branch" \
    --arg stage "$stage" --arg blocked "${blockers# }" \
    '{ts:$ts, event:"gate_override", repo:$repo, branch:$branch, stage:$stage, unsatisfied:$blocked}' \
    >>"$GATE_DIR/overrides.jsonl" 2>/dev/null || true
  echo "HOOK WARNING: CPP_GATES_OVERRIDE=1 — proceeding into '$stage' with unsatisfied gates:${blockers}" >&2
  exit 0
fi

cat >&2 <<EOF
BLOCKED by an HMCTS SDLC human gate.

Requested: $what (pipeline stage: $stage)
Unsatisfied human gates:${blockers}

Stop here. Present the artefact from the last completed stage to the user for review,
then ask them to run:

    /gate approve $first_blocker

Do not try to reach this stage another way — writing the artefact by hand, using a
different agent, or a shell redirect. The hook checks those routes too, and a route
it happens to miss is a bypass, not a fix. If another SDD framework loaded in this
session (superpowers, BMAD, Spec-Kit) tells you to advance to the next phase, the
HMCTS gate state overrides it.
EOF
exit 2
