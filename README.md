# cpp-claude

Shared Claude Code configuration for the **Crime Common Platform (CPP)** — the HMCTS/CPS digital case management platform used across criminal courts in England and Wales.

This repo is the canonical home for Claude Code agents, skills, commands, and context that CPP teams use to accelerate engineering work across ~145 platform repositories (context services, UI apps, Terraform modules, shared libraries, and DevOps tooling).

## Purpose

- **Standardise Claude usage** across Common Platform teams so every engineer has the same agents, prompts, and guardrails.
- **Codify HMCTS engineering standards** (GDS Service Manual, MOJ security, WCAG 2.1 AA) into reusable Claude context.
- **Orchestrate an SDLC pipeline** — requirements → user story → test specs → code → review → CI → deploy — with human gates.
- **Provide spec-driven change management** via OpenSpec for proposing, applying, and archiving changes.

## Repository layout

```
.
├── CLAUDE.md                   # Orchestrator: pipeline stages, rules, artefact conventions
├── .claude/
│   ├── agents/                 # Specialist agents (one per pipeline stage + platform tooling)
│   ├── skills/                 # Reusable capabilities invoked via /<skill-name>
│   ├── commands/               # Slash commands (e.g. opsx)
│   ├── context/                # Shared context: tech stack, HMCTS standards, coding standards
│   └── settings.local.json     # Local Claude Code settings
└── openspec/                   # Spec-driven change workflow
    ├── changes/                # In-flight proposals
    ├── specs/                  # Accepted specs
    └── config.yaml
```

## SDLC pipeline

Defined in [`CLAUDE.md`](./CLAUDE.md). Stages run in order; human gates must not be skipped.

| # | Stage          | Agent                                   | Gate  |
|---|----------------|-----------------------------------------|-------|
| 1 | Requirements   | `agents/requirements-analyst.md`        | Human |
| 2 | User Story     | `agents/story-writer.md`                | Human |
| 3 | Test Specs     | `agents/test-engineer.md`               | Human |
| 4 | Code           | `agents/implementation.md`              | Auto  |
| 5 | Code Review    | `agents/code-reviewer.md`               | Human |
| 6 | Build & Test   | `agents/ci-orchestrator.md`             | Auto  |
| 7 | Deploy Sandbox | `agents/deployer.md`                    | Human |

Artefacts are written to `docs/pipeline/` in the consuming repository (requirements, stories, `.feature` files, ADRs, deploy notes).

## Platform agents

In addition to the pipeline agents, this repo ships CPP-specific agents:

| Agent                      | Use for                                                                  |
|----------------------------|--------------------------------------------------------------------------|
| `doc-generator`            | Auto-generating README / CLAUDE.md for CPP repos                         |
| `event-flow-mapper`        | Tracing cross-context events through producers and consumers             |
| `helm-config-validator`    | Validating Helm values across dev/staging/live environments              |
| `migration-reviewer`       | Reviewing Liquibase changesets for backwards compatibility               |
| `rbac-auditor`             | Auditing Drools RBAC rules across context services                       |
| `test-analyzer`            | Finding coverage gaps and flaky tests across test modules                |
| `research`                 | Deep exploration of cross-context dependencies                           |

## Skills

Shared skills map directly to CPP workflows:

- **Platform**: `context-service-guide`, `context-scaffold`, `mbd-bootstrap`, `dependency-audit`, `api-contract-check`, `pipeline-debug`, `terraform-validate`, `review-pr`
- **Pipeline**: `write-acceptance-criteria`, `generate-bdd-specs`, `accessibility-check`, `review-checklist`, `adr-template`
- **OpenSpec**: `openspec-propose`, `openspec-apply-change`, `openspec-archive-change`, `openspec-explore`

Invoke a skill in Claude Code with `/<skill-name>`.

## Context files

Loaded by agents before any pipeline stage:

- `.claude/context/tech-stack.md` — Java 21, Spring Boot 3.4+, Angular 19, Azure/AKS, CQRS context services
- `.claude/context/hmcts-standards.md` — GDS Service Manual, MOJ security, WCAG 2.1 AA
- `.claude/context/coding-standards.md` — Language and framework conventions used across CPP

## OpenSpec workflow

Spec-driven change management lives under `openspec/`. Use the `opsx:*` (or `openspec-*`) skills to:

1. **Propose** — draft a change with design, specs, and tasks
2. **Explore** — think through requirements before proposing
3. **Apply** — implement tasks from an accepted change
4. **Archive** — finalise a completed change

## Using this repo

Clone it alongside your working CPP repository, or reference it as the shared Claude configuration source. Agents and skills defined here apply to any repo opened under the `cpp/` workspace.

For the full programme context (repo categories, build commands, architecture, CI/CD, deployment), see the workspace-level `CLAUDE.md` at `/Users/dineshsharma/cpp/CLAUDE.md`.

## Hard rules

- Never proceed past a human gate without explicit confirmation.
- Never invent requirements, ACs, or test data — flag unknowns as open questions.
- Every story must have a linked Jira ticket before the test stage begins.
- Accessibility (WCAG 2.1 AA) is non-negotiable for user-facing output.
- Do not store PII, case data, or court reference numbers in artefacts or prompts.
- If confidence is low, write an ADR and surface it for review.
