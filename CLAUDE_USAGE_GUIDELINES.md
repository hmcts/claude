# Claude Usage Guidelines — CPP Teams

Audience: **all CPP teams** (backend, frontend, platform/DevOps, QA, architecture).
Purpose: a short, scannable Do's & Don'ts reference for using Claude (Claude Code, claude.ai, IDE integrations) on the Crime Common Platform.

> CPP is a joint HMCTS/CPS programme handling live criminal case data. Treat every Claude interaction as if it leaves the CPP boundary. When in doubt, **don't paste it**.

---

## 1. Security & data handling

| Do | Don't |
|---|---|
| Treat every prompt as if it leaves the CPP boundary — assume third-party processing. | Paste **real case data, PII, witness/victim details, or judicial material** into any Claude surface. |
| Use **synthetic / anonymised data** when debugging case-shaped payloads. | Paste **secrets**: Azure service principals, Key Vault values, DB credentials, JWT signing keys, `.env` contents, kubeconfigs. |
| Strip URNs, defendant names, DOBs, addresses, NINOs, and CJS IDs before pasting. | Connect Claude to **production** databases, Service Bus namespaces, or AKS clusters. |
| Share file paths with Claude, not contents, when the file holds sensitive data. | Upload prod log bundles, heap dumps, or DB exports without scrubbing. |
| Report any accidental disclosure to the CPP security team **immediately**. | Use Claude to draft anything filed at court or sent to a defendant without human legal review. |

---

## 2. Effective prompting & workflow

| Do | Don't |
|---|---|
| Use **plan mode** (Shift+Tab in Claude Code) for non-trivial changes — review the plan before code is written. | Hand Claude vague, multi-context goals ("refactor the hearing service") — break them down first. |
| Scope tasks tightly: one bounded context, one module, one concern at a time. | Skip reading the diff because tests pass — tests verify code correctness, not feature correctness. |
| Provide the **`CLAUDE.md`** project context and point Claude at the specific files/paths involved. | Let Claude design cross-context event flows without a human architect signing off — CQRS/ES decisions are load-bearing. |
| Use **subagents** (Explore, Plan, code-reviewer, migration-reviewer, rbac-auditor, helm-config-validator, etc.) for the work they're designed for. | Rely on Claude's memory of prior conversations as authoritative — verify against current code. |
| Run **`/ultrareview`** on a branch or PR before requesting human review on anything non-trivial. | Treat Claude's first answer as the final answer on architecture, security, or compliance. |
| Ask Claude to *explain* legacy code (cp-* / Libra / XHIBIT integrations) — it's good at orienting newcomers. | |

---

## 3. Code review & quality gates

| Do | Don't |
|---|---|
| **Review every line** of Claude-authored code before commit; you own it. | Bypass pre-commit hooks (`--no-verify`), commit signing, or branch protections — even if Claude suggests it. |
| Run the full local build (`mvn clean verify`, `./gradlew test`, `npm run ci:test`) before pushing. | Force-push to `main`/`master` or shared feature branches based on Claude's suggestion. |
| Ensure **CI pipelines pass** on Azure DevOps — `context-validation.yaml` / `ui-validation.yaml` / `terratest.yaml`. | Merge Claude-generated code with placeholder values, TODOs, or mocked secrets still in place. |
| Have a human review **Liquibase migrations**, **Drools/RBAC rules**, and **Helm values** even if Claude generated them — use the `migration-reviewer` / `rbac-auditor` / `helm-config-validator` subagents as a first pass. | Accept new dependencies Claude proposes without checking they're in `cp-maven-common-bom` or approved by the platform team. |
| Keep commits small and revertable when Claude is involved. | Trust Claude on **legal, regulatory, accessibility (WCAG 2.1 AA), or GDS service standard** decisions — escalate to the relevant SME. |

---

## 4. Tooling, MCP & integrations

| Do | Don't |
|---|---|
| Use the **sanctioned MCP servers** only (Atlassian / Confluence / Jira, Miro, IDE diagnostics) configured by the platform team. | Install unvetted MCP servers or community tools that touch CPP credentials, repos, or networks. |
| Keep **Claude Code permissions** restrictive — approve tool calls per-action until you trust the workflow. | Auto-approve all tool calls (`--dangerously-skip-permissions` or equivalent) on a machine with prod access. |
| Use **memory** (`/memory`) for personal preferences and durable project facts. | Store secrets, case data, or court reference numbers in memory. |
| Use the right subagent for the job — they have scoped tools and produce better output than `general-purpose` for their domain. | Wire Claude into Azure DevOps / GitHub with write tokens beyond what your role already has. |
| Prefer the agents and skills shipped in **`cpp-claude`** — they encode CPP conventions. | Use Claude to mass-create Jira tickets or Confluence pages without team agreement on cadence and ownership. |

---

## Hard rules (non-negotiable)

- **No PII, case data, or court reference numbers** in any Claude prompt, artefact, or memory entry.
- **No secrets** — ever — in prompts, screenshots, or pasted logs.
- **Human gate** required before merging Claude-authored migrations, RBAC rules, Helm values, or anything user-facing.
- **Accessibility (WCAG 2.1 AA)** must be verified by a human for UI work — Claude assists, does not certify.
- **No production access** from any Claude-driven workflow.

---

## Reporting & feedback

- **Suspected data leak / security concern**: contact the CPP security team immediately.
- **Suggestions or corrections to this page**: open a PR against `cpp-claude/CLAUDE_USAGE_GUIDELINES.md`.
- **New patterns worth standardising**: propose via OpenSpec (see `openspec/` in this repo).

---

*Last reviewed: 2026-04-27. This document is mirrored to Confluence (`CPP > Engineering > Claude Usage Guidelines`); the markdown in this repo is the source of truth.*
