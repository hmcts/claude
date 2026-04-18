---
name: mbd-bootstrap
description: Bootstrap a new Modern by Default (MbD) Spring Boot service for the Common Platform. Use when creating a new microservice, event processor, or API service.
---

# Modern by Default Service Bootstrap

Scaffolds a new CPP Modern by Default service following the established patterns from `cpp-mbd-idam-integration` and platform conventions.

## When to Use

- User asks to "create a new service", "bootstrap a microservice", "scaffold a new MbD service"
- User wants to replace a legacy WildFly context service with a modern Spring Boot equivalent
- User needs a new event processor, API service, or integration service

## Required Input

Ask the user for:

1. **Service name** — e.g., `cp-mbd-court-schedule` (must start with `cp-mbd-`)
2. **Bounded context** — e.g., `court-schedule`
3. **Service type** — one of:
   - **Event processor** — consumes events from Service Bus, transforms, dispatches (like IDAM integration)
   - **API service** — exposes REST APIs, may have a database
   - **Integration service** — bridges between external systems and CPP contexts
4. **Inbound source** — Service Bus topic, REST API, or both
5. **Outbound target** — which context service(s) or external systems it calls
6. **Stateful or stateless** — does it need a database?

## Scaffold Structure

Generate the following project structure:

```
cpp-mbd-{name}/
├── build.gradle                    # Spring Boot 3.4+, Java 21, dependencies
├── settings.gradle                 # Project name
├── gradle/
│   └── wrapper/                    # Gradle wrapper (8.x)
├── Dockerfile                      # eclipse-temurin:21-jre-alpine
├── CLAUDE.md                       # Service-specific guidance
├── .claude/
│   ├── rules/
│   │   ├── technical-default.md    # Service identity, tech stack
│   │   ├── design_rules.md         # Architecture layers, event flow
│   │   ├── technical-rules.md      # Code generation rules
│   │   └── workflow.md             # Build loop workflow
│   └── agents/
│       ├── code-reviewer.md        # Code review subagent
│       └── qa.md                   # QA/testing subagent
├── src/
│   ├── main/
│   │   ├── java/uk/gov/hmcts/cp/{context}/
│   │   │   ├── Application.java
│   │   │   ├── config/
│   │   │   │   ├── SecurityConfig.java
│   │   │   │   └── JacksonConfig.java
│   │   │   ├── controller/         # (if API service)
│   │   │   ├── consumer/           # (if event processor)
│   │   │   ├── client/             # Outbound REST clients
│   │   │   ├── service/            # Business logic
│   │   │   └── model/              # Records, enums, DTOs
│   │   └── resources/
│   │       ├── application.yaml
│   │       └── logback-spring.xml  # Structured JSON logging
│   └── test/
│       └── java/uk/gov/hmcts/cp/{context}/
│           ├── *Test.java          # Unit tests (JUnit 5 + Mockito)
│           └── *E2ETest.java       # E2E tests (SpringBootTest + WireMock)
└── azure-pipelines.yaml            # CI/CD pipeline
```

## Technical Defaults

Apply these conventions to all generated code:

### build.gradle
```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.4.2'
    id 'io.spring.dependency-management' version '1.1.7'
}

group = 'uk.gov.hmcts.cp'
java.sourceCompatibility = JavaVersion.VERSION_21

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'
    implementation 'org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.4'
    // Add Azure Service Bus if event processor:
    // implementation 'com.azure.spring:spring-cloud-azure-starter-servicebus:5.19.0'
    
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'org.wiremock:wiremock-standalone:3.10.0'
}
```

### Code Conventions
- **Package:** `uk.gov.hmcts.cp.{context}` (not `uk.gov.moj.cpp`)
- **Constructor injection** — never `@Autowired` fields
- **Java records** for DTOs, commands, event payloads
- **`@Operation`** and **`@ApiResponse`** on all controller methods
- **RestClient** (not RestTemplate or WebClient) for outbound HTTP
- **Structured JSON logging** via logback-spring.xml with MDC (correlationId, eventId, eventType)
- **ISO 8601 dates** via JacksonConfig with JavaTimeModule

### application.yaml
```yaml
spring:
  application:
    name: cpp-mbd-{name}
server:
  port: 8080
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: always
```

### Dockerfile
```dockerfile
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

## Post-Scaffold Steps

After generating the scaffold, remind the user to:

1. Verify the service builds: `./gradlew compileJava`
2. Run tests: `./gradlew test`
3. Update the C4 architecture model in `cp-c4-architecture` to include the new service
4. Create the Azure DevOps pipeline using the shared templates
5. Add Helm chart in `cpp-helm-chart` for deployment
6. Register the service in `cpp-flux-config` for GitOps
