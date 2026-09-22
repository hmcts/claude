# Scripts

| Script | Purpose | Dependencies |
|---|---|---|
| `validate_claude_config.py` | Repo/marketplace consistency checks. Runs in CI. | PyYAML |
| `harness_metrics.py` | Reports the harness measurement metrics from telemetry events and the local commit attribution index. | stdlib only |

## `harness_metrics.py`

Reads the local JSONL event log written by `.claude/hooks/harness-telemetry.sh` and the git
hooks in `.claude/hooks/git/`, joins its `commit_recorded` SHAs against `git log` across the
workspace, and reports the metrics from the
[measurement framework](../docs/harness-measurement-framework.html) that those two sources
support — adoption, per-skill and per-agent usage, repo coverage, pipeline abandonment,
gate rejection rate, and assisted-commit share.

Attribution is held locally and keyed by SHA rather than stamped into commit messages,
because most CPP repositories are public. See
[`docs/telemetry/attribution-index.md`](../docs/telemetry/attribution-index.md). The cost is
that **the report only knows about machines whose logs you are reading** — a freshly cloned
repo correctly shows 0% assisted. The `Index health` block in the output quantifies that
gap; read it before quoting the percentage.

```bash
# The monthly review
python scripts/harness_metrics.py --repos ~/cpp --since 30 --eligible 40

# Paste-ready for Confluence
python scripts/harness_metrics.py --format markdown > monthly-review.md

# For a collector
python scripts/harness_metrics.py --format json | jq .
```

| Flag | Default | Notes |
|---|---|---|
| `--events` | `~/.cpp-harness/events` | Point at a directory of collected logs to report across machines |
| `--repos` | parent of this repo | Workspace root; scanned two levels deep for git repos |
| `--since` | `90` | Window in days |
| `--eligible` | — | Eligible developer count. Without it the adoption percentage is blank, and adoption without a denominator is not a metric |
| `--total-repos` | `145` | Coverage denominator |
| `--no-git` | off | Skip the git scan (faster; drops attribution) |

The `--since` window applies to the metrics, not to the index: the event log is always read
whole, because a rebase outside the window can rewrite a SHA a commit inside it depends on.

Read-only — it runs `git log` and nothing else.

**It deliberately does not compute** change failure rate, defect escape rate, PR review
turnaround, cycle time, CI first-pass rate, or the SonarQube trend. Those need Azure
DevOps, Jira, and SonarQube, and the report lists them with the API each requires rather
than substituting a local proxy that would read as the real thing.

## `validate_claude_config.py`

Runs the checks CI needs that Claude Code's
built-in `/plugin validate` does not cover: cross-repo consistency with the
`agentic-plugins-marketplace`, pointer-stub integrity, CLAUDE.md / README.md
file-reference checks, and dangling skill references from agents and skills.

## Local run

```bash
pip install pyyaml

# Point at a local clone of the marketplace repo so the cross-repo
# enabledPlugins check can run.
python scripts/validate_claude_config.py \
  --marketplace-path ../agentic-plugins-marketplace
```

If the marketplace path is absent, the cross-repo check is skipped with a
warning but all other checks still run. CI always fetches the marketplace.

Exit code `0` means clean; `1` means one or more violations; `2` means the
script itself failed to run.

## What each check covers

| # | Check | What it catches |
|---|---|---|
| 1 | `enabledPlugins` vs. marketplace | `.claude/settings.json` enables a plugin that doesn't exist in the marketplace. Claude Code validates against *installed* plugins, not the marketplace manifest — so a typo only surfaces on first install. |
| 2 | Pointer stub integrity | Every `.claude/skills/*` file that redirects to a marketplace plugin must name a plugin that's also enabled in `settings.json`. A stub left behind after renaming silently misleads readers. |
| 3 | Skill frontmatter | Every `.claude/skills/*/SKILL.md` has `name` + `description`. (Claude Code silently skips broken frontmatter; CI fails loudly.) |
| 4 | opsx command frontmatter | Every `.claude/commands/opsx/*.md` has `name` + `description`. |
| 5 | CLAUDE.md references | Every `agents/<name>.md` and `context/<name>.md` mentioned in CLAUDE.md must exist on disk. Guards the pipeline-stages table and context file list. |
| 6 | README.md references | Same, for the README's skill/agent tables. |
| 7 | `skill: skills/...` path references | Agents reference skills via `skill: skills/review-checklist.md` lines — the target paths must resolve. |
| 8 | Dangling skill names | `SKILL.md` or agent bodies referencing other skills by kebab-case name (`` `foo` skill``, `Task: foo`) must reference real ones. Prefix-gated to keep false positives low — this is the `openspec-sync-specs` bug class on the claude-repo side. |

## What this script intentionally does NOT check

Anything Claude Code already validates on plugin load or `/plugin validate`:
JSON validity of `settings.json` (aside from a sanity parse), SKILL.md YAML
structure beyond `name`/`description`, agent frontmatter schema (agents in
this repo don't use frontmatter).

## Ordering rule with the marketplace repo

CI fetches `main` of `hmcts/agentic-plugins-marketplace`. If a single logical
change adds a plugin to the marketplace and enables it here simultaneously,
**land the marketplace PR first** or this repo's CI will fail on the
`enabledPlugins` check.
