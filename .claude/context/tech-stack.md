# HMCTS Tech Stack

## Overview
This file describes the technology stack in use on this project.
All agents must consult this before making implementation or tooling decisions.

## Master source for Spring Boot apps
The canonical, authoritative definitions for a Spring Boot service or API repo
are the HMCTS templates:

- **Service:** [`hmcts/service-hmcts-crime-springboot-template`](https://github.com/hmcts/service-hmcts-crime-springboot-template) — runtime Spring Boot service (Spring Boot 4.0.5, Java 25, Gradle 9.4.1, Flyway, Postgres, OpenTelemetry, logstash JSON logging, PMD, CycloneDX, App Insights agent).
- **API spec:** [`hmcts/api-hmcts-crime-template`](https://github.com/hmcts/api-hmcts-crime-template) — OpenAPI spec repo with naming rules, validation tooling, publishing workflows.
- **Reference examples:** [`hmcts/service-hmcts-springboot-demo`](https://github.com/hmcts/service-hmcts-springboot-demo) — look at the Spring Boot 4 modules only (`postgres-springboot4`). Ignore the Spring Boot 3 demo modules.

Skills [`springboot-service-from-template`](../skills/springboot-service-from-template/SKILL.md) and [`springboot-api-from-template`](../skills/springboot-api-from-template/SKILL.md) walk through adopting them. Do not scaffold Spring Boot apps from scratch; when the template updates, the service picks the update up by refresh, not by duplication.

## Azure-first posture
HMCTS runs on Azure. Cloud-native decisions are governed by
[`azure-cloud-native.md`](./azure-cloud-native.md); Azure SDK usage and
Managed Identity patterns by [`azure-sdk-guide.md`](./azure-sdk-guide.md);
logging by [`logging-standards.md`](./logging-standards.md). Cost and
vendor-lock-in rebuttals are in [`cloud-adoption-rationale.md`](./cloud-adoption-rationale.md) — on-demand only.

---
## Languages and frameworks
| Layer        | Technology                | Notes                                      |
|--------------|---------------------------|--------------------------------------------|
| Backend      | Java 25 / Spring Boot 4.0.5 / Gradle 9.4.1 | Canonical versions track the HMCTS templates (see below) |
| Frontend     | govuk-frontend            | GOV.UK Design System for consistent government UI patterns|
|              |  ngrx                     | Reactive state management                  |
|              |    ngx-bootstrap          |   UI component library |
|              |    Jest or Jasmine        |  Unit testing|
| Scripting    | Github                    |                                            |

## Databases
| Type         | Technology    | Notes                                      |
|--------------|---------------|--------------------------------------------|
| Relational   | PostgreSQL 16 | Via Azure Flexible Server or AKS           |
| Cache        | Redis         | Session and feature flag caching           |

## Messaging / eventing
| Use case     | Technology           | Notes                                      |
|--------------|----------------------|--------------------------------------------|
| Async events | Azure Service Bus    | Standard for cross-service events          |
| Internal     | Spring Application Events | Within a single service boundary      |

## Infrastructure
| Component    | Technology              | Notes                                      |
|--------------|-------------------------|--------------------------------------------|
| Platform     | Azure AKS (Kubernetes)  | HMCTS Reform Platform                      |
| GitOps       | Flux CD                 | All environment deployments via Flux       |
| Helm         | Helm 3                  | Chart per service                          |
| Registry     | Azure Container Registry|                                            |
| Secrets      | Azure Key Vault         | Never hardcode secrets                     |

## CI/CD
| Stage        | Technology              | Notes                                      |
|--------------|-------------------------|--------------------------------------------|
| CI           | GitHub Actions          | All pipelines in `.github/workflows/`      |
| Build        | Gradle (Java), npm      |                                            |
| Static analysis | SonarQube / SonarCloud |                                           |
| Dependency scan | Snyk                 | Critical/High = pipeline block             |
| Artefact     | Docker image → ACR      |                                            |
| Deploy       | Flux CD / Helm          | GitOps repo separate from app repo         |

## Test tooling
| Layer        | Technology                       |
|--------------|----------------------------------|
| Unit         | JUnit 5, Mockito                 |
| Integration  | Spring Boot Test, TestContainers |
| BDD          | Cucumber 7 + Serenity BDD        |
| API          | REST Assured                     |
| Contract     | Pact (consumer-driven)           |
| Accessibility| axe-core, Playwright             |
| UI E2E       | Playwright or Selenium 4         |

## Monitoring
| Component    | Technology              | Notes |
|--------------|-------------------------|-------|
| Logs         | Azure Monitor / Log Analytics | JSON to stdout via logstash-logback-encoder — see `logging-standards.md` |
| Metrics      | Azure Monitor, Prometheus | Micrometer → `/actuator/prometheus`, tags `service`/`cluster`/`region` |
| Tracing      | OpenTelemetry → Azure Monitor | `spring-boot-starter-opentelemetry`; OTLP exporter |
| APM          | Application Insights    | Injected via the Java agent at image build time — **do not** embed the App Insights SDK in code |
| Alerts       | PagerDuty               | |

---

## Sandbox environment
- Namespace: `[project]-sandbox`
- Ingress: `https://[service]-sandbox.platform.hmcts.net`
- Deployed via: Flux CD watching the `sandbox` overlay in the GitOps repo
- Smoke test base URL: set in `TEST_BASE_URL` environment variable
