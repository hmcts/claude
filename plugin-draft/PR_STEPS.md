# PR steps: publish `hmcts-sdlc-orchestrator` to the marketplace

The plugin under `plugin-draft/hmcts-sdlc-orchestrator/` is now self-contained
(agents, skills, commands, context, hooks, CLAUDE.md, plugin.json, README).
Publishing it to the marketplace is a single copy plus a manifest edit.

## 1. Fork & clone the marketplace
```bash
gh repo fork hmcts/agentic-plugins-marketplace --clone
cd agentic-plugins-marketplace
git checkout -b add-hmcts-sdlc-orchestrator
```

## 2. Copy the plugin in
```bash
SRC=/Users/dineshsharma/cpp/claude
DEST=plugins/agents/hmcts-sdlc-orchestrator   # marketplace convention slot

mkdir -p plugins/agents
cp -R "$SRC/plugin-draft/hmcts-sdlc-orchestrator" "$DEST"
```

That's it — the plugin-draft directory contains everything the plugin needs.

## 3. Register in the marketplace manifest
Append the entry from `plugin-draft/MARKETPLACE_ENTRY.json` to the `plugins[]`
array in `.claude-plugin/marketplace.json`:

```bash
cat "$SRC/plugin-draft/MARKETPLACE_ENTRY.json"
```

## 4. Verify locally
```bash
# In a throwaway repo, inside Claude Code:
/plugin marketplace add /absolute/path/to/agentic-plugins-marketplace
/plugin install hmcts-sdlc-orchestrator
```

Smoke-test:
- `/agents` lists all 8 pipeline stages (requirements-analyst, architecture-designer,
  story-writer, test-engineer, implementation, code-reviewer, ci-orchestrator, deployer)
- `/plugin` shows the plugin contributing agents, skills, commands, and hooks
- Submitting a prompt with `AKIA0123456789ABCDEF` is blocked by `block-secrets.sh`
- Submitting a prompt with a fake URN like `01AA1234567` is blocked by `block-pii.sh`

## 5. Open the PR
```bash
git add plugins/agents/hmcts-sdlc-orchestrator .claude-plugin/marketplace.json
git commit -m "feat: add hmcts-sdlc-orchestrator plugin"
git push -u origin add-hmcts-sdlc-orchestrator
gh pr create --base main --fill
```

## Notes / decisions to confirm with the marketplace maintainers

1. **Path slot**: `plugins/agents/` is a guess based on the bundle being
   agent-centric. Maintainers may prefer `plugins/orchestrators/` (new category)
   or `plugins/skills/`. Easy to move during review.
2. **Pointer-stub skills**: `accessibility-check.md`, `adr-template.md`,
   `generate-bdd-specs.md`, `review-checklist.md`, `write-acceptance-criteria.md`
   in `skills/` point at other marketplace plugins (`bdd-workflow`,
   `accessibility-check`, `review-checklist`, `adr-template`). Consider dropping
   them and declaring those plugins as dependencies in `plugin.json` instead, to
   avoid drift.
3. **Hook activation**: The bundled `hooks/hooks.json` activates PII/secret
   guards on every consumer. If teams want opt-in, split into a sibling plugin
   (`hmcts-guard-hooks`) and have `hmcts-sdlc-orchestrator` recommend it.
4. **CLAUDE.md path references**: The orchestrator `CLAUDE.md` references
   `context/*.md` and `skills/*` with relative paths. After install those paths
   resolve under the plugin root — verified in step 4.
5. **Version**: Starts at `0.1.0`. Bump per the marketplace's semver convention.

## Keeping plugin-draft in sync with `.claude/`

The agents/skills/commands/context/hooks/CLAUDE.md inside
`plugin-draft/hmcts-sdlc-orchestrator/` are copies of the canonical ones at the
repo root (`.claude/agents/`, `.claude/skills/`, etc., and `CLAUDE.md`). If you
change either side, sync the other before opening a marketplace PR:

```bash
SRC=/Users/dineshsharma/cpp/claude
DEST="$SRC/plugin-draft/hmcts-sdlc-orchestrator"

cp "$SRC/CLAUDE.md"              "$DEST/CLAUDE.md"
cp "$SRC/.claude/agents/"*.md    "$DEST/agents/"
cp -R "$SRC/.claude/skills/"*    "$DEST/skills/"
cp "$SRC/.claude/hooks/"*.sh     "$DEST/hooks/"
cp -R "$SRC/.claude/commands/"*  "$DEST/commands/"
cp "$SRC/.claude/context/"*.md   "$DEST/context/"
```
