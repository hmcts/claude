# Installing harness telemetry

Two pieces, installed independently:

1. **The telemetry hook** — records anonymous usage events. Comes with the plugin; nothing to do.
2. **The git hooks** — record which commits the harness helped produce, in a
   [local index](./attribution-index.md). One command per machine, because git hooks cannot
   be installed by a Claude Code plugin.

Both write only to the local filesystem. Neither makes a network call — hooks run
synchronously in front of every tool use, and a network round-trip there would be felt.

**Nothing is written into your commits.** Attribution is held locally and keyed by commit
SHA, precisely so that no AI-assistance marker appears in the public history of a CPP
repository. See [attribution-index.md](./attribution-index.md#why-not-a-commit-trailer).

---

## 1. Telemetry hook

**As a plugin** (the supported path):

```
/plugin install hmcts-sdlc-orchestrator@agentic-plugins-marketplace
```

`hooks/hooks.json` wires `harness-telemetry.sh` to `SessionStart`, `SessionEnd`, `Stop`, and
`PostToolUse` on `Skill|Task|Agent|Write|Edit`. Requires `jq`; without it the hook exits 0
silently rather than failing the session.

**From a working copy of this repo**, merge the `SessionStart` / `SessionEnd` / `Stop` /
`PostToolUse` blocks from [`.claude/hooks/settings.example.json`](../../.claude/hooks/settings.example.json)
into your settings, fixing the paths. Do not do both — you will double-count every event.

## 2. Git hooks

Three hooks — `post-commit`, `post-rewrite`, `pre-push` — installed by hand, once per machine:

```bash
git config --global core.hooksPath "$HOME/cpp/claude/.claude/hooks/git"
# or, if you installed the plugin:
git config --global core.hooksPath "$HOME/.claude/plugins/hmcts-sdlc-orchestrator/hooks/git"
```

| Hook | Does | Runs when |
|---|---|---|
| `post-commit` | Records the new SHA against the live session | A session is open in that repo |
| `post-rewrite` | Follows attribution across `--amend` and `rebase` | Always — rebases happen long after the session |
| `pre-push` | Records which branch carried the commits to the remote | Always, in repos the harness has committed in |

> **`core.hooksPath` is global and overrides per-repo hooks.** That would otherwise disable
> husky in the `cpp-ui-*` repos and any local pre-commit wiring. All three shipped hooks
> therefore **chain**: each runs the repo's own hook of the same name (`.husky/` first, then
> `.git/hooks/`) before doing its own work. `pre-push` propagates a non-zero exit, so a repo
> that legitimately blocks a push still blocks it. They are additive.
>
> If your team already sets `core.hooksPath` for something else, don't fight it — copy the
> hooks into that directory instead, or chain to them from there.

Verify:

```bash
cd ~/cpp/cpp-context-hearing
git config core.hooksPath          # should print the path above
```

Nothing here can break a commit: `post-commit` and `post-rewrite` run after the objects
exist and git ignores their exit status, and `pre-push` only ever passes through the
verdict of a hook that was already there.

---

## What gets recorded

`~/.cpp-harness/events/events-YYYY-MM.jsonl`, one JSON object per line:

```json
{"ts":"2026-08-28T09:11:05Z","event":"agent_used","session":"7f3a9c21e4b0",
 "install":"4404be648cde","repo":"cpp-context-hearing","branch":"feature/custody-timer",
 "agent":"requirements-analyst","stage":"requirements"}
```

| Event | Emitted on | Feeds |
|---|---|---|
| `session_start` / `session_end` | session lifecycle | Weekly actives, sessions per dev, repo coverage, abandonment |
| `turn_end` | `Stop` | Session depth |
| `skill_used` | `Skill` tool | **Per-skill invocation counts** — which of the ~15 skills earn their keep |
| `agent_used` | `Task`/`Agent` tool | Per-stage agent usage |
| `artefact_written` | Write/Edit under `docs/pipeline/` | Pipeline completion rate |
| `gate_decision` | `/gate` command | **Gate rejection rate by stage** |
| `commit_recorded` | `post-commit` | **The assisted/unassisted split** for every flow and quality metric |
| `commit_rewritten` | `post-rewrite` | Keeps that split intact across amend and rebase |
| `branch_pushed` | `pre-push` | Join key for PR-level metrics in Azure DevOps |

Two pieces of local state sit alongside the log:
`~/.cpp-harness/by-repo/<hash>.json` holds the live session the git hooks read, and is
deleted at `SessionEnd`; `~/.cpp-harness/attributed/<hash>` marks repos the harness has
committed in, so `pre-push` stays silent in every other repo on the machine.

