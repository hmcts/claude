# HMCTS Claude Code Configuration

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration for HMCTS engineering projects. Provides agents, skills, context files, and an SDLC pipeline orchestrator that enforce HMCTS engineering standards, GDS Service Manual principles, and MOJ security/accessibility requirements.

## Installation

Clone this repo into your project's `.claude/` directory (or symlink it) so Claude Code picks up the configuration automatically.

### Prerequisite — install the agentic plugins marketplace

This repo now depends on the [HMCTS Agentic Plugins Marketplace](https://github.com/hmcts/agentic-plugins-marketplace) for generic, reusable skills (ADRs, BDD workflow, accessibility checks, code review checklist). HMCTS-specific logic stays here as overlays.

Add the marketplace once:

```
/plugin
→ Marketplaces tab → Add: hmcts/agentic-plugins-marketplace
```

The five required plugins (`adr-template`, `bdd-workflow`, `accessibility-check`, `review-checklist`, `openspec`) auto-enable via `.claude/settings.json` in this repo — no individual `/plugin install` calls needed. Run `/reload-plugins` after adding the marketplace and they load automatically.

**One extra prerequisite for `openspec`**: the `openspec` CLI binary must be on your `PATH`. Install it separately before using the `openspec-*` skills — see the [OpenSpec upstream installation instructions](https://github.com/Fission-AI/OpenSpec#installation).

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

Skills fall into two groups: those that live in the marketplace (install via `/plugin`) and those that stay in this repo because they are HMCTS- or CPP-specific.

**From the marketplace** (generic — install via `/plugin install <name>@agentic-plugins-marketplace`):

| Skill | Purpose |
|-------|---------|
| `adr-template` | Record architecture decisions in a consistent ADR format |
| `bdd-workflow` | Write acceptance criteria AND turn them into Gherkin (bundled: `write-acceptance-criteria` + `generate-bdd-specs`) |
| `accessibility-check` | WCAG 2.1 AA via axe-core + manual checks. HMCTS overlay at `.claude/skills/accessibility-check.md` adds GOV.UK Frontend guidance |
| `review-checklist` | Code review pass/fail checklist. HMCTS overlay at `.claude/skills/review-checklist.md` adds Spring Boot / Azure / logging checks |
| `openspec` | OpenSpec workflow — `explore`, `propose`, `apply-change`, `archive-change` bundled. Requires the `openspec` CLI. The `/opsx:*` commands in this repo remain and are parallel implementations of the same logic |

**In this repo** (HMCTS- or CPP-specific, stays local):

| Skill | Purpose |
|-------|---------|
| `springboot-service-from-template` | Stand up a new Spring Boot service using the HMCTS template (`service-hmcts-crime-springboot-template`) as master source |
| `springboot-api-from-template` | Stand up a new HMCTS Marketplace API spec repo from the `api-hmcts-crime-template` |
| `context-service-guide` | **Legacy only.** Navigate existing `cpp-context-*` WildFly services — patterns must not bleed into new Spring Boot work |
| `context-scaffold` | **Legacy only.** Scaffold modules/commands/queries/events within a WildFly context service |
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
| `tech-stack.md` | Languages, frameworks, databases, infrastructure, CI/CD, and test tooling. Points to the HMCTS templates as Spring Boot master source |
| `hmcts-standards.md` | GDS, accessibility, security, coding, Cloud-Native posture, and data protection standards |
| `coding-standards.md` | Java/Spring Boot conventions, commit message format, PR hygiene, logging and dependency rules |
| `azure-cloud-native.md` | Cloud-Native posture on Azure + Shared Responsibility Model (auto-loaded) |
| `logging-standards.md` | Mandatory JSON logging for Spring Boot services (auto-loaded) |
| `azure-sdk-guide.md` | Azure SDK usage + Managed Identity patterns (on-demand, loaded by skills) |
| `cloud-adoption-rationale.md` | Rebuttals to "vendor lock-in" and "cloud is too expensive" arguments (**on-demand only**, not auto-loaded) |

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

- **Backend**: Java 25 / Spring Boot 4.0.5 / Gradle 9.4.1 — **master source is the HMCTS template** [`hmcts/service-hmcts-crime-springboot-template`](https://github.com/hmcts/service-hmcts-crime-springboot-template)
- **API specs**: OpenAPI, from the template [`hmcts/api-hmcts-crime-template`](https://github.com/hmcts/api-hmcts-crime-template)
- **Frontend**: GOV.UK Frontend, ngrx, ngx-bootstrap
- **Database**: PostgreSQL 16, Redis
- **Messaging**: Azure Service Bus (via Azure SDK + Managed Identity)
- **Infrastructure**: Azure AKS, Flux CD, Helm 3
- **CI/CD**: GitHub Actions, Gradle, SonarQube, Snyk
- **Observability**: JSON logs to stdout (logstash-logback-encoder), Micrometer + Prometheus, OpenTelemetry, Application Insights Java agent
- **Testing**: JUnit 5, Cucumber 7 + Serenity BDD, Pact, Playwright, axe-core, Testcontainers


### Contribute to This Repository

Contributions are welcome! Please see the [CONTRIBUTING.md](.github/CONTRIBUTING.md) file for guidelines.

## License

This project is licensed under the [MIT License](LICENSE).