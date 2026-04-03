# BlazeDB Full RLS Implementation Plan

## Goal

Promote RLS from partial/internal behavior to a clearly supported, consistently enforced feature across public BlazeDB client operations.

## Current State (Audit Summary)

- RLS policy infrastructure exists (`PolicyEngine`, `SecurityContext`, policy models).
- Enforcement is partial and path-dependent.
- Default public CRUD/query paths are not uniformly RLS-gated.
- Some docs historically overstated public/automatic RLS enforcement.

## Target State

RLS should be:

1. **Explicitly configurable** (on/off, fail-open/fail-closed mode).
2. **Uniformly enforced** on all supported public read/write entry points.
3. **Tested end-to-end** through public APIs (not only internal helpers).
4. **Accurately documented** with clear guarantees and caveats.

## Scope Decisions

### In scope

- Public RLS configuration API (minimal, stable).
- Enforcement on:
  - `fetch(id:)`, `fetchAll()`, `fetchBatch`, `fetchPage`, `distinct`, `query().execute()`
  - `insert`, `update`, `delete`, and batch variants
- Consistent context propagation model for policy evaluation.
- Security-focused integration tests and docs updates.

### Out of scope (separate future phase)

- Distributed cross-node policy propagation guarantees.
- Incremental reactive policy-diff propagation to UI.
- Rich policy DSL redesign.

## API Design (Minimal Public Surface)

Introduce a focused public API (names illustrative; preserve existing conventions):

- `enableRLS(mode: RLSMode = .failOpen)` / `disableRLS()`
- `setSecurityContext(_:)` / `clearSecurityContext()`
- `registerPolicy(_:)` / `removePolicy(named:)` / `listPolicies()`

`RLSMode`:
- `.failOpen` (compatibility mode): missing context may allow reads/writes per policy defaults.
- `.failClosed` (strict mode): missing context denies access when RLS is enabled.

## Enforcement Architecture

## 1) Central Gate Layer

Create internal gate helpers used by all public client operations:

- `authorizeRead(record:)`
- `authorizeWrite(operation:recordBefore:recordAfter:)`
- `filterReadable(records:)`

All top-level public operations must route through these helpers.

## 2) Read Path Coverage

Apply policy gates in:

- `fetch(id:)` (single-record allow/deny)
- `fetchAll`, `fetchPage`, `fetchBatch`, `distinct` (filter to readable set)
- `QueryBuilder.execute` and typed query execution path (filter result set before returning)

## 3) Write Path Coverage

Apply policy gates in:

- `insert` (authorize create)
- `update` / `updateFields` / `updateMany` (authorize update against prior/current record)
- `delete` / `deleteMany` (authorize delete)

## 4) Context Handling

- Define one canonical execution context source for each request.
- Remove ambiguous fallbacks where missing context accidentally bypasses checks.
- Enforce mode semantics (`failOpen` vs `failClosed`) in one place.

## 5) Graph / Specialized Paths

- Align graph path behavior with default client behavior.
- If graph has custom context behavior, document and test it explicitly.

## Test Plan

## Tier 1 (fast deterministic)

- Read denied with no context in fail-closed mode.
- Read allowed/denied per policy in both single-record and list paths.
- Write denied for unauthorized principal (`insert/update/delete`).
- Query builder results filtered by policy.
- Batch operations enforce policy per affected record.

## Tier 2 (integration)

- Mixed-role scenario with shared data set:
  - viewer: read-only subset
  - editor: scoped write
  - admin: full access
- Ensure exports/backups use defined RLS stance (either policy-aware or explicitly administrative-only).

## Negative tests

- Missing context when RLS enabled + fail-closed must deny.
- Policy registration with invalid rule shape must fail predictably.
- No silent allow due to empty policy set unless explicitly configured.

## Migration / Compatibility

- Default behavior for existing users should remain unchanged unless RLS is enabled.
- Emit clear logs/warnings when RLS is enabled without context/policies.
- Document upgrade path:
  1. enable in fail-open
  2. validate policies in staging
  3. switch to fail-closed in production

## Documentation Deliverables

When implementation lands:

- `README.md`: short support-state note (no overclaim).
- `Docs/API/API_REFERENCE.md`: concrete public RLS API and guarantees.
- `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md`: practical usage and caveats.
- New focused guide: `Docs/Features/ROW_LEVEL_SECURITY.md` (examples + threat model boundaries).

## Milestones

1. **M1: Public API + read enforcement**
2. **M2: Write enforcement + batch coverage**
3. **M3: QueryBuilder/typed-query integration**
4. **M4: Hardening tests + docs + release notes**

## Release Readiness Criteria

RLS can be called "supported" only when:

- Public API is stable and documented.
- Read + write + query paths are enforced through shared gates.
- Tier1/Tier2 RLS suites pass with both fail-open and fail-closed modes.
- No docs claim behavior stronger than tests prove.
