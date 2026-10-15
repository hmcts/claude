---
name: gate
description: Record a human-gate decision (approve / edit / reject / skip) for a pipeline stage, unlocking the next stage. User-only.
argument-hint: <approve|edit|reject|skip> <stage> [reason]   (no arguments shows gate status)
allowed-tools: Bash(.claude/hooks/record-gate.sh:*)
disable-model-invocation: true
---

# Record a gate decision

The user has just recorded the outcome of a human gate in the SDLC pipeline. The recorder
ran when they typed this command, before this prompt reached you. Its output:

!`.claude/hooks/record-gate.sh $ARGUMENTS 2>&1 || true`

You did not run it, and you cannot. This command is user-only (`disable-model-invocation`), and
the `enforce-gate.sh` hook blocks any Bash or Write call of yours that runs `record-gate.sh` or
touches the gate state. That is the whole control.

## What to do

1. **`recorded: …`** — confirm in one line, then carry on with whatever the pipeline does next.
   Do not summarise the artefact or re-litigate the decision.
2. **A gate status table** (the user typed `/gate` with no arguments) — show it as is.
3. **`error: …`** — nothing was recorded. Show the error and the exact command the user should
   type, for example `/gate approve requirements`. Do not try to record it any other way.

| | Values |
|---|---|
| Decision | `approve`/`accept` (used as produced) · `edit` (usable, needed changes) · `reject` (discarded or redone) · `skip` (stage does not apply to this change) |
| Stage | `requirements` `architecture` `user-story` `test-specs` `code` `code-review` `build-test` `deploy-sandbox` |
| Reason | `incomplete` `wrong-pattern` `missed-standard` `hallucinated` `style` `scope-creep` `other` |

Order does not matter: `/gate approve requirements` and `/gate requirements approve` are the same.

## Effect on the pipeline

| Decision | Gate state | Effect |
|---|---|---|
| `approve` / `accept` / `edit` | `approved` | The next stage unblocks |
| `skip` | `skipped` | Treated as satisfied — use when a stage genuinely does not apply (e.g. no architecture change for a copy fix) |
| `reject` | `rejected` | Stage stays locked **and every downstream stage resets to pending**, so the pipeline rewinds properly |

Gate state is per **repo + branch**. A new feature branch starts with every gate pending.

## Rules

- **Never suggest free text.** The reason is a fixed code and the recorder rejects anything
  else. No prompt content, no artefact content, no case data — the state file is retained and
  the PII rule applies.
- **Suggest what the human decided, not what you think of it.** If it is unclear whether they
  mean `approve` or `edit`, ask — that distinction is what the reviewer is telling you.
- **Never try to unblock yourself.** If a gate hook blocks you, stop and ask the user to review
  and run `/gate`.
- Do not offer `skip` as a way around a blocked gate. Suggest it only when the stage is
  genuinely irrelevant to the change in hand, and let the user decide.
- If the user rejects an artefact in conversation without invoking `/gate`, tell them once the
  command to type (`/gate reject <stage> <reason>`), then drop it.