### The installation id

`install` is a random 12-hex-character value generated once and stored at
`~/.cpp-harness/installation-id`. It is **not** derived from your name, email, hostname, or
any machine identifier, and cannot be mapped back to a person without access to that
person's machine.

It exists because every other field is deliberately non-identifying, which left "weekly
active developers" — the headline adoption metric — uncomputable. Delete the file to get a
new one; nothing breaks, you just appear as a new installation from then on.

The governance rules in [the attribution spec](./attribution-index.md#governance) apply to
it in full: aggregate reporting only, no per-installation breakdowns, no
performance-management use.

### What is deliberately not recorded

No prompt text. No file contents. No file paths (only the artefact subdirectory name). No
absolute paths — `/Users/<name>/…` identifies a person, so only the repo basename is kept.
No remote URLs, only the remote's name. No developer name, email, hostname, or hardware id.
No free text anywhere, including in `/gate` reasons, which are a fixed vocabulary.

And nothing at all in the commit itself.

The log is local. Nothing leaves the machine until someone builds the shipper — decide the
destination and retention period *before* that, not after.

---

## Opting out

```bash
export CPP_HARNESS_TELEMETRY=off      # suppresses the usage log and the attribution index
export CPP_HOOKS_DISABLE=1            # suppresses all CPP hooks, guards included
```

`CPP_HOOKS_DISABLE` is the blunt instrument and also turns off the PII and secret guards —
prefer `CPP_HARNESS_TELEMETRY=off` when telemetry is the thing you object to.

Deleting `~/.cpp-harness` removes every record held on the machine, retroactively. Opting
out is legitimate and is not tracked to an individual. A high opt-out rate is a finding
about trust in the programme, and should be read that way rather than engineered around.

---

## Smoke test

```bash
export CPP_HARNESS_STATE_DIR=$(mktemp -d)
cd "$(mktemp -d)" && git init -q -b main . && git config user.email t@t.test && git config user.name T
H=~/cpp/claude/.claude/hooks

jq -n --arg cwd "$PWD" '{hook_event_name:"SessionStart",session_id:"7f3a9c21e4b0aa",cwd:$cwd}' | "$H/harness-telemetry.sh"
jq -n --arg cwd "$PWD" '{hook_event_name:"PostToolUse",session_id:"7f3a9c21e4b0aa",cwd:$cwd,
  tool_name:"Task",tool_input:{subagent_type:"requirements-analyst"}}' | "$H/harness-telemetry.sh"

git config core.hooksPath "$H/git"
touch a && git add a && git commit -q -m "test commit"

git log -1 --format=%B                                   # expect NO trailers — a clean message
jq -c 'select(.event=="commit_recorded")' "$CPP_HARNESS_STATE_DIR"/events/*.jsonl
```

Expected on a clean install: the commit message is exactly what you typed, and one
`commit_recorded` line carries that commit's SHA with `stages:["requirements"]`.

To check the rewrite chain: `git commit --amend -m "test commit v2"` should add a
`commit_rewritten` line mapping the old SHA to the new one.

---

## Reading the data

[`scripts/harness_metrics.py`](../../scripts/harness_metrics.py) joins the event log to
`git log` by SHA and reports the starting-set metrics. Stdlib only, read-only:

```bash
python scripts/harness_metrics.py --repos ~/cpp --since 30 --eligible 40
python scripts/harness_metrics.py --format markdown > monthly-review.md
python scripts/harness_metrics.py --format json | jq .
```

It reports adoption, per-skill and per-agent usage, repo coverage, pipeline abandonment,
gate rejection rate by stage, and assisted-commit share — and names the metrics it cannot
compute locally alongside the API each one needs, rather than substituting a proxy.

It also prints an **index health** block: how many commits were recorded, how many rewrites
were followed, and how many recorded commits could not be found in the scanned history.
Read that block before quoting the assisted percentage — a high "recorded but not found"
count means the percentage is an undercount, not that the harness is unused.

Point `--events` at a directory of logs collected from several machines to report across a
team. Full flag reference: [`scripts/README.md`](../../scripts/README.md).

### Collection

There is no collector, and this design needs one more than the previous design did. Because
attribution lives in the log rather than in the commit, **a report covers only the machines
whose logs you have**. Scanning a colleague's repo from your machine correctly reports 0%
assisted.

The natural destination is the same observability backend as
`CLAUDE_CODE_ENABLE_TELEMETRY`, so OTel session data and these harness-specific events land
together. Decide the destination, the retention period, who can query it, and how deletion
works **before** building it — those are the questions that make the difference between
telemetry people tolerate and telemetry they switch off.
