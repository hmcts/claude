# CPP Claude Hooks

Mechanical enforcement of the **Don'ts** in the [Claude Usage Guidelines](../../CLAUDE_USAGE_GUIDELINES.md) ([Confluence mirror](https://tools.hmcts.net/confluence/pages/viewpage.action?pageId=1969095323)).

Hooks block tool calls and prompts when input matches a known-bad pattern. They are a **first line of defence**, not a substitute for human review — see "Limits" below.

## Hooks shipped

| Script | Hook events | What it blocks |
|---|---|---|
| `block-secrets.sh` | `UserPromptSubmit`, `PreToolUse:Write\|Edit` | Azure Key Vault URIs, SAS/connection strings, SP secrets, JWTs, private keys, kubeconfig markers, AWS keys, GitHub PATs, Slack tokens, password assignments, DB URLs with creds. |
| `block-pii.sh` | `UserPromptSubmit`, `PreToolUse:Write\|Edit` | CJS URNs, NINOs, labelled DOBs, passport hints, defendant/witness/victim labels, court reference labels. |
| `guard-bash.sh` | `PreToolUse:Bash` | `--no-verify`, `--no-gpg-sign`, `--dangerously-skip-permissions`, force-push to `main`/`master`/`develop`/`release/*`, `kubectl --context …prod…`, `az aks …prod…`, prod DB connections, `rm -rf` on workspace roots. |
| `guard-paths.sh` | `PreToolUse:Read\|Write\|Edit` | `.env*` (allows `.env.example`/`.sample`/`.template`/`.dist`), `kubeconfig*`, SSH private keys, `credentials*.json`, `*.pem`/`*.key`/`*.pfx`/`*.p12`, paths under `secrets/`. Edits/writes to prod Helm values and prod Flux configs. |

## Telemetry (non-blocking)

These do not block anything. They record harness usage for the
[measurement framework](../../docs/harness-measurement-framework.html).

| Script | Hook events | What it records |
|---|---|---|
| `harness-telemetry.sh` | `SessionStart`, `SessionEnd`, `Stop`, `PostToolUse:Skill\|Task\|Agent\|Write\|Edit` | Anonymous usage events to `~/.cpp-harness/events/*.jsonl` — session lifecycle, per-skill and per-agent invocations, artefact writes. No prompt text, file contents, absolute paths, or developer identity. Always exits 0. |
| `record-gate.sh` | invoked by `/gate`, not a hook | Human-gate decisions (`accept`/`edit`/`reject` + fixed reason code) per pipeline stage. |
| `git/post-commit` | git hook, installed via `core.hooksPath` | Records the commit's SHA against the live session, in the **local index only**. Writes nothing into the commit message. |
| `git/post-rewrite` | git hook | Follows attribution across `git commit --amend` and `git rebase`, so tidying a branch does not orphan it. |
| `git/pre-push` | git hook | Records which remote branch carried the commits — the join key for PR-level metrics in Azure DevOps. |

All three chain to the repo's own hook of the same name (husky first), because
`core.hooksPath` is global. Nothing about AI assistance is written into git history: most
CPP repos are public, and that marker would be permanent and unretractable.

Install and opt-out: [`docs/telemetry/installing.md`](../../docs/telemetry/installing.md).
Attribution spec: [`docs/telemetry/attribution-index.md`](../../docs/telemetry/attribution-index.md).
Disable with `CPP_HARNESS_TELEMETRY=off` (telemetry only) or `CPP_HOOKS_DISABLE=1` (everything).

## Mapping to Don'ts

| Don't (from guidelines) | Enforced by |
|---|---|
| Paste secrets (Azure SP, Key Vault, JWTs, kubeconfigs, `.env`) | `block-secrets.sh` + `guard-paths.sh` |
| Paste real case data, PII, court references | `block-pii.sh` |
| Connect to prod DBs / Service Bus / AKS | `guard-bash.sh` |
| Bypass pre-commit hooks / commit signing | `guard-bash.sh` |
| Force-push to `main`/`master` | `guard-bash.sh` |
| Auto-approve all tool calls | `guard-bash.sh` (catches the flag inside Bash invocations) |
| Edit prod Helm values without a human-driven flow | `guard-paths.sh` |

The remaining Don'ts (review every line, architect sign-off on event flows, WCAG verification, legal review) are **not enforceable via hooks** — they belong in CODEOWNERS, branch protections, and `/ultrareview`.

## Install

1. Ensure `jq` is installed (`brew install jq` on macOS).
2. Merge the contents of [`settings.example.json`](./settings.example.json) into your `~/.claude/settings.json` (or your project's `.claude/settings.json`).
   - The example uses `$HOME/cpp/cpp-claude/.claude/hooks/...`. Adjust the path if your workspace lives elsewhere.
3. Restart Claude Code so hooks are loaded.
4. Verify with the smoke tests below.

## Smoke tests

Run from a shell to confirm hooks block as expected:

```bash
# Should exit 2 ("Blocked: matched pattern Azure Key Vault URI")
echo '{"hook_event_name":"UserPromptSubmit","prompt":"my secret lives at foo.vault.azure.net"}' \
  | ./block-secrets.sh; echo "exit=$?"

# Should exit 2 (NINO match)
echo '{"hook_event_name":"UserPromptSubmit","prompt":"the suspect NINO is AB123456C"}' \
  | ./block-pii.sh; echo "exit=$?"

# Should exit 2 (force-push to main)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | ./guard-bash.sh; echo "exit=$?"

# Should exit 2 (.env read)
echo '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/repo/.env"}}' \
  | ./guard-paths.sh; echo "exit=$?"

# Should exit 0 (.env.example is allow-listed)
echo '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/repo/.env.example"}}' \
  | ./guard-paths.sh; echo "exit=$?"
```

## Override

Set `CPP_HOOKS_DISABLE=1` in the environment to bypass for one session. Use sparingly and only when you're certain the trigger is a false positive — the next session re-enables hooks automatically.

## Limits

- **Pattern matching is heuristic.** A determined paste of base64'd secrets won't be caught. Hooks raise the floor; they don't replace judgment.
- **Hooks run on the user's machine.** They aren't a server-side control — anyone editing `settings.json` can disable them.
- **No replacement for branch protection.** Server-side rules in Azure DevOps / GitHub remain the authoritative gate.

## Contributing

- New patterns → add to the relevant script and update the smoke test list above.
- Refining noisy patterns → prefer narrower regex over removing the rule.
- Anything cross-team → propose via OpenSpec (`openspec/`) so the change is reviewed.
