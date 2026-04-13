# HMCTS SDLC Pipeline — Orchestrator

## Project context
This is an HMCTS engineering project. All work must comply with HMCTS engineering standards,
GDS Service Manual principles, and MOJ security and accessibility requirements.

Always load context/tech-stack.md and context/hmcts-standards.md before any pipeline stage.

---

## Pipeline stages

Run stages in order. Do not skip or reorder. Halt at every human gate before proceeding.

| # | Stage          | Agent file                        | Gate   |
|---|----------------|-----------------------------------|--------|
| 1 | Requirements   | agents/requirements-analyst.md    | Human  |
| 2 | User Story     | agents/story-writer.md            | Human  |
| 3 | Test Specs     | agents/test-engineer.md           | Human  |
| 4 | Code           | agents/implementation.md          | Auto   |
| 5 | Code Review    | agents/code-reviewer.md           | Human  |
| 6 | Build & Test   | agents/ci-orchestrator.md         | Auto   |
| 7 | Deploy Sandbox | agents/deployer.md                | Human  |

---

## Shared skills (available to all agents)

| Skill file                              | Use when                                      |
|-----------------------------------------|-----------------------------------------------|
| skills/write-acceptance-criteria.md     | Deriving testable ACs from any requirement    |
| skills/generate-bdd-specs.md            | Writing Cucumber/Gherkin feature files        |
| skills/accessibility-check.md          | WCAG 2.1 AA review of any UI component        |
| skills/review-checklist.md             | Code review pass/fail checklist               |
| skills/adr-template.md                 | Recording any architecture decision           |

---

## Artefact output convention

All pipeline artefacts are written to `/docs/pipeline/` in the repo:

```
docs/pipeline/
├── requirements.md
├── user-stories/
│   └── <story-id>.md
├── test-specs/
│   └── <story-id>.feature
├── adrs/
│   └── <NNN>-<title>.md
└── deploy-notes.md
```

---

## Hard rules

- Never proceed past a human gate without explicit confirmation.
- Never invent requirements, ACs, or test data — flag unknowns as open questions.
- Every story must have a linked Jira ticket before the test stage begins.
- All code must pass the review checklist before CI is triggered.
- Accessibility (WCAG 2.1 AA) is non-negotiable for any user-facing output.
- Do not store PII, case data, or court reference numbers in artefacts or prompts.
- If confidence in a decision is low, write an ADR and surface it for review.
