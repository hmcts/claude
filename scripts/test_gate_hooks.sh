#!/usr/bin/env bash
# Behavioural tests for the SDLC gate hooks (enforce-gate.sh + record-gate.sh).
#
# Runs every case against both copies — .claude/hooks/ and the plugin-draft mirror —
# inside a scratch git repo, with CPP_HARNESS_STATE_DIR pointed at a temp dir so
# nothing under ~/.cpp-harness is touched.
#
# Usage: scripts/test_gate_hooks.sh            (both copies)
#        scripts/test_gate_hooks.sh <hooks-dir> (one copy)
# Exit 0 = all pass; 1 = one or more failures.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -gt 0 ]]; then
  DIRS=()
  for d in "$@"; do DIRS+=("$(cd "$d" && pwd)"); done
else
  DIRS=("$REPO/.claude/hooks" "$REPO/plugin-draft/hmcts-sdlc-orchestrator/hooks")
fi

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "  FAIL: $*"; }

# expect_exit <want> <description> <json>  — pipe json to enforce-gate.sh from the scratch repo
expect_exit() {
  local want="$1" desc="$2" json="$3" got
  (cd "$WORK" && printf '%s' "$json" | "$HOOKS/enforce-gate.sh" >/dev/null 2>&1)
  got=$?
  [[ "$got" == "$want" ]] && ok || bad "$desc — want exit $want, got $got"
}

# expect_exit_in <dir> <want> <description> <json> — same, with the Bash tool's cwd at <dir>
expect_exit_in() {
  local dir="$1" want="$2" desc="$3" json="$4" got
  (cd "$dir" && printf '%s' "$json" | "$HOOKS/enforce-gate.sh" >/dev/null 2>&1)
  got=$?
  [[ "$got" == "$want" ]] && ok || bad "$desc — want exit $want, got $got"
}

task()  { printf '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"subagent_type":"%s"}}' "$1"; }
write() { jq -cn --arg t "$1" --arg f "$2" '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{file_path:$f}}'; }
bash_() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
record() { (cd "$WORK" && "$HOOKS/record-gate.sh" "$@" >/dev/null 2>&1); }
state_of() { (cd "$WORK" && "$HOOKS/record-gate.sh" --status 2>/dev/null | awk -v s="$1" '$1 == s {print $2}'); }

