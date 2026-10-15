# Skill: Code Review Checklist (HMCTS overlay)

The generic checklist has moved to the [agentic-plugins-marketplace](https://github.com/hmcts/agentic-plugins-marketplace).

Install the generic plugin first:

```
/plugin install review-checklist@agentic-plugins-marketplace
```

The generic plugin covers: Correctness, Test quality, Security, Code quality, Dependencies, Documentation, and Scoring. Accessibility is handled by the separate `accessibility-check` plugin.

This overlay adds HMCTS-specific additions the `code-reviewer` agent must apply on top of the generic checklist.

---

## HMCTS-specific additions

### Test quality (extra)
- [ ] No real PII or court reference numbers in test data

### Security (extra)
- [ ] No connection strings, SAS tokens, or account keys — Managed Identity only (see `context/azure-sdk-guide.md`)
- [ ] No PII in log statements
- [ ] No new Critical or High Snyk findings introduced

### Backward compatibility & conflicts
- [ ] Every changed event, API, schema, Drools rule, or shared UI component is listed in the design's "Compatibility & Conflicts" section
- [ ] Event and API changes are additive or versioned — nothing removed or renamed that an existing consumer uses
- [ ] Liquibase changesets are non-destructive and include rollback
- [ ] New user-facing behaviour that changes existing behaviour is behind a feature toggle, default off
- [ ] `@regression` tests for affected journeys exist and pass; none deleted or loosened without justification

### Spring Boot template alignment (Spring Boot services)
- [ ] `build.gradle`, `gradle/*.gradle`, `Dockerfile`, `logback.xml`, `.github/workflows/` unchanged from template (or ADR recorded)
- [ ] `spring.application.name` and `management.metrics.tags.service` match the repo name
- [ ] Java package consistent with naming convention; no template placeholder left behind
- [ ] Template sample code (e.g., `ExampleController`) removed if not kept intentionally

### Logging (JSON mandatory)
- [ ] Logs are JSON to stdout via `logstash-logback-encoder` (see `context/logging-standards.md`)
- [ ] MDC contains `correlationId` and `requestId` on every request
- [ ] No Authorization/Cookie headers, secrets, or PII in log output
- [ ] Log levels used correctly: WARN for expected business errors, ERROR for unexpected failures

### Cloud-Native / Azure
- [ ] Container runs as non-root (`USER app`); base image from HMCTS ACR
- [ ] Liveness/readiness probes wired to Spring Boot Actuator health groups
- [ ] Graceful shutdown, HTTP/2, forward-headers strategy unchanged from template
- [ ] All config via env vars; no hardcoded endpoints or credentials
- [ ] Managed Identity assigned via Helm; workload identity annotation present

### Accessibility (UI stories only)
Run the `accessibility-check` skill (install `accessibility-check@agentic-plugins-marketplace` + apply the HMCTS overlay at `.claude/skills/accessibility-check.md`).

### Dependencies (extra)
- [ ] Licence compatible with HMCTS/MOJ policy — no GPL

### HMCTS scoring overrides
- Any FAIL in **Accessibility** (UI story) → **block merge, must fix** (HMCTS treats a11y failures as equivalent to security failures)
- Any unresolved **PII leak** in logs or test data → **block merge, must fix**
- Any **unversioned breaking change** to an event, API, or schema with existing consumers → **block merge, must fix**
