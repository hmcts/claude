# Validation scripts

`validate_claude_config.py` runs the checks CI needs that Claude Code's
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
