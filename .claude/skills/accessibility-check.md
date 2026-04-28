# Skill: Accessibility Check (HMCTS overlay)

The generic version of this skill has moved to the [agentic-plugins-marketplace](https://github.com/hmcts/agentic-plugins-marketplace).

Install the generic plugin first:

```
/plugin install accessibility-check@agentic-plugins-marketplace
```

The generic plugin covers: WCAG 2.1 AA automated checks (axe-core Java / Playwright Node / Playwright Python), the manual-check table, and failure severity classification.

This overlay adds the HMCTS-specific requirements.

---

## HMCTS-specific additions

### Policy basis
WCAG 2.1 AA compliance is required by **HMCTS and GDS standards**. It is non-negotiable for any public-facing service.

### GOV.UK / HMCTS component library
Prefer **GOV.UK Frontend** components — they are pre-tested for WCAG 2.1 AA.

Do not build custom implementations of any of the following when a GOV.UK Frontend version exists:
- Buttons
- Inputs
- Error summaries
- Breadcrumbs
- Accordions
- Tabs
- Date inputs

Any deviation requires an ADR recording the accessibility testing done on the custom component.

### Failure handling workflow
HMCTS overrides the generic "Log as an issue" action with the Jira workflow:

| Severity | Action                                                  |
|----------|---------------------------------------------------------|
| Critical | Block deployment — must fix before merge                |
| Serious  | Block deployment — must fix before merge                |
| Moderate | Create Jira ticket — fix within current sprint          |
| Minor    | Create Jira ticket — fix in next sprint                 |

### Used by
- `test-engineer` agent (axe-core hooks in the test scaffolding)
- `code-reviewer` agent (manual checks on UI PRs)
- `deployer` agent (evidence requirement at the deploy gate)
