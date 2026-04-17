---
description: Force-refresh the cp-c4-architecture checkout that backs the LikeC4 MCP server (fast-forward pull + last-pull sentinel bump).
allowed-tools: Bash
---

Run the refresh script that the `cp-architecture` plugin ships. It acquires the shared wrapper lockdir, fast-forward-pulls the cp-c4-architecture checkout under the plugin's persistent data directory, updates the last-pull sentinel, and prints a summary.

Execute exactly this command, then report its stdout verbatim to the user:

```bash
CLAUDE_PLUGIN_DATA="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/cp-architecture-cpp-claude" bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-c4-checkout.sh"
```

Do not add interpretation, do not re-summarise the before/after SHAs, and do not suppress the "running MCP server still holds the pre-refresh model" note — the user needs to see it so they know to restart their session before the new model is visible.

The explicit `CLAUDE_PLUGIN_DATA=` assignment is load-bearing: Claude Code substitutes `${CLAUDE_PLUGIN_ROOT}` in slash-command markdown bodies, but `${CLAUDE_PLUGIN_DATA}` falls through to the Bash tool's inherited env, which in a multi-plugin session leaks whichever plugin touched it last. Using the canonical `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/cp-architecture-cpp-claude` pinned by Phase 0 Task 0.3 avoids that leak and is robust regardless of whether the plugin is loaded from the cache path or dev-loaded from a local marketplace path (where structural derivation from `CLAUDE_PLUGIN_ROOT` breaks because the depth from the plugin root to the `plugins/` parent changes).

If the script exits non-zero, surface its stderr verbatim and stop. Do not retry, do not try to fix the checkout by hand, and do not fall back to `npx @likec4/mcp` or any other alternative — the script's failure messages are actionable on their own.