for HOOKS in "${DIRS[@]}"; do
  echo "== ${HOOKS#"$REPO"/}"
  TMP="$(mktemp -d)"
  export CPP_HARNESS_STATE_DIR="$TMP/state"
  WORK="$TMP/repo"
  mkdir -p "$WORK/docs/pipeline" && git -C "$WORK" init -q && git -C "$WORK" checkout -q -b feat/a
  GATES="$CPP_HARNESS_STATE_DIR/gates"

  # --- fresh branch: stage 1 open, everything after it closed -----------------
  expect_exit 0 "requirements-analyst on a fresh branch"   "$(task requirements-analyst)"
  expect_exit 2 "story-writer on a fresh branch"           "$(task story-writer)"
  expect_exit 0 "ungated agent (research)"                 "$(task research)"

  # --- F1: plugin-namespaced agent names are gated the same way ---------------
  expect_exit 2 "plugin:story-writer"   "$(task hmcts-sdlc-orchestrator:story-writer)"
  expect_exit 2 "plugin:implementation" "$(task hmcts-sdlc-orchestrator:implementation)"
  expect_exit 2 "plugin:deployer"       "$(task hmcts-sdlc-orchestrator:deployer)"
  expect_exit 0 "plugin:requirements-analyst" "$(task hmcts-sdlc-orchestrator:requirements-analyst)"
  expect_exit 0 "plugin:research (ungated)"   "$(task hmcts-sdlc-orchestrator:research)"

  # --- artefact writes: Write / Edit / MultiEdit (F3) --------------------------
  expect_exit 2 "Write user story"     "$(write Write "$WORK/docs/pipeline/user-stories/US-1.md")"
  expect_exit 2 "Edit user story"      "$(write Edit "$WORK/docs/pipeline/user-stories/US-1.md")"
  expect_exit 2 "MultiEdit user story" "$(write MultiEdit "$WORK/docs/pipeline/user-stories/US-1.md")"
  expect_exit 2 "Write via ./"         "$(write Write "$WORK/docs/pipeline/./user-stories/US-1.md")"
  expect_exit 2 "Write via //"         "$(write Write "$WORK/docs/pipeline//user-stories/US-1.md")"
  expect_exit 2 "Write via adrs/../"   "$(write Write "$WORK/docs/pipeline/adrs/../user-stories/US-1.md")"
  expect_exit 2 "Write relative path"  "$(write Write "docs/pipeline/user-stories/US-1.md")"
  mkdir -p "$WORK/docs/pipeline/user-stories" && ln -s "$WORK/docs/pipeline/user-stories" "$WORK/stories"
  expect_exit 2 "Write via symlinked dir" "$(write Write "$WORK/stories/US-1.md")"
  ln -s "$WORK/docs/pipeline/user-stories/US-7.md" "$WORK/notes.md"
  expect_exit 2 "Write via symlink file into user-stories" "$(write Write "$WORK/notes.md")"
  expect_exit 2 "Bash quote-split docs path" "$(bash_ "echo hi > docs/pipe''line/user-stories/x.md")"
  expect_exit 0 "Write requirements.md (stage 1)" "$(write Write "$WORK/docs/pipeline/requirements.md")"
  expect_exit 0 "Write outside docs/pipeline"     "$(write Write "$WORK/src/Main.java")"

  # --- artefact writes via Bash (F3, heuristic) --------------------------------
  expect_exit 2 "Bash > redirect"  "$(bash_ 'echo hi > docs/pipeline/user-stories/x.md')"
  expect_exit 2 "Bash >> redirect" "$(bash_ "printf x >>$WORK/docs/pipeline/test-specs/a.feature")"
  expect_exit 2 "Bash tee"         "$(bash_ 'echo hi | tee -a docs/pipeline/adrs/001-x.md')"
  expect_exit 2 "Bash cp into"     "$(bash_ 'cp /tmp/x.md docs/pipeline/user-stories/x.md')"
  expect_exit 0 "Bash read only"   "$(bash_ 'cat docs/pipeline/user-stories/x.md | grep AC')"
  expect_exit 0 "Bash ls"          "$(bash_ 'ls docs/pipeline')"
  expect_exit 0 "Bash unrelated"   "$(bash_ 'git status')"
  expect_exit 2 "Bash sed -i"      "$(bash_ 'sed -i s/a/b/ docs/pipeline/user-stories/x.md')"
  expect_exit 0 "Bash head (read)" "$(bash_ 'head -5 docs/pipeline/user-stories/x.md')"
  expect_exit 0 "Bash grep into /tmp, no gated path named" "$(bash_ 'grep -r AC docs/pipeline > /tmp/out.txt')"
  # Fail closed: anything not on the read-only list that names a locked stage's path is gated.
  expect_exit 2 "Bash sed -n (not on the read-only list)" "$(bash_ 'sed -n 1p docs/pipeline/user-stories/x.md')"
  expect_exit 2 "Bash cp out of a locked stage" "$(bash_ 'cp docs/pipeline/user-stories/x.md /tmp/')"
  expect_exit 2 "Bash python write"  "$(bash_ "python3 -c \"open('docs/pipeline/user-stories/x.md','w')\"")"
  expect_exit 2 "Bash dd of="        "$(bash_ 'dd if=/dev/null of=docs/pipeline/user-stories/x.md')"
  expect_exit 2 "Bash curl -o"       "$(bash_ 'curl -so docs/pipeline/test-specs/a.feature https://example.invalid')"
  expect_exit 2 "Bash ./ in path"    "$(bash_ 'echo hi > docs/pipeline/./user-stories/x.md')"
  expect_exit 2 "Bash cd into pipeline, relative write" "$(bash_ 'cd docs/pipeline && echo hi > user-stories/x.md')"
  mkdir -p "$WORK/docs/pipeline/user-stories"
  expect_exit_in "$WORK/docs/pipeline" 2 "Bash cwd in docs/pipeline, relative write" "$(bash_ 'echo hi > user-stories/x.md')"
  expect_exit_in "$WORK/docs/pipeline/user-stories" 2 "Bash cwd in user-stories, bare write" "$(bash_ 'echo hi > x.md')"
  expect_exit_in "$WORK/docs/pipeline/user-stories" 0 "Bash cwd in user-stories, read" "$(bash_ 'ls')"

  # --- F2: the assistant cannot clear its own gate -----------------------------
  expect_exit 2 "Bash record-gate.sh approve" "$(bash_ '.claude/hooks/record-gate.sh requirements approve')"
  expect_exit 2 "Bash bash record-gate.sh"    "$(bash_ 'bash "$CLAUDE_PLUGIN_ROOT/hooks/record-gate.sh" approve requirements')"
  expect_exit 0 "Bash record-gate.sh --status" "$(bash_ '.claude/hooks/record-gate.sh --status')"
  expect_exit 0 "Bash record-gate.sh (no args = status)" "$(bash_ '.claude/hooks/record-gate.sh')"
  expect_exit 2 "Bash cd && ./record-gate.sh" "$(bash_ 'cd .claude/hooks && ./record-gate.sh approve requirements')"
  expect_exit 2 "Bash bash -c '...record-gate.sh'" "$(bash_ "bash -c '.claude/hooks/record-gate.sh requirements approve'")"
  expect_exit 2 "Bash VAR=x record-gate.sh" "$(bash_ 'X=1 .claude/hooks/record-gate.sh approve requirements')"
  expect_exit 0 "Bash grep record-gate.sh (read-only)" "$(bash_ 'grep -n usage .claude/hooks/record-gate.sh')"
  # git is not on the read-only list: add/status/diff can run configured programs.
  expect_exit 2 "Bash git add naming the recorder" "$(bash_ 'git add .claude/hooks/record-gate.sh')"
  expect_exit 0 "Bash git add of the hooks dir" "$(bash_ 'git add .claude/hooks/')"
  expect_exit 2 "Bash --status chained with a write" "$(bash_ '.claude/hooks/record-gate.sh --status; .claude/hooks/record-gate.sh requirements approve')"
  expect_exit 2 "Bash write to gate state"    "$(bash_ "echo '{}' > ~/.cpp-harness/gates/forged.json")"
  expect_exit 2 "Bash write to \$GATE_DIR"    "$(bash_ "jq . x > $GATES/forged.json")"
  expect_exit 2 "Write to gate state"         "$(write Write "$GATES/forged.json")"
  expect_exit 2 "Edit gate state"             "$(write Edit "$HOME/.cpp-harness/gates/abc.json")"
  mkdir -p "$GATES" && ln -s "$CPP_HARNESS_STATE_DIR" "$TMP/alias"
  expect_exit 2 "Write gate state via ./"      "$(write Write "$CPP_HARNESS_STATE_DIR/./gates/f.json")"
  expect_exit 2 "Write gate state via ../"     "$(write Write "$TMP/nope/../state/gates/f.json")"
  expect_exit 2 "Write gate state via symlink" "$(write Write "$TMP/alias/gates/f.json")"
  expect_exit 2 "Bash { recorder; }"           "$(bash_ '{ .claude/hooks/record-gate.sh approve requirements; }')"
  expect_exit 2 "Bash if/then recorder"        "$(bash_ 'if true; then .claude/hooks/record-gate.sh approve requirements; fi')"
  expect_exit 2 "Bash nohup recorder"          "$(bash_ 'nohup .claude/hooks/record-gate.sh approve requirements')"
  expect_exit 2 "Bash time recorder"           "$(bash_ 'time .claude/hooks/record-gate.sh approve requirements')"
  expect_exit 2 "Bash xargs recorder"          "$(bash_ 'echo approve requirements | xargs .claude/hooks/record-gate.sh')"
  expect_exit 2 "Bash ls state dir"            "$(bash_ 'ls ~/.cpp-harness')"
  expect_exit 2 "Bash cd state dir then write" "$(bash_ "cd ~/.cpp-harness && echo '{}' > gates/f.json")"
  expect_exit 2 "Bash git commit naming the recorder" "$(bash_ 'git commit -m "tidy record-gate.sh"')"
  expect_exit 2 "Bash quote-split recorder"     "$(bash_ ".claude/hooks/rec''ord-gate.sh approve requirements")"
  expect_exit 2 "Bash backslash-split recorder" "$(bash_ '.claude/hooks/r\ecord-gate.sh approve requirements')"
  expect_exit 2 "Bash globbed recorder"         "$(bash_ '.claude/hooks/rec*-gate.sh approve requirements')"
  expect_exit 2 "Bash quote-split state dir"    "$(bash_ "echo x > ~/.cpp-har''ness/gates/f.json")"
  ln -s "$GATES/new.json" "$TMP/innocent.json"
  expect_exit 2 "Write via dangling symlink file into state" "$(write Write "$TMP/innocent.json")"
  ln -s "$TMP/alias" "$TMP/alias2"
  expect_exit 2 "Write via symlink chain into state" "$(write Write "$TMP/alias2/gates/f.json")"
  CPP_HOOKS_DISABLE=1 expect_exit 2 "CPP_HOOKS_DISABLE does not open the recorder" "$(bash_ '.claude/hooks/record-gate.sh requirements approve')"

  # --- F4: stage / decision validation is exact --------------------------------
  record review approve && bad "record-gate.sh accepted substring stage 'review'" || ok
  record code-review appr && bad "record-gate.sh accepted substring decision 'appr'" || ok
  record user approve && bad "record-gate.sh accepted substring stage 'user'" || ok
  [[ "$(state_of code-review)" == "pending" ]] && ok || bad "code-review should still be pending"
  [[ -z "$(jq -r '.gates.review // empty' "$GATES"/*.json 2>/dev/null)" ]] && ok || bad "junk key 'review' written to state"

  # --- recorder and enforcer agree on the state file (guards key drift) --------
  record approve requirements || bad "'/gate approve requirements' (decision first) rejected"
  [[ "$(state_of requirements)" == "approved" ]] && ok || bad "requirements not approved after decision-first call"
  record architecture approve || bad "'architecture approve' (stage first) rejected"
  expect_exit 0 "story-writer after requirements+architecture approved" "$(task story-writer)"
  expect_exit 0 "plugin:story-writer after approval" "$(task hmcts-sdlc-orchestrator:story-writer)"
  expect_exit 2 "test-engineer while user-story pending" "$(task test-engineer)"
  # Gate on the repo the artefact lands in: approvals here must not open another repo.
  OTHER="$TMP/other"; mkdir -p "$OTHER/docs/pipeline" && git -C "$OTHER" init -q && git -C "$OTHER" checkout -q -b feat/x
  expect_exit 2 "Write into another repo with its gates pending" "$(write Write "$OTHER/docs/pipeline/user-stories/US-9.md")"
  expect_exit 0 "Write user story here once gates approved"      "$(write Write "$WORK/docs/pipeline/user-stories/US-9.md")"

  # --- reject rewinds downstream ----------------------------------------------
  record user-story approve
  record reject architecture wrong-pattern || bad "reject with reason rejected"
  [[ "$(state_of user-story)" == "pending" ]] && ok || bad "user-story should reset to pending after architecture reject"
  expect_exit 2 "story-writer after architecture rejected" "$(task story-writer)"

  # --- branch isolation --------------------------------------------------------
  git -C "$WORK" checkout -q -b feat/b 2>/dev/null
  expect_exit 2 "new branch starts with every gate pending" "$(task architecture-designer)"
  git -C "$WORK" checkout -q feat/a 2>/dev/null

  # --- override: CPP_GATES_OVERRIDE=1 opens and audits; CPP_HOOKS_DISABLE does not
  CPP_HOOKS_DISABLE=1 expect_exit 2 "CPP_HOOKS_DISABLE is ignored" "$(task story-writer)"
  CPP_GATES_OVERRIDE=1 expect_exit 0 "CPP_GATES_OVERRIDE=1 proceeds" "$(task story-writer)"
  [[ -s "$GATES/overrides.jsonl" ]] && ok || bad "override not written to overrides.jsonl"

  # --- F5: injected context names the stages that are actually blocked ---------
  out="$(cd "$WORK" && printf '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}' | "$HOOKS/enforce-gate.sh" 2>/dev/null)"
  grep -q "at or beyond" <<<"$out" && bad "UserPromptSubmit still says 'at or beyond'" || ok
  grep -q "after the first of these" <<<"$out" && ok || bad "UserPromptSubmit text missing 'after the first of these'"

  # --- /gate with no arguments prints status -----------------------------------
  (cd "$WORK" && "$HOOKS/record-gate.sh" 2>/dev/null | grep -q "requirements") && ok || bad "record-gate.sh with no args should print status"

  rm -rf "$TMP"
done

echo "passed: $pass   failed: $fail"
[[ $fail -eq 0 ]]
