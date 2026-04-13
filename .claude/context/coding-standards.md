# Coding Standards

## Java / Spring Boot

### Naming
- Classes: PascalCase, noun or noun phrase (`HearingService`, `CaseRepository`)
- Methods: camelCase, verb or verb phrase (`submitHearing`, `findByCaseId`)
- Constants: SCREAMING_SNAKE_CASE
- Packages: lowercase, domain-first (`uk.gov.hmcts.[service].[domain]`)
- Test classes: suffix `Test` for unit, `IT` for integration (`HearingServiceTest`, `HearingControllerIT`)

### Structure (per service)
```
src/
├── main/java/uk/gov/hmcts/[service]/
│   ├── [domain]/          # Domain model and business logic
│   ├── service/           # Application services
│   ├── repository/        # Data access
│   ├── controller/        # REST controllers
│   ├── config/            # Spring configuration
│   └── exception/         # Exception types and handlers
└── test/java/uk/gov/hmcts/[service]/
    ├── unit/              # Unit tests
    ├── integration/       # Integration tests
    └── contract/          # Pact contract tests
```

### Method size
- Methods should do one thing. If a method needs a comment to explain a section, extract that section.
- Target: ≤20 lines per method. Hard limit: 40 lines.

### Error handling
- Use typed exceptions (`HearingNotFoundException extends RuntimeException`)
- Map exceptions to HTTP status in a `@ControllerAdvice` handler — not in individual controllers
- Never return a stack trace in an HTTP response body
- Log at WARN for expected business errors, ERROR for unexpected failures

### Logging
- Use SLF4J with structured log fields where possible
- Log correlation IDs on every request (`X-Request-ID`)
- Never log: passwords, tokens, full request bodies, case party names, dates of birth

### Dependencies
- Manage versions in `build.gradle` dependency constraints block — not per-dependency
- Use Spring Boot BOM for Spring dependencies — do not override versions without reason
- Every new dependency needs a comment: why it was added and what it replaces (if anything)

---

## Commit message format (Conventional Commits)

```
<type>(scope): <short summary>

[optional body — wrap at 72 chars]

[optional footer — Jira ticket, breaking change note]
```

Types: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `ci`, `revert`

Example:
```
feat(hearing): add case reference validation on submission

Validates that case references match the expected format before
persisting to the hearing table.

PROJ-123
```

---

## Pull request hygiene
- Title must include the Jira ticket: `[PROJ-123] Add case reference validation`
- Description must include: what changed, why, how to test
- Maximum 400 lines changed per PR — split larger changes
- All conversations resolved before merge
- Branch deleted after merge
