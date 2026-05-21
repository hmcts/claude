# PR steps: publish `hmcts-sdlc-orchestrator` to the marketplace

## 1. Fork & clone
```bash
gh repo fork hmcts/agentic-plugins-marketplace --clone
cd agentic-plugins-marketplace
git checkout -b add-hmcts-sdlc-orchestrator
```

## 2. Copy the plugin in
From this repo (`/Users/dineshsharma/cpp/claude`):

```bash
SRC=/Users/dineshsharma/cpp/claude
DEST=plugins/agents/hmcts-sdlc-orchestrator   # marketplace convention slot

# Scaffolding (plugin.json, hooks.json, README) prepared under plugin-draft/
cp -R "$SRC/plugin-draft/hmcts-sdlc-orchestrator/" "$DEST/"

# Pipeline orchestrator CLAUDE.md
cp "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"

# Agents (15 .md files)
cp "$SRC/.claude/agents/"*.md "$DEST/agents/"

# Skills (mixed dirs + .md pointer stubs)
cp -R "$SRC/.claude/skills/"* "$DEST/skills/"

# Hooks (shell scripts referenced by hooks.json)
cp "$SRC/.claude/hooks/"*.sh "$DEST/hooks/"

# Commands
cp -R "$SRC/.claude/commands/"* "$DEST/commands/"

# Context docs (referenced by CLAUDE.md)
cp "$SRC/.claude/context/"*.md "$DEST/context/"
```

## 3. Register in the marketplace manifest
Add the entry from `plugin-draft/MARKETPLACE_ENTRY.json` to the `plugins[]` array in `.claude-plugin/marketplace.json`.

## 4. Verify locally
```bash
# In a throwaway repo
/plugin marketplace add /absolute/path/to/agentic-plugins-marketplace
/plugin install hmcts-sdlc-orchestrator
# Then check: /agents, /plugin, and that CLAUDE.md context loads
```

## 5. Open the PR
```bash
git add plugins/agents/hmcts-sdlc-orchestrator .claude-plugin/marketplace.json
git commit -m "feat: add hmcts-sdlc-orchestrator plugin"
gh pr create --fill --base main
```

## Notes / decisions to confirm with the marketplace maintainers

1. **Path slot**: I placed it under `plugins/agents/` since the bundle is agent-centric and that folder is currently a reserved-but-empty slot. They may prefer `plugins/orchestrators/` (new category) or `plugins/skills/` — easy to move.
2. **Pointer-stub skills**: `accessibility-check.md`, `adr-template.md`, `generate-bdd-specs.md`, `review-checklist.md`, `write-acceptance-criteria.md` in `.claude/skills/` already point at marketplace plugins. Consider dropping them from this plugin and listing those plugins as dependencies/recommendations in the README instead, to avoid duplication.
3. **Hook activation**: The bundled `hooks.json` activates guard hooks for all consumers. If teams want opt-in only, split hooks into a sibling plugin (`hmcts-guard-hooks`) and let `hmcts-sdlc-orchestrator` recommend it.
4. **Path references in CLAUDE.md**: The orchestrator `CLAUDE.md` references `context/*.md` and `skills/*` with repo-relative paths. After moving into the plugin, those paths still resolve because Claude Code mounts the plugin root alongside the repo. Double-check by running step 4 above.
5. **Version**: Start at `0.1.0`; bump per the marketplace's existing versioning convention (looks like semver).
