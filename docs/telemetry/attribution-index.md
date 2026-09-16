# Harness attribution: the local commit index

**Status:** proposed
**Applies to:** every CPP repository where the `hmcts-sdlc-orchestrator` plugin is used
**Supersedes:** the git trailer convention (`Assisted-By:` etc.), withdrawn — see
[Why not a commit trailer](#why-not-a-commit-trailer)

Without a durable marker on the commit, none of the flow or quality metrics in the
[measurement framework](../harness-measurement-framework.html) can be segmented into
harness-assisted vs. unassisted work. This document defines that marker.

The marker is held **locally, keyed by commit SHA**. Nothing about AI assistance is written
into a commit message, a tag, a branch name, or anything else that reaches a public
remote.

---

## Why not a commit trailer

The obvious design is a `Assisted-By: hmcts-sdlc-orchestrator@1.2.0` trailer in the commit
message. It is self-describing, needs no infrastructure, and survives being cloned. It was
the first design, and it was withdrawn for one reason:

**The majority of CPP repositories are public.** A permanent, world-readable AI-assistance
marker on the commit history of a criminal justice system is a standing liability. It
cannot be retracted — removing it would mean rewriting published history across ~145
repositories — and its meaning is entirely outside the programme's control once a
journalist, a defence practitioner, or a select committee decides what it signifies.

A local index gives up several genuinely useful properties (see
[What this costs](#what-this-costs)) and gains three:

- **Nothing to explain.** The public commit is indistinguishable from any other.
- **It is revocable.** Delete the log and the attribution is gone. "You can withdraw your
  data" becomes a true statement rather than an awkward one, which matters for the
  governance conversation below.
- **The hooks stop touching the commit.** Trailers required `prepare-commit-msg`, which
  mutates the message and sits in the blocking path of every commit on the machine. The
  replacement hooks all run *after* the commit exists and cannot break one.

Do not "solve" this with an opaque marker — `X-CPP-Pipeline: 3f2a` and similar. That is
concealment rather than absence, and its failure mode is strictly worse than the one it
avoids: *HMCTS hid AI attribution behind a code* is a better story than *HMCTS used AI
assistance*, and the marker being obviously deliberate is what makes it one. If a marker is
not safe to explain, it does not go in a public repository.

---

## The records

Three event types, appended to the same local JSONL log as the usage telemetry
(`~/.cpp-harness/events/events-YYYY-MM.jsonl`):

| Event | Written by | Carries |
|---|---|---|
| `commit_recorded` | `post-commit` | `sha`, `harness` (`name@version`), `stages`, `session`, `install`, `repo`, `branch` |
| `commit_rewritten` | `post-rewrite` | `old_sha`, `new_sha`, `reason` (`amend` \| `rebase`) |
| `branch_pushed` | `pre-push` | `tip_sha`, `remote_ref`, `remote` (name only, never the URL) |

```json
{"ts":"2026-08-28T09:14:02Z","event":"commit_recorded","session":"7f3a9c21e4b0",
 "install":"4404be648cde","repo":"cpp-context-hearing","branch":"feature/custody-timer",
 "sha":"6b1e3275ac78306fbc04e3a85b7aaeab777adb97","harness":"hmcts-sdlc-orchestrator@1.2.0",
 "stages":["requirements","test-specs","code"]}
```

### Stage slugs

Fixed vocabulary, matching the eight pipeline stages in [`CLAUDE.md`](../../CLAUDE.md):

`requirements` · `architecture` · `user-story` · `test-specs` · `code` · `code-review` · `build-test` · `deploy-sandbox`

A session that only used an ad-hoc skill without entering the pipeline records an empty
stage list — still attributed, but explicitly outside the orchestrated flow. That
distinction matters: it separates *"the pipeline delivered this"* from *"someone used a
skill once"*, and the two have very different quality profiles.

---

## Following the commit

A SHA is not stable. Amend it, rebase it, and the attribution would be orphaned — which in
CPP would mean losing it on most branches, since tidying before review is the norm.
`post-rewrite` closes that: git hands it `<old-sha> <new-sha>` pairs for both `--amend` and
`rebase`, and the reader walks the chain forward, so attribution stays attached to the
commit rather than to the hash.

Two consequences worth stating plainly:

- **`post-rewrite` and `pre-push` run without a live Claude session.** Rebases and pushes
  routinely happen hours or days after the work. Requiring a session would break the chain
  exactly when it is needed. Only `post-commit` requires a live session, because only it
  decides whether a commit is attributed at all.
- **Cherry-pick is not covered.** Git does not fire `post-rewrite` for it. A cherry-picked
  commit loses its attribution and reads as unassisted. This is an undercount, and an
  acceptable one.

---

## Design rules

**Absence means "not assisted", so absence must be trustworthy.** Recording is automatic —
there is no step a developer can forget. A marker that had to be remembered would be
missing perhaps a third of the time, and the missing third would not be random: it would
skew toward rushed work, which is exactly the population the quality comparison needs.

**Nothing derived from prompt content is ever recorded.** SHAs, enums, semvers, opaque ids.
The hard rule against PII, case data, and court references applies in full.

**No developer identity.** The commit author already carries that. The index holds only the
pseudonymous `install` id described in [installing.md](./installing.md#the-installation-id).

**Stable keys.** Event names and field names are frozen. New facts get new fields; existing
fields never change meaning, or the historical series breaks.

---

## Querying it

The join is SHA-based, so it needs the log and the repo together.
[`scripts/harness_metrics.py`](../../scripts/harness_metrics.py) does this and reports
index health alongside the numbers. By hand:

```bash
# Every assisted SHA in the index
jq -r 'select(.event=="commit_recorded") | .sha' ~/.cpp-harness/events/*.jsonl | sort -u > /tmp/assisted

# Assisted share of the last 90 days in this repo
git log --since='90 days ago' --no-merges --format=%H > /tmp/all
echo "assisted: $(comm -12 <(sort /tmp/all) <(sort /tmp/assisted) | wc -l) / $(wc -l < /tmp/all)"
```

Remember to follow `commit_rewritten` pairs forward, or every rebased branch will read as
unassisted. The reader does this; a one-liner does not.

### PR-level rollup, held in Azure DevOps

This is where most of the metrics actually live — cycle time, review turnaround, CI
first-pass rate, and change failure rate are all PR- and build-level, not commit-level. ADO
is **not public**, so the assisted/unassisted split can be held there safely.

`branch_pushed` is the join key: it maps a set of attributed commits to the remote ref that
became the PR's source branch. Given a collected log, an analysis job can tag PRs in ADO
(build tag `harness-assisted`, or an equivalent field) without any of it being visible on
GitHub.

Note the ordering constraint this creates: **the pipeline can no longer work this out by
itself.** With trailers, `context-verify.yaml` could grep the commits at build time. Without
them, the signal has to reach ADO from the developer's machine, which means the collector
has to exist first. See the design doc's decision D4.

---

## What this costs

Stated up front so nobody discovers it in a review:

- **The collector becomes a blocker, not a nice-to-have.** Trailers worked with zero
  infrastructure. This does not: until logs are collected centrally, a report covers one
  machine.
- **A fresh clone shows 0% assisted, correctly and unhelpfully.** The index is not in the
  repository, so it does not travel with it.
- **Squash-merge is a join, not a fact.** ADO builds the squash commit server-side, so
  there is no local SHA to catch. The route is PR → source commits → index, which works but
  is more fragile than reading a trailer off the merge commit.
- **No permanent provenance record.** If someone asks in two years which code was
  AI-assisted, the answer exists only for the retention window and only for machines that
  reported. A trailer would have answered forever. If a *disclosure obligation* turns out
  to apply, this design does not discharge it and something else will have to — see below.

---

## Governance

This mechanism produces data about how people work, so the constraints on its use are part
of the spec, not an afterthought:

- **Aggregate only.** Report at team and programme level. No per-developer breakdowns, no
  league tables, no performance-management use. The index deliberately carries no identity
  field to make the wrong analysis harder to run by accident.
- **The one pseudonymous id is a deliberate, minimal exception.** The log carries a random
  `install` value so that distinct active developers can be counted at all; it is not
  derived from name, email, or hardware. It makes counting people possible and identifying
  them still not possible — treat any analysis that tries to close that gap as out of
  bounds. See [installing.md](./installing.md#the-installation-id).
- **Announce before enabling.** Developers should know attribution is being recorded before
  their first recorded commit, not discover it in a dashboard.
- **Opt-out is honoured.** `CPP_HARNESS_TELEMETRY=off` suppresses both the usage log and the
  attribution index. An opt-out rate worth worrying about is itself a finding — track it.
- **Deletion is real and should be documented as such.** `rm -rf ~/.cpp-harness` removes
  every record on that machine. Once a collector exists, the same must be true centrally,
  which is part of what D4 has to settle.
- **Check with the appropriate forum** (departmental trade union side / staff engagement)
  before programme-wide rollout.

---

## Open questions

- **Is there a disclosure obligation pulling the other way?** ATRS is aimed at algorithmic
  decision-making rather than developer tooling, so it probably does not bite — but
  "probably" is doing real work in that sentence, and someone in the department will know.
  If the answer is that use must be disclosed, the question becomes *where* (a service-level
  statement, a repo README, an ATRS record), not whether to hide it. A per-commit trailer
  would be an odd way to discharge such an obligation in any case.
- Should stages record what *ran* or what was *accepted at the gate*? Currently run —
  accepted is more meaningful but depends on `/gate` being used consistently.
- Squash-merge: confirm the merge strategy per repo before relying on the commit-level
  numbers. The PR-level join is unaffected.
