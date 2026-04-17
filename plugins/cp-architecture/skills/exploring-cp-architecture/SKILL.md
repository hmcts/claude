---
name: exploring-cp-architecture
description: Use when reviewing cp-context-* pom.xml/build.gradle dep changes, or for CP cross-service architecture questions — service relationships, ownership, boundaries, drift, cross-repo exploration, integration code, module boundaries.
---

## Core principle

The LikeC4 model is authoritative but fallible. When model and code disagree, name which side you suspect is wrong and cite evidence for both.

## Workflows

**W1 — "What is X?"** `search-element` → `read-element`. Prose answer citing dot-notation ID (`cp.{subdomain}.{product}.{component}`) and `link`.

**W2 — "Who talks to X?"** `search-element`/`read-element` first, even if local clones exist. Then call **both** `query-outgoers-graph` and `query-incomers-graph`. Report upstream/downstream with kinds and author **titles**. Core drift moment.

**W3 — "Does this connection exist?"** Resolution order:

1. **Direct edge A→B first** — `query-outgoers-graph` on A, filter for B. If present, compare relationship prose with code intent. Match → supported. Mismatch → semantic drift; name the suspect side.
2. No direct edge? `find-relationship-paths` is **secondary context only**. Indirect A→C→B is context, **not** evidence for direct A→B wiring.
3. Neither: likely new integration, or the model is stale.

**W4 — "Show me the other side."** `read-element` B → read `link` (sibling of `metadata`, not inside it). If using a local clone, verify `origin` matches `link`; otherwise **propose** exact `gh` commands and wait.

**W5 — "Where does this belong?"** `read-project-summary` + `search-element` to scan hierarchy. Suggest placement; challenge duplication if home exists.

## Reading the model

Read prose, not just edges: element `title` / `summary` / `description`, relationship `title` and description, metadata, and `link`.

## Output format

**Answer mode** (explicit question): cite every claim against an element ID, a relationship the model explicitly describes, or a repo link. Quote or paraphrase model prose.

**Check mode** — enter **before any local verdict** when a diff touches:
- a new cross-context `RestClient` / `@Inject` / `@Handles`
- any inter-context `pom.xml` / `build.gradle` coordinate change (new, version bump, scope, removal)
- a new boundary HTTP call or event subscription

MCP floor: `read-element` on both endpoint services **and** `find-relationships` (or `query-outgoers-graph` filtered for the target). Then **support** ("the model already describes this") or **challenge** ("model says A depends on B, not C — either model is stale or wiring is wrong"). Local review alone is **not** a check.

Both modes: dot-notation IDs; include `link` when present; name the suspect side, not "drift detected".

## Scope boundaries

- Never edit `.c4` files; drift is flagged, not fixed here.
- Never fabricate element IDs, relationships, or repo links. If `search-element` returns nothing, say so.
- Never run `gh` without developer approval.
- Don't duplicate `c4-model-maintenance` (DSL authoring).

## Rationalization counters

| Thought | Reality |
|---------|---------|
| "Endpoints, search, scripts, or tests tell me who this service talks to." | Implementation evidence ≠ relationship inventory. Query the model; confidence depends on model coverage, not local completeness. |
| "Step into a sibling checkout / use the DB table / read the test — it answers it." | Cross-repo exploration starts from `search-element`/`read-element` and the `link`. Clone names aren't identity proof; verify `origin` against `link`. |
| "The developer knows their own service — no need to check." | Naming a service is a signal to use the model, not skip it. |
| "Dependency coordinates give me the repo." | Derive repo links from the model `link`, not `group:artifact`. |
| "Run `gh` first, ask later." | Propose exact `gh` commands and wait for approval. |
| "`pom.xml` or new client wiring shows it — I'll review locally." | Cross-context wiring triggers a model check, not a substitute for one. |
| "Just a version bump, nothing structural." | The classifier does not auto-trigger for version-only bumps (v1 gap), but a major-version bump on a cross-context dep may signal a breaking contract change — enter Check mode manually when in doubt. |
| "`read-project-summary` (or any cheap MCP call) satisfies check-mode." | Load the affected element **and** read at least one relationship first. Discovery alone is not a check. |
