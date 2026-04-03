# BlazeDB API Migration Guide

## What Changed

### Password Behavior (Breaking)

- `open(named:password:)` now requires a password (non-optional `String`)
- Previously, `open(named:)` without a password silently injected a development password (`"BlazeDB-Dev-<name>-2024!"`)
- If you have databases created with the old behavior, reopen with the legacy password to migrate:
 ```swift
 let db = try BlazeDBClient.open(named: "yourdb", password: "BlazeDB-Dev-yourdb-2024!")
 ```
 Then export and re-import with your chosen password, or continue using the legacy password explicitly.

### Removed from Public API

- **`@Field` property wrapper** — marked `@available(*, unavailable)`. Use `BlazeStorable` (Codable-based) or `BlazeDocument` protocol instead.
- **Row-level security types** (`RLS`, `SecurityContext`, `PolicyEngine`, `SecurityPolicy`, `AccessManager`, `User`, `Team`) — RLS is not enforced in this release. These types are now internal.
- **Base64 auto-coercion** — strings that look like base64 are no longer silently converted to `Data`. If you need base64 decoding, do it explicitly before storing.
- **Field-name type heuristics** — fields named `isActive`, `createdAt`, etc. are no longer automatically inferred as Bool or Date. Types are determined by their stored `BlazeDocumentField` case only.

### Deprecated (Compiler Warnings with Replacement Guidance)

| Deprecated | Replacement |
|------------|-------------|
| `openDefault(name:password:)` | `open(named:password:)` |
| `openOrCreate(name:password:)` | `open(named:password:)` — all open methods create if absent |
| `openTemporary(name:password:)` | `openForTesting(name:password:)` |
| `openForCLI(name:password:)` | `open(named:password:)` |
| `openForDaemon(name:password:)` | `open(named:password:)` |
| `create(name:password:)` | `open(named:password:)` |
| `init(name:password:)` | `open(named:password:)` or `open(at:password:)` |
| `getHealthStatus()` | `health()` |
| `explainQuery()` | `explain()` |
| `explainDetailed()` | `explain()` |
| `explainAnalyze()` | `explain()` |
| `explainCost()` | `explain()` |
| `insertAsync(_:)` | `insert(_:) async throws` |
| `fetchAsync(id:)` | `fetch(id:) async throws` |
| `updateAsync(id:with:)` | `update(id:data:) async throws` |
| `deleteAsync(id:)` | `delete(id:) async throws` |
| `flush()` | `persist()` |

### Error Taxonomy Changes

- Query structure errors now throw `.invalidQuery` (not `.transactionFailed`)
- Lifecycle/state errors now throw `.invalidData` (not `.transactionFailed`)
- `.transactionFailed` is reserved for actual transaction failures (write conflicts, WAL failures, commit aborts)

### New Convenience Methods

| Method | Description |
|--------|-------------|
| `open(at:password:)` | Open database at explicit file URL |
| `fetchRequired(id:)` | Fetch or throw `.recordNotFound` |
| `exists(id:)` | Check record existence without full fetch |

### Typed Model Protocols

- **`BlazeStorable`** is the recommended protocol for typed models (Codable-based, KeyPath queries)
- **`BlazeDocument`** remains available for manual mapping when Codable is impractical
- See the decision table in the Getting Started guide

### Health API

- Single blessed entry point: `health() -> HealthReport`
- `observe() -> ObservabilitySnapshot` remains separate (operational metrics)
- `getHealthStatus()` variants are deprecated
