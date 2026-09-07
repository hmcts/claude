We are measuring whether the Claude SDLC harness actually helps — on delivery speed, on quality, and on how the work feels. Most of that we can measure without you. This page is the small part that needs you, and the part we are promising not to do with it.

| | |
| --- | --- |
| **From** | *[name / team]* |
| **Applies to** | Teams using the harness |
| **Questions by** | *[date]* |

---

## Three things, and that's all

### 1. Install the harness and leave its telemetry on

One line in the onboarding script. It records which commits the harness helped produce, which skills and agents ran, and what happened at each review gate. Nothing is written into your commit messages and nothing reaches a public repository — the record stays in a local file until it is collected.

*Cost: one-time, around 10 minutes per developer.*

### 2. Tell us if these two definitions are wrong

Two of the ten metrics only mean anything if every team counts them the same way. We are not asking you to record them — only to check that the definitions match how your team actually works, once.

- **Change failure** — a deployment that required a hotfix, rollback, or out-of-cycle patch within *[N]* days.
- **Escaped defect** — a defect raised against a story after it left your team's control, whatever environment finds it.

*Cost: one 30-minute conversation.*

### 3. Answer the quarterly survey

Perceived productivity, confidence in harness output reaching production, cognitive load across the estate, and a free-text box for what is annoying you. It is anonymous and not attributable to a team. The free-text answers are the part we read most carefully — they are where the real problems have shown up so far.

*Cost: 15 minutes, once a quarter.*

---

## What we are not asking for

- **No monthly return.** There is no form and no numbers to submit.
- **No self-reported measurements.** Six of the ten metrics come from Azure DevOps, Jira and SonarQube — data you already produce by working normally. Asking teams to type numbers that a board will later read turns a measurement into a negotiation, so we are not doing it.
- **No time tracking, and no counting lines of code.** We have explicitly ruled out lines written and "percentage of code written by AI" as metrics. Both reward the wrong behaviour and neither tells us whether the work got better.

---

## What we are committing to in return

- **No named-team league tables.** Your team sees its own numbers plus the anonymised programme distribution, so you know where you sit. The programme board sees the aggregate and the shape of the distribution — not named teams ranked against each other.
- **No individual-level reporting, ever.** The telemetry carries a random installation identifier, not a name, an email address, or a username.
- **Nothing in public git history.** No AI-assistance marker goes into a commit message. Most of our repositories are public and that marker would be permanent — so the record is kept privately instead.
- **Opt-out is honoured and deletion is real.** One environment variable turns it off. Deleting the local store removes every record held on that machine, retroactively.
- **Speed is never reported without its counter-metric.** Cycle time appears next to change failure rate; review turnaround next to review depth. A harness that makes us faster and worse is a failure, and the report is built so that shows.

---

## What you get back, monthly — and how each one is counted

Ten metrics, on a dashboard you can open yourself. Each is shown for your team and for the programme. If a definition below does not describe how your team actually works, that is worth telling us now.

| # | Metric | Source | How it is counted |
| --- | --- | --- | --- |
| 01 | Weekly active developers | Harness | Distinct installations that opened at least one harness session during the week, divided by the developers the harness is available to. The denominator is the point — eight enthusiasts is not adoption. |
| 02 | Per-skill invocation counts | Harness | How many times each skill and each agent was invoked, per week. Tells us which parts of the harness are load-bearing and which are shelfware we should stop maintaining. |
| 03 | Cycle time | Azure DevOps | First commit on the branch through to merge into the trunk. Reported as median **and** p90, because the harness is expected to compress the tail — the "I have never touched this repo before" work — far more than the middle. **Always shown next to change failure rate.** |
| 04 | PR review turnaround | Azure DevOps | Two clocks, reported separately: pull request opened to first review comment, and opened to approval. The first is responsiveness, the second is throughput, and they can move in opposite directions. **Always shown next to review depth — comments per PR, which must not collapse.** |
| 05 | Change failure rate | ADO + incidents | Deployments that required a hotfix, rollback, or out-of-cycle patch within *[N]* days, as a share of all deployments. A DORA metric, and the single most important counter-metric here — a harness that ships faster and breaks more has not helped. **Definition being agreed with teams — see ask 2.** |
| 06 | Defect escape rate | Jira | Defects raised against a story after it left your team's control, as a share of stories delivered. Counted wherever the defect is found, not only in production. **Definition being agreed with teams — see ask 2.** |
| 07 | CI first-pass rate | Azure DevOps | Pipeline runs that go green on the first attempt with no re-run, as a share of all runs. The most direct read on whether harness-written code and tests actually hold up. |
| 08 | Sonar critical issues on new code | SonarQube | Critical and blocker issues raised against new code in the period. Already collected by the parent POM chain, so this costs nobody anything — it is pure reporting. |
| 09 | Gate rejection rate by stage | Harness | At each human gate, whether the reviewer accepted, edited, or rejected what the agent produced — reported per stage. Read in both directions: a stage rejected most of the time is a prompt we can fix; a stage almost never rejected may mean reviewers have stopped reading, which is the more dangerous failure and invisible everywhere else. |
| 10 | Quarterly DX survey | Survey | Six to eight questions: perceived productivity change, confidence in harness output reaching production, time lost correcting that output, cognitive load across the estate, free-text frustrations, and an eNPS score for the harness. Anonymous, and not attributable to a team. |

> Metrics 03 to 08 are additionally split by whether the work was harness-assisted. That split only covers machines that are reporting telemetry, so a piece of work with no record is *untracked*, not *unassisted* — and the report states its coverage every month so the difference cannot be quietly lost.

---

## One thing worth saying plainly

We do not know yet whether the harness is helping. The honest three-month answer may well be that adoption is uneven and two skills are doing most of the work — and if the numbers say the harness is not earning its place on your team, that is a result we will publish rather than bury. The measurement is there to find that out, not to justify a decision already taken.

If any of the above looks wrong for how your team works, say so now rather than after the first report. Changing it later is much harder than changing it this week.

---

**Questions, or want the detail?** The full design — what is collected, what is not, and the open decisions we are still asking for views on — is in the harness attribution and telemetry design document. Ask *[name]* in *[channel]*.
