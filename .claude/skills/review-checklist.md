# Skill: Code Review Checklist

## Purpose
Structured pass/fail checklist for the code-reviewer agent.
Produces a consistent, auditable review record on every PR.

## Checklist

### Correctness
- [ ] Implementation covers all ACs in the linked story
- [ ] No obvious logical errors or off-by-one conditions
- [ ] Edge cases identified in the story are handled
- [ ] No dead code paths that are untested

### Test quality
- [ ] All new code covered by at least one test
- [ ] Unit coverage on new code ≥80%
- [ ] Tests assert behaviour, not implementation detail
- [ ] No test that always passes regardless of the code under test
- [ ] No real PII or court reference numbers in test data
- [ ] @wip tags removed before merge

### Security
- [ ] No secrets, API keys, or passwords in code or comments
- [ ] No connection strings, SAS tokens, or account keys (use Managed Identity — `context/azure-sdk-guide.md`)
- [ ] No PII in log statements
- [ ] No raw stack traces in HTTP error responses
- [ ] Input validation on all externally supplied values
- [ ] Authentication/authorisation enforced where required by the story
- [ ] No new Critical or High Snyk findings introduced

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
- [ ] axe-core assertion present in integration tests
- [ ] GOV.UK Frontend components used where available
- [ ] No custom interactive element without keyboard support
- [ ] Error messages programmatically associated with fields

### Code quality
- [ ] Methods are small and single-purpose (no god methods)
- [ ] Names reflect domain language from the story
- [ ] No commented-out code
- [ ] No TODO without a linked Jira ticket
- [ ] No inline linting suppression without an explanatory comment
- [ ] No hardcoded environment-specific values (URLs, ports, credentials)

### Dependencies
- [ ] No new dependency introduced without a comment explaining why
- [ ] No dependency that duplicates an existing one in the project
- [ ] Licence compatible with HMCTS/MOJ policy (no GPL)

### Documentation
- [ ] Public API methods have doc comments
- [ ] README updated if setup steps changed
- [ ] ADR written for any significant architectural decision made

## Scoring
- Any FAIL in Security → **block merge, must fix**
- Any FAIL in Accessibility (UI story) → **block merge, must fix**
- 3+ FAILs in other categories → **changes requested**
- 1–2 FAILs in other categories → **minor changes requested, can merge after fix**
- All PASS → **claude-approved** (human reviewer still required for final approval)
