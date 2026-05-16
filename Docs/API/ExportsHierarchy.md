# Exports Hierarchy

This is the canonical, opinionated map of `BlazeDB/Exports`.

Purpose: classify what is **first** vs **important but later** without removing symbols.

## Layer 1: Newcomer Default

Start here first.

- `PublicFacadeAPI.swift` - default facade (`BlazeDB.open`, `put/get/query(namespace)`).

Canonical starter snippet: [FACADE_EXAMPLE.md](FACADE_EXAMPLE.md)

## Layer 2: Advanced Embedded API

Core embedded capabilities used after the facade path is understood.

- `BlazeDBClient.swift` - core client engine surface (CRUD, query, transactions, integrity).
- `BlazeTypes.swift` - `BlazeDataRecord` and raw record value container.
- `BlazeRecordKind.swift` - namespace/kind tagging helpers.
- `BlazeDBClient+EasyOpen.swift` - modern open helpers and test open path.
- `BlazeDBClient+TypeSafe.swift` - typed model-oriented CRUD/query helpers.
- `BlazeDBClient+Async.swift` - async API overlays for core operations.
- `BlazeDBClient+Lifecycle.swift` - explicit close and closed-state safety.
- `BlazeDBClient+Migration.swift` - schema version/migration planning and execution.
- `BlazeDBClient+Guardrails.swift` - open-time schema validation helper.
- `BlazeDBClient+Batch.swift` - bulk operation helpers.
- `BlazeDBClient+Lazy.swift` - lazy decoding controls.
- `BlazeDBClient+MVCC.swift` - MVCC and GC controls/stats.
- `BlazeDBClient+Spatial.swift` - spatial index lifecycle controls.
- `BlazeDBClient+Vector.swift` - vector index lifecycle controls.
- `BlazeDBClient+RLS.swift` - row-level security manager plumbing and enforcement hooks.
- `BlazeDBClient+ConvenienceAPI.swift` - small convenience gaps (`fetchRequired`, `exists`).
- `BlazeDBError+Categories.swift` - error category mapping and user guidance.
- `BlazeDBError+Suggestions.swift` - suggestion-rich error messaging helpers.

## Layer 3: Ops / Distributed / Integration

Legitimate surfaces, but not newcomer-first.

- `BlazeDBClient+Stats.swift` - stats snapshot API.
- `BlazeDBClient+Health.swift` - health report API.
- `DatabaseHealth.swift` - health types and analyzer.
- `DatabaseHealth+Limits.swift` - resource-limit checks and enforcement helper.
- `DatabaseStats+Interpretation.swift` - human-readable stats interpretation.
- `BlazeDBClient+Monitoring.swift` - metadata-only monitoring snapshot/export.
- `BlazeDBClient+Observability.swift` - state snapshot observability API.
- `BlazeDBClient+Telemetry.swift` - full telemetry manager integration.
- `BlazeDBClient+Debug.swift` - debug exports and encoding diagnostics.
- `BlazeDBClient+PrettyPrint.swift` - human-readable debug/export formatting.
- `BlazeDBClient+Export.swift` - deterministic database dump export.
- `BlazeDBImporter.swift` - verified restore/import and dump verification.
- `MigrationPlan+PrettyPrint.swift` - migration plan rendering helpers.
- `BlazeDBClient+Sync.swift` - sync helpers (local and remote).
- `BlazeDBClient+Discovery.swift` - discovery and auto-connect helpers.
- `BlazeDBClient+SharedSecret.swift` - shared-secret auth/token sync/server helpers.
- `BlazeDBServer.swift` - high-level server startup wrapper.
- `BlazeDBClient+Workspace.swift` - workspace-specific query helpers.
- `BlazeDBClient+AI.swift` - AI workload persistence helpers.

## Layer 4: Legacy / Transitional / Internal-ish

Keep for compatibility; do not present as first-path APIs.

- `BlazeDBClient+Convenience.swift` - deprecated convenience openers and registry helpers.
- `BlazeDBClient+DX.swift` - deprecated DX aliases around open/test flows.
- `BlazeDBClient+AsyncOptimized.swift` - deprecated `*Async` naming-era APIs.
- `BlazeDBClient+HealthCheck.swift` - deprecated health path superseded by `health()`.
- `BlazeDBClient+Compatibility.swift` - format/version compatibility contract and open-time guards.
- `BlazeDBClient+TelemetryStub.swift` - build-config no-op telemetry compatibility shim.
- `BlazeDBClient+Triggers.swift` - mostly internal trigger metadata persistence plumbing.

## Notes

- Some Layer 2 files are architecturally central but still not the first thing newcomers should learn.
- Layer placement is for curation and onboarding order, not for symbol removal.
