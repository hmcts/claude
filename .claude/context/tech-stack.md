# HMCTS Tech Stack

## Overview
This file describes the technology stack in use on this project.
All agents must consult this before making implementation or tooling decisions.

---
## Languages and frameworks
| Layer        | Technology                | Notes                                      |
|--------------|---------------------------|--------------------------------------------|
| Backend      | Java 25 / Spring Boot 3.x | Preferred for new services                 |
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
| Component    | Technology              |
|--------------|-------------------------|
| Logs         | Azure Monitor / Log Analytics |
| Metrics      | Azure Monitor, Prometheus |
| Alerts       | PagerDuty               |

---

## Sandbox environment
- Namespace: `[project]-sandbox`
- Ingress: `https://[service]-sandbox.platform.hmcts.net`
- Deployed via: Flux CD watching the `sandbox` overlay in the GitOps repo
- Smoke test base URL: set in `TEST_BASE_URL` environment variable
