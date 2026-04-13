# HMCTS Engineering Standards

## Overview
All work on this project must comply with the following standards.
Agents must check against these before producing any artefact or code.

---

## GDS Service Manual principles
All services must follow the GDS Service Standard. Key requirements:
- Understand users and their needs before building
- Use simple, clear language — Plain English, reading age ≤9
- Make the service accessible (WCAG 2.1 AA minimum)
- Design for the full journey, including assisted digital
- Test with real users, including those with access needs

Reference: https://www.gov.uk/service-manual

---

## Accessibility
- **Standard**: WCAG 2.1 AA — non-negotiable for all user-facing output
- **Components**: Use GOV.UK Frontend — do not rebuild what already exists
- **Testing**: axe-core automated + manual keyboard and screen reader check
- **Audit**: HMCTS requires an accessibility statement for public-facing services

---

## Security
- **Classification**: Treat all case data as OFFICIAL-SENSITIVE unless told otherwise
- **PII**: No personally identifiable information in logs, error messages, or test data
- **Court references**: No real case numbers, hearing dates, or party names in artefacts
- **Auth**: All services behind IDAM (HMCTS Identity and Access Management)
- **Secrets**: Azure Key Vault only — no `.env` files committed to repos
- **OWASP**: All services must be assessed against OWASP Top 10

---

## Coding standards
- Java: Google Java Style Guide + HMCTS team conventions
- Commits: Conventional Commits format (`feat:`, `fix:`, `test:`, `chore:`)
- Branch names: `feature/PROJ-NNN-short-description`
- PR titles must include the Jira ticket number
- No direct commits to `main` — all changes via PR with ≥1 human approval

---

## Test pyramid and coverage
| Layer         | Coverage target       | Framework             |
|---------------|-----------------------|-----------------------|
| Unit          | ≥80% on new code      | JUnit 5 + Mockito     |
| Integration   | All AC happy paths + top 3 failures | Spring Boot Test |
| Contract      | All inter-service calls | Pact              |
| Accessibility | Zero violations       | axe-core              |
| Smoke         | Critical path only    | Cucumber @smoke       |

---

## Story and ticket conventions
- Stories must be in the Jira project board before implementation starts
- ACs must be in Given/When/Then format
- Definition of Done must be checked before transitioning to Done
- `claude-generated` label applied to all AI-generated artefacts for audit purposes

---

## Architecture decision records
An ADR is required for:
- Any new external dependency
- Any deviation from this tech stack
- Any security or data handling decision
- Any integration pattern not previously used on the project

ADRs are stored in `docs/pipeline/adrs/` and reviewed by the tech lead.

---

## Data protection
- Data Protection Act 2018 and UK GDPR apply
- Do not store or process personal data beyond what the service requires
- Data retention periods must be defined and enforced
- Subject access requests must be supportable by the service design
