# HMCTS Claude Code Configuration

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration for HMCTS engineering projects. Provides agents, skills, context files, and an SDLC pipeline orchestrator that enforce HMCTS engineering standards, GDS Service Manual principles, and MOJ security/accessibility requirements.

## Installation

Currently, clone this repo into your project's `.claude/` directory (or symlink it) so Claude Code picks up the configuration automatically.

We are working on an [HMCTS Agentic Plugins Marketplace](https://github.com/hmcts/agentic-plugins-marketplace) that will allow you to install these agents, skills, and commands directly into your project without manually copying files. Stay tuned.

## What's included

### CLAUDE.md — SDLC pipeline orchestrator

The root `CLAUDE.md` defines a gated software delivery pipeline with seven stages:

| # | Stage | Agent | Gate |
|---|-------|-------|------|
| 1 | Requirements | `requirements-analyst` | Human |
| 2 | User Story | `story-writer` | Human |
| 3 | Test Specs | `test-engineer` | Human |
| 4 | Code | `implementation` | Auto |
| 5 | Code Review | `code-reviewer` | Human |
| 6 | Build & Test | `ci-orchestrator` | Auto |
| 7 | Deploy Sandbox | `deployer` | Human |

Human gates require explicit confirmation before proceeding. No stages may be skipped or reordered.

### Agents

Specialised agents in `.claude/agents/`:

| Agent | Purpose |
|-------|---------|
| `requirements-analyst` | Gather and validate requirements |
| `story-writer` | Write user stories with acceptance criteria |
| `test-engineer` | Generate test specifications and BDD feature files |
| `implementation` | Write code that meets the specs |
| `code-reviewer` | Review code against the HMCTS checklist |
| `ci-orchestrator` | Manage build and test execution |
| `deployer` | Deploy to sandbox environments |
| `doc-generator` | Generate project documentation |
| `event-flow-mapper` | Map event flows across services |
| `helm-config-validator` | Validate Helm chart configurations |
| `migration-reviewer` | Review database and data migrations |
| `rbac-auditor` | Audit role-based access control |
| `research` | General-purpose research tasks |
| `test-analyzer` | Analyse test results and failures |

### Skills

Reusable skills in `.claude/skills/`:

| Skill | Purpose |
|-------|---------|
| `write-acceptance-criteria` | Derive testable ACs from requirements |
| `generate-bdd-specs` | Write Cucumber/Gherkin feature files |
| `accessibility-check` | WCAG 2.1 AA review of UI components |
| `review-checklist` | Code review pass/fail checklist |
| `adr-template` | Record architecture decisions |
| `mbd-bootstrap` | Scaffold a new Modern by Default Spring Boot service |
| `context-service-guide` | Navigate and understand `cpp-context-*` services |
| `context-scaffold` | Scaffold modules, commands, queries, events within a context service |
| `review-pr` | Review a pull request |
| `terraform-validate` | Validate Terraform modules and configurations |
| `dependency-audit` | Audit dependency versions across repos |
| `pipeline-debug` | Debug Azure DevOps pipeline configurations |
| `api-contract-check` | Validate API contracts against implementations |

### Slash commands

Custom commands in `.claude/commands/opsx/`:

| Command | Purpose |
|---------|---------|
| `/opsx:explore` | Thinking partner mode — investigate problems and clarify requirements without writing code |
| `/opsx:propose` | Propose a new change with design, specs, and tasks |
| `/opsx:apply` | Implement tasks from a proposed change |
| `/opsx:archive` | Archive a completed change |

### Context files

Shared context in `.claude/context/` that agents load automatically:

| File | Contents |
|------|----------|
| `tech-stack.md` | Languages, frameworks, databases, infrastructure, CI/CD, and test tooling |
| `hmcts-standards.md` | GDS, accessibility, security, coding, and data protection standards |
| `coding-standards.md` | Java/Spring Boot conventions, commit message format, PR hygiene |

## Hard rules

These are enforced across all agents and stages:

- Never proceed past a human gate without explicit confirmation
- Never invent requirements, ACs, or test data — flag unknowns as open questions
- Every story must have a linked Jira ticket before the test stage begins
- All code must pass the review checklist before CI is triggered
- Accessibility (WCAG 2.1 AA) is non-negotiable for any user-facing output
- No PII, case data, or court reference numbers in artefacts or prompts
- If confidence in a decision is low, write an ADR and surface it for review

## Tech stack summary

- **Backend**: Java 25 / Spring Boot 4.x
- **Frontend**: GOV.UK Frontend, ngrx, ngx-bootstrap
- **Database**: PostgreSQL 16, Redis
- **Messaging**: Azure Service Bus
- **Infrastructure**: Azure AKS, Flux CD, Helm 3
- **CI/CD**: GitHub Actions, Gradle, SonarQube, Snyk
- **Testing**: JUnit 5, Cucumber 7 + Serenity BDD, Pact, Playwright, axe-core


### Contribute to This Repository

Contributions are welcome! Please see the [CONTRIBUTING.md](.github/CONTRIBUTING.md) file for guidelines.

## License

This project is licensed under the [MIT License](LICENSE).