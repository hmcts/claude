# Skill: Accessibility Check

## Purpose
Ensure any user-facing output meets WCAG 2.1 AA as required by HMCTS / GDS standards.
Used by: test-engineer, code-reviewer, deployer.

## When to apply
- Any story that produces HTML output (pages, components, error messages, forms)
- Any story modifying navigation, focus management, or dynamic content

## Automated checks (axe-core)
Add the following assertion to the integration test for every new page or component:

```java
// Spring Boot / Selenium example
AxeBuilder axeBuilder = new AxeBuilder();
Results results = axeBuilder.analyze(driver);
assertThat(results.getViolations()).isEmpty();
```

```javascript
// Node / Playwright example
const { checkA11y } = require('axe-playwright');
await checkA11y(page, null, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa'] } });
```

## Manual checks (required for these scenarios)
The following cannot be fully automated and must be checked by a human:

| Check                            | Guidance                                                  |
|----------------------------------|-----------------------------------------------------------|
| Keyboard navigation              | Tab through all interactive elements — logical order?     |
| Focus visible                    | Is the focus ring visible on all interactive elements?    |
| Screen reader (VoiceOver/NVDA)   | Are form labels, error messages, and headings announced?  |
| Colour contrast                  | 4.5:1 for normal text, 3:1 for large text (use Stark)     |
| Error identification              | Errors linked to fields via `aria-describedby`            |
| Timeout warnings                 | User warned before session timeout with option to extend  |

## GOV.UK / HMCTS component library
Prefer GOV.UK Frontend components — they are pre-tested for WCAG 2.1 AA.
Do not build custom implementations of: buttons, inputs, error summaries, breadcrumbs,
accordions, tabs, or date inputs when GOV.UK Frontend versions exist.

## Failure classification
| Severity | Action                                                  |
|----------|---------------------------------------------------------|
| Critical | Block deployment — must fix before merge                |
| Serious  | Block deployment — must fix before merge                |
| Moderate | Create Jira ticket — fix within current sprint          |
| Minor    | Create Jira ticket — fix in next sprint                 |
