# cpp-claude

Claude Code plugins for Common Platform development.

## Plugins

### cp-architecture

LikeC4 architecture model awareness and drift-check for cp-context-\* services. Provides MCP tools for querying the C4 model, a skill for architecture exploration, and hooks that detect structural edits and prompt for model checks.

**Install:**

```
/plugin marketplace add https://github.com/hmcts/cpp-claude.git
/plugin install cp-architecture@cpp-claude
```

**Commands:**

- `/refresh-c4-model` — force-refresh the cp-c4-architecture checkout (bypasses the 24h staleness window). Restart the session afterwards to pick up the new model.

**Drift mode:**

Set `CP_ARCHITECTURE_DRIFT_MODE` to control hook behaviour:

| Value | Behaviour |
|-------|-----------|
| `warn` (default) | Hooks emit advisory context on structural edits |
| `block` | Stop hook blocks the turn until a model check is performed |
| `off` | Hooks are fully inert |

**State and log locations:**

All runtime state lives under `~/.claude/plugins/data/cp-architecture-cpp-claude/`:

| Path | Purpose |
|------|---------|
| `cp-c4-architecture/` | Cloned checkout of the LikeC4 model repo |
| `state/last-pull` | Sentinel file; mtime determines staleness (24h window) |
| `state/turn-*.json` | Per-session turn state for the drift hooks |
| `state/*.lock.d/` | Lockdirs (wrapper: 300s stale, turn: 60s stale) |
| `logs/wrapper.log` | Wrapper stderr (rotated at 1 MB) |
| `npm-cache/` | Isolated npm cache for the MCP server dependencies |

**Clean reinstall:** delete the entire `cp-architecture-cpp-claude/` directory. The next session will re-clone and re-install from scratch.

**Design and implementation details:**

- [Design spec](docs/superpowers/specs/2026-04-13-cp-architecture-plugin-design.md)
- [Implementation plan](docs/superpowers/specs/2026-04-13-cp-architecture-plugin-plan.md)
- [Implementation notes](docs/superpowers/specs/2026-04-13-cp-architecture-plugin-notes.md)