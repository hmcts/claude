---
name: gate
description: Record a human-gate decision (accept / edit / reject) for a pipeline stage, so gate rejection rate can be measured per agent.
allowed-tools: Bash(*/record-gate.sh:*)
---

# Record a gate decision

The user is reporting the outcome of a human gate in the SDLC pipeline. Capture it, then
carry on with whatever the pipeline does next.

**Arguments given:** `$ARGUMENTS`

## What to do

1. Work out the **stage**, the **decision**, and — if the decision was `edit` or `reject` —
   a **reason code**, from the arguments and from what has happened in this session.

   | | Values |
   |---|---|
   | Stage | `requirements` `architecture` `user-story` `test-specs` `code` `code-review` `build-test` `deploy-sandbox` |
   | Decision | `accept` (used as produced) · `edit` (usable, needed changes) · `reject` (discarded or redone) |
   | Reason | `incomplete` `wrong-pattern` `missed-standard` `hallucinated` `style` `scope-creep` `other` |

   If the stage is unambiguous from the session — you have just produced exactly one gated
   artefact — infer it rather than asking. If the decision is genuinely unclear, ask; do not
   guess between `accept` and `edit`, because that distinction is the whole point of the metric.

2. Run the recorder:

   ```bash
   .claude/hooks/record-gate.sh <stage> <decision> [reason]
   ```

   As an installed plugin, use `${CLAUDE_PLUGIN_ROOT}/hooks/record-gate.sh` instead.

3. Confirm in one line. Do not summarise the artefact or re-litigate the decision.

## Rules

- **Never pass free text.** The reason is a fixed code. No prompt content, no artefact
  content, no case data — the log is retained and the PII rule applies.
- **Record what the human decided, not what you think of it.** A rejection of your own
  output is the most valuable row in the dataset; log it plainly and without hedging.
- If the user rejects an artefact in conversation without invoking `/gate`, offer once to
  record it, then drop it. Nagging suppresses reporting, which corrupts the metric.
