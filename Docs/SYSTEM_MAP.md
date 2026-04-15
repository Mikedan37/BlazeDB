# BlazeDB System Map

**Canonical engineering source of truth for what exists, what state it is in, and where it lives.**

This document tracks subsystems at a meaningful granularity — not every struct, but every surface a maintainer or contributor needs to reason about. It is not marketing material. It is not a roadmap. It is a map of the repo as it currently is.

For onboarding, see `README.md`.
For CI lanes and test tiers, see `Docs/Testing/CI_AND_TEST_TIERS.md`.
For API stability commitments, see `Docs/API_STABILITY.md`.
For release line policy, see `Docs/RELEASE_POSTURE.md`.

---

## How to Read Status

| Status | Meaning |
| ------ | ------- |
| **Stable** | Shipped, tested in CI, part of the public onboarding path. Breaking changes require a major version bump. |
| **Advanced / Opt-in** | Available but not the default path. Requires explicit enablement or build configuration. |
| **Internal** | Present in source, compiled into the target, but not part of the documented public API surface. |
| **Partial** | Implementation exists but is incomplete, missing docs, or missing stable creation/configuration APIs. |
| **Deferred** | Code exists in the repo but is excluded from `BlazeDBCore` and the default build. Not shipped. |
| **Blocked** | Has a known issue preventing inclusion or use. Tracked by a specific GitHub issue. |

| Surface | Meaning |
| ------- | ------- |
| **Public** | Documented, stable API. Safe for external consumers. |
| **Public with caveats** | Usable but with platform restrictions, footguns, or missing docs. |
| **Internal only** | Implementation detail. Not part of the supported contract. |
| **Not shipped** | Excluded from the default library product. |

---

## Feature Inventory

### Core Engine

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Document store (single-collection) | Stable | Public | `Core/DynamicCollection.swift` | — | All record types share one encrypted collection per DB file |
| Client lifecycle (open / close / validate) | Stable | Public | `Exports/BlazeDBClient+EasyOpen.swift`, `+Convenience.swift`, `+DX.swift`, `+Lifecycle.swift`, `+Compatibility.swift` | — | `open(named:)`, `openOrCreate()`, `close()`; `FormatVersion` on-disk compat check |
| CRUD operations | Stable | Public | `Exports/BlazeDBClient.swift`, `Core/DynamicCollection.swift` | — | insert/fetch/update/delete/fetchAll; batch upsert via `+Batch.swift`; **`fetchAll()` silently drops records that fail to decode** (`try?` in bulk path) while individual `fetch(id:)` throws — behavioral split |
| Record encoding (BlazeBinary + JSON) | Stable | Internal | `Utils/BlazeBinary*.swift`, `Core/BlazeRecordEncoder.swift`, `Core/BlazeRecordDecoder.swift` | — | BlazeBinary codec (18 files in `Utils/`); JSON legacy supported |
| Record builder DSL | Internal | Public with caveats | `Core/BlazeRecordDSL.swift` | — | Public `RecordBuilder` / `RecordField`; not referenced in examples or onboarding docs |
| Multi-database manager | Advanced / Opt-in | Public with caveats | `Core/BlazeDBManager.swift` | — | `BlazeDBManager.shared`; mount/unmount/switch databases; used by CLI tools |
| Change observation | Internal | Public with caveats | `Core/ChangeObservation.swift`, `Observability/BlazeDBSnapshot.swift` | — | `db.observe { changes in }` pub/sub; `DatabaseChange`, `ObserverToken`; 50ms coalesced batching |
| `BlazeDBError` unified error model | Stable | Public | `Exports/BlazeDBClient.swift` | — | 15 cases covering CRUD, transactions, migrations, queries, concurrency, integrity, security; `LocalizedError` with actionable messages; every public API throws this type |
| Metadata store | Stable | Internal | `Core/MetaStore.swift`, `Storage/StorageLayout.swift` | — | Index map, deleted pages, schema version |
| Page-based storage | Stable | Internal | `Storage/PageStore.swift` | — | 4KB pages, AES-256-GCM encrypted |
| Record cache | Internal | Internal | `Core/RecordCache.swift` | — | In-memory LRU |
| Lazy records | Internal | Internal | `Core/LazyRecord.swift`, `Core/LazyFieldRecord.swift` | — | Deferred decoding |
| Triggers | Partial | Public with caveats | `Core/Triggers.swift` | — | Public `registerTrigger`, `onInsert`, `onUpdate`, `onDelete` on `BlazeDBClient`; persistence gated behind `#if !BLAZEDB_LINUX_CORE` |

### Storage and Durability

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| WAL (write-ahead log) | Stable | Internal | `Storage/WriteAheadLog.swift`, `Storage/WALEntry.swift` | — | Binary WAL; fsync before main-file write |
| Crash recovery / WAL replay | Stable | Internal | `Storage/RecoveryManager.swift` | — | Replays committed entries on init; **uncommitted transactions silently discarded**; corrupt mid-WAL entry is a hard failure (DB refuses to open); no "skip recovery" mode |
| Durability manager | Stable | Internal | `Storage/DurabilityManager.swift` | — | LSN allocation, checkpoint metadata |
| Page cache | Stable | Internal | `Storage/PageCache.swift` | — | LRU, 1000-page default (~4MB); O(n) eviction via array scan; cache size not configurable via public API; thread-safe via `NSLock` (independent of collection's GCD queue) |
| Overflow pages | Stable | Internal | `Storage/PageStore+Overflow.swift` | — | Records larger than one page |
| Compression | Stable | Internal | `Storage/PageStore+Compression.swift`, `Storage/CompressionSupport.swift` | [#43](https://github.com/Mikedan37/BlazeDB/issues/43) | zlib; Linux parity tracked in #43 |
| Vacuum / compaction | Internal | Internal | `Storage/VacuumCompaction.swift`, `VacuumOperations.swift`, `VacuumRecovery.swift` | — | Page reclamation; no public API |
| Page reuse GC | Internal | Internal | `Core/PageReuseGC.swift` | — | Free-page allocation/reclaim; distinct from vacuum compaction |
| Storage manager | Partial | Public with caveats | `Storage/StorageManager.swift` | — | Public `performCleanup()`, `databaseDiskUsage()`; no docs or onboarding path |
| Backup / export | Stable | Public | `Storage/BlazeDBBackup.swift`, `Exports/BlazeDBClient+Export.swift`, `Exports/BlazeDBImporter.swift` | — | `db.export(to:)` produces deterministic JSON (`DatabaseDump`) with SHA256 tamper detection across supported platforms — see `Core/DumpFormat.swift` |
| Forensics | Internal | Internal | `Storage/BlazeDBForensics.swift` | — | Low-level page inspection |

### Transactions and Concurrency

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Explicit transactions | Stable | Public | `Exports/BlazeDBClient.swift`, `Transactions/` | — | `beginTransaction()` / `commitTransaction()` / `rollbackTransaction()`; savepoints |
| MVCC (multi-version concurrency) | Advanced / Opt-in | Public with caveats | `Core/MVCC/`, `Exports/BlazeDBClient+MVCC.swift` | — | `db.setMVCCEnabled(true)`; snapshot isolation |
| GCD concurrent-read / barrier-write | Stable | Internal | `Core/DynamicCollection.swift` | — | Per-collection `DispatchQueue(.concurrent)`; queue label is placeholder `com.yourorg.blazedb` (indistinguishable in Instruments); `fetchAll` on Apple has 5-second static in-memory cache (`NSLock`-guarded, independent of queue) |
| Page garbage collector | Internal | Internal | `Core/MVCC/PageGarbageCollector.swift`, `AutomaticGC.swift` | — | Automatic (60s interval / 100 txn / 3.0 avg versions threshold) + manual GC; **holds `VersionManager` lock during collection — blocks all MVCC reads and writes**; only runs when MVCC is enabled |
| Async APIs | Advanced / Opt-in | Public with caveats | `Exports/BlazeDBClient+AsyncOptimized.swift`, `Core/DynamicCollection+Async.swift` | — | `insertAsync`, `fetchAsync`, etc. Gated: `#if !BLAZEDB_LINUX_CORE` — Apple platforms only |

### Encryption and Security

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| AES-256-GCM page encryption | Stable | Internal | `Storage/PageStore.swift` | — | Always-on in production; per-page auth tags |
| Key management | Stable | Internal | `Crypto/KeyManager.swift` | — | PBKDF2-HMAC-SHA256, 600k iterations (100k in tests, configurable via `BLAZEDB_PBKDF2_ITERATIONS` env var); `CryptoKit` / `swift-crypto`; per-DB salt; legacy `KeySource.password` path uses hardcoded static salt (deprecated) |
| HMAC-SHA256 metadata signing | Stable | Internal | `Storage/StorageLayout+Security.swift` | — | Tamper detection on metadata |
| Argon2 KDF | Internal | Internal | `Crypto/Argon2KDF.swift` | — | Argon2-inspired, **not standards-compliant Argon2id**; not called by `KeyManager` in production — actual KDF is PBKDF2 (see Key management row); dead code for key derivation purposes |
| Forward secrecy manager | Internal | Internal | `Crypto/ForwardSecrecyManager.swift` | — | Key rotation helpers |
| Row-level security (RLS) | Partial | Internal | `Security/RLSPolicy.swift`, `Security/PolicyEngine.swift`, `Security/AccessManager.swift` | — | Policy infrastructure exists; not enforced by default |
| Security context / policy | Internal | Internal | `Security/SecurityContext.swift`, `SecurityPolicy.swift`, `SecurityAuditor.swift` | — | Audit and policy evaluation infrastructure |
| Certificate pinning | Internal | Internal | `Security/CertificatePinning.swift` | — | TLS pinning helpers |
| Secure enclave key manager | Internal | Internal | `Security/SecureEnclaveKeyManager.swift` | — | Apple Keychain path; `#if canImport(Security)` |
| User context / key unlock | Internal | Internal | `Security/BlazeUserContext.swift`, `Security/KeyUnlockProvider.swift` | — | User-scoped security context and key unlock |
| Password strength validator | Internal | Internal | `Security/PasswordStrengthValidator.swift` | — | `KeyManager` enforces `.recommended` preset: min 12 chars, uppercase + lowercase + numbers required; configurable via `Requirements` |

### Typed Model Layer

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| `BlazeStorable` protocol | Stable | Public | `Codable/CodableIntegration.swift` | — | `Codable + Identifiable where ID == UUID`; recommended path; **no bridge to `BlazeDocument`** — cannot use `@BlazeQueryTyped` without rewriting model; nested Codable structs encode to `.dictionary(...)` (not `.string(json)` — fixed in [#80](https://github.com/Mikedan37/BlazeDB/issues/80)); legacy `.string(json)` nested objects still decode via two-pass fallback |
| `TypedStore<T>` | Stable | Public | `Codable/TypedStore.swift` | — | `db.typed(T.self)` — CRUD + KeyPath queries; `fetchAll()`, `TypeSafeQueryBuilder.all()`, and `count()` filter by decodability (`compactMap` / `try?`), silently skipping records that cannot decode as `T` |
| `BlazeDocument` protocol | Stable | Public with caveats | `TypeSafety/BlazeDocument.swift` | [#37](https://github.com/Mikedan37/BlazeDB/issues/37) | Manual `toStorage()` / `init(from:)` mapping; required for `@BlazeQueryTyped`; default `storage` is **deprecated** — on `toStorage()` failure it **logs** (error) and returns `[:]` (not safe to persist); use `try toStorage()` or `try resolveStorage()` when errors must propagate; typed `insert`/`update` paths call `toStorage()` directly — see [#88](https://github.com/Mikedan37/BlazeDB/pull/88); no bridge from `BlazeStorable` |
| `BlazeDataRecord` (raw API) | Stable | Public | `Exports/BlazeTypes.swift` | — | Dynamic schemas, migration scripts |
| `BlazeDocumentField` value type | Stable | Public | `Core/BlazeDocumentField.swift` | — | `.string`, `.int`, `.bool`, etc. |

### Query System

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| `QueryBuilder` (field-name) | Stable | Public | `Query/QueryBuilder.swift` | — | `db.query().where("field", equals: .value).execute()` |
| `TypeSafeQueryBuilder` (KeyPath) | Stable | Public | `Query/QueryBuilderKeyPath.swift` | — | `users.query().where(\.age, greaterThan: 21).all()` |
| Query planner | Stable | Internal | `Query/QueryPlanner.swift` | — | Strategy selection only; `.regularIndex` path still fetches all records and filters in memory; `.vectorIndex`, `.fullTextIndex`, `.hybrid` strategies **fall back to sequential scan** — index-accelerated execution not yet wired |
| Query explain | Stable | Public | `Query/QueryPlanner+Explain.swift`, `QueryBuilder+Explain.swift` | — | `query.explain()` |
| Full-text search | Partial | Internal | `Query/FullTextSearch.swift`, `Query/AdvancedSearch.swift` | — | Inverted index integration; no public stable creation API |
| Aggregation | Partial | Public with caveats | `Query/BlazeAggregation.swift`, `Query/WindowFunctions.swift` | — | Sum/avg/count/min/max; window functions internal |
| Joins | Internal | Internal | `Query/BlazeJoin.swift` | — | Cross-collection join within same DB |
| Subqueries / CTEs | Internal | Internal | `Query/Subqueries.swift`, `CTE.swift` | — | Infrastructure present |
| Spatial queries | Partial | Public with caveats | `Query/QueryBuilder+Spatial.swift`, `Exports/BlazeDBClient+Spatial.swift` | — | Builder + client APIs; `enableSpatialIndex()` / `rebuildSpatialIndex()` |
| Vector queries | Partial | Public with caveats | `Query/QueryBuilder+Vector.swift`, `Exports/BlazeDBClient+Vector.swift` | — | Builder + client APIs; `enableVectorIndex()` / `rebuildVectorIndex()` |
| Query cache | Internal | Internal | `Query/QueryCache.swift` | — | In-memory result cache |
| Query profiling | Internal | Internal | `Query/QueryProfiling.swift` | — | Per-query timing |

### Indexing

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Secondary indexes (compound key) | Internal | Internal | `Core/CompoundIndexKey.swift`, `Core/WorkspaceIndexing.swift` | — | Used internally by query engine |
| B-tree index | Internal | Internal | `Storage/BTreeIndex.swift` | — | Storage-level data structure; **not consumed by query execution path** — planner uses for cost estimation only |
| Inverted index (FTS) | Internal | Internal | `Storage/InvertedIndex.swift` | — | Backing for full-text search |
| Vector index | Internal | Internal | `Storage/VectorIndex.swift` | — | Nearest-neighbor search backing |
| Spatial index | Internal | Internal | `Storage/SpatialIndex.swift` | — | Geo-spatial query backing |
| Ordering index | Internal | Internal | `Query/OrderingIndex.swift` + Advanced + Performance | — | Pre-sorted result optimization |

### Schema and Migration

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Schema versioning | Stable | Public | `Core/SchemaVersion.swift` | — | `SchemaVersion(major:minor:)` |
| Migration planning / execution | Stable | Public | `Core/MigrationPlan.swift`, `Core/MigrationExecutor.swift` | — | `planMigration(to:)` / `executeMigration(plan:)` |
| Auto-migration | Stable | Public | `Core/AutoMigration.swift` | — | Field-addition heuristics |
| `BlazeDBMigration` protocol | Stable | Public | `Core/BlazeDBMigration.swift` | — | `up(db:)` / `down(db:)` |
| Schema validation | Internal | Internal | `Core/SchemaValidation.swift` | — | Constraint checking |
| Unique / foreign key / check constraints | Internal | Internal | `Core/UniqueConstraints.swift`, `Core/ForeignKeys.swift`, `Core/CheckConstraints.swift` | — | Infrastructure; no public creation API |
| Migration progress monitor | Deferred | Not shipped | `Migration/MigrationProgressMonitor.swift` | — | Excluded from `BlazeDBCore`; depended on by CoreData/SQLite migrators |
| CoreData / SQLite migrators | Deferred | Not shipped | `Migration/CoreDataMigrator.swift`, `SQLiteMigrator.swift`, `SQLMigrator.swift` | — | Excluded from `BlazeDBCore` |

### SwiftUI Integration

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| `@BlazeQuery` | Stable | Public with caveats | `SwiftUI/BlazeQuery.swift` | — | Apple platforms only; `#if canImport(SwiftUI)`; **hard dependency on `ChangeObservation` subsystem** (`ObserverToken`, `db.observe()`); changes to observation API break SwiftUI wrappers |
| `@BlazeQueryTyped` | Stable | Public with caveats | `SwiftUI/BlazeQueryTyped.swift` | — | Requires `BlazeDocument`, not `BlazeStorable`; **no bridge protocol** — `BlazeStorable` users must rewrite models to use typed queries; same `ChangeObservation` dependency as `@BlazeQuery` |

### Distributed / Transport

All distributed code is **excluded from `BlazeDBCore`** and **not shipped** in the default library product.

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Sync engine | Deferred | Not shipped | `Distributed/BlazeSyncEngine.swift` | — | Excluded from BlazeDBCore |
| Server | Deferred | Not shipped | `Distributed/BlazeServer.swift`, `Exports/BlazeDBServer.swift` | — | Excluded from BlazeDBCore |
| Operation model | Deferred | Not shipped | `Distributed/BlazeOperation.swift`, `Distributed/BlazeOperation+BlazeBinary.swift` | — | Sync operation types + serialization |
| TCP relay | Deferred | Not shipped | `Distributed/TCPRelay.swift` | — | `import Network` — Apple-only |
| WebSocket relay | Deferred | Not shipped | `Distributed/WebSocketRelay.swift` | — | |
| Unix domain socket relay | Deferred | Not shipped | `Distributed/UnixDomainSocketRelay.swift` | — | |
| In-memory relay | Deferred | Not shipped | `Distributed/InMemoryRelay.swift` | — | Test-only transport |
| Secure connection | Deferred | Not shipped | `Distributed/SecureConnection.swift` | [#73](https://github.com/Mikedan37/BlazeDB/issues/73) | `import Network` — Apple-only |
| Cross-app sync | Deferred | Not shipped | `Distributed/CrossAppSync.swift` | — | |
| Discovery / topology | Deferred | Not shipped | `Distributed/BlazeDiscovery.swift`, `BlazeTopology.swift` | — | |
| Connection pool | Deferred | Not shipped | `Distributed/ConnectionPool.swift` | — | |
| Distributed GC suite | Deferred | Not shipped | `Distributed/*GC.swift` (7 files) | — | Sync metadata, relay memory, operation log cleanup |
| Security validator | Deferred | Not shipped | `Distributed/SecurityValidator.swift` | — | Transport-layer validation |
| Distributed client exports | Deferred | Not shipped | `Exports/BlazeDBClient+Discovery.swift`, `+Sync.swift`, `+Telemetry.swift`, `+SharedSecret.swift` | — | Excluded from `BlazeDBCore`; public extensions for sync/discovery/shared-secret |
| Sync staging primitives | Deferred | Not shipped | `DistributedStaging/SyncPrimitives.swift` | — | Stub target |

See `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` for rationale.

### Telemetry

| Feature | Status | Surface | Code location | Tracking | Notes |
| ------- | ------ | ------- | ------------- | -------- | ----- |
| Metrics collector | Deferred | Not shipped | `Telemetry/MetricsCollector.swift`, `MetricEvent.swift`, `TelemetryConfiguration.swift` | — | Excluded from BlazeDBCore |
| Telemetry staging | Deferred | Not shipped | `TelemetryStaging/TelemetryPrimitives.swift` | — | Stub target |

### CLI Tools

| Tool | Status | Surface | Code location | Notes |
| ---- | ------ | ------- | ------------- | ----- |
| `BlazeDoctor` | Stable | Public | `BlazeDoctor/` | Health checks, insert/fetch/delete probe |
| `BlazeDump` | Stable | Public | `BlazeDump/` | Export, restore, verify backups |
| `BlazeInfo` | Stable | Public | `BlazeInfo/` | Stats, health, schema version |
| `BlazeShell` | Stable | Public | `BlazeShell/` | Interactive REPL |
| `BlazeDBBenchmarks` | Internal | Internal | `BlazeDBBenchmarks/` | Performance benchmarks |

### Examples

| Example | Target | Notes |
| ------- | ------ | ----- |
| `HelloBlazeDB` | `Examples/HelloBlazeDB/` | Primary onboarding example; depends on umbrella `BlazeDB` |
| `BasicExample` | `Examples/BasicExample/` | Minimal usage; depends on `BlazeDBCore` |
| `ReferenceConsumer` | `Examples/ReferenceConsumer/` | API surface consumer; depends on umbrella `BlazeDB` |

Additional example files in `Examples/` (`.swift` files) are standalone reference scripts, not SwiftPM executable targets.

### Platform Support

| Platform | Status | CI | Notes |
| -------- | ------ | -- | ----- |
| macOS 15+ | Stable | Primary blocking lane (`ci.yml`) | Xcode Swift |
| iOS 15+ | Stable | Xcode builds | |
| watchOS 8+ | Stable | Declared in Package.swift | Limited CI |
| tvOS 15+ | Stable | Declared in Package.swift | Limited CI |
| visionOS 1+ | Stable | Declared in Package.swift | Limited CI |
| Linux (Swift 6.0+) | Stable | Blocking lane (core + Tier0) | `BLAZEDB_LINUX_CORE` gates **69 files** across spatial, vector, async APIs, trigger persistence, FTS internals, query planner branches — effectively a second operating mode, not just SwiftUI exclusion |
| Android | Partial | Best-effort | `BLAZEDB_LINUX_CORE` path; Swift 6.3+ / NDK |

### Testing and CI

| Lane | Status | Location | Notes |
| ---- | ------ | -------- | ----- |
| Tier 0 (PR gate) | Stable | `BlazeDBTests/Tier0Core/` | Deterministic correctness |
| Tier 1 Fast (PR gate) | Stable | `BlazeDBTests/Tier1Core/` | Nearly full coverage; one file excluded (`SecureConnectionTests.swift` — requires Network framework) — see `CI_AND_TEST_TIERS.md` and `Package.swift` |
| Tier 1 Extended | Stable | `BlazeDBTests/Tier1Extended/` | Weekly + manual; sync tests partially excluded |
| Tier 1 Perf | Stable | `BlazeDBTests/Tier1Perf/` | `measure()` suites |
| Tier 2 / Tier 3 | Stable | `BlazeDBExtraTests/` | Nested package; not in root `swift test` |
| Nightly | Stable | `.github/workflows/nightly.yml` | Depth + TSan + Linux |
| Deep validation | Stable | `.github/workflows/deep-validation.yml` | Weekly soak |

### Developer Tooling

| Feature | Status | Surface | Code location | Notes |
| ------- | ------ | ------- | ------------- | ----- |
| `db.stats()` | Stable | Public | `Exports/BlazeDBClient+Stats.swift` | Record count, size; interpretation via `DatabaseStats+Interpretation.swift` |
| `db.health()` | Stable | Public | `Exports/BlazeDBClient+HealthCheck.swift`, `Exports/DatabaseHealth.swift` | Health report + warnings; resource limits via `DatabaseHealth+Limits.swift` |
| Monitoring framework | Stable | Public | `Exports/BlazeDBClient+Monitoring.swift` | `DatabaseMonitoringSnapshot` with 5 info subtypes; 69 public symbols; metadata-only dashboard surface |
| IO trace sink | Internal | Internal | `Storage/IOTraceSink.swift` | `#if DEBUG` on Darwin |
| Storage dashboard stats | Internal | Internal | `Storage/StorageDashboardStats.swift` | |
| Test fault injection | Internal | Internal | `Core/BlazeDBTestFaults.swift` | `#if DEBUG` only |

### BlazeStudio

| Feature | Status | Surface | Location | Notes |
| ------- | ------ | ------- | -------- | ----- |
| Visual companion app | Partial | Not shipped (via SwiftPM) | `BlazeStudio/` | Xcode project; not part of SwiftPM product graph |

---

## Known Blockers and Active Cleanup

| Issue | Area | Summary | Blocks |
| ----- | ---- | ------- | ------ |
| [#73](https://github.com/Mikedan37/BlazeDB/issues/73) | Tests / Transport | SecureConnectionTests in wrong target; split crypto vs transport tests | Tier1 exclusion removal |
| [#43](https://github.com/Mikedan37/BlazeDB/issues/43) | Storage / Linux | Compressed pages (v0x03) Linux/Android parity | Cross-platform compression |
| [#30](https://github.com/Mikedan37/BlazeDB/issues/30) | Storage / Linux | Binary decoding alignment safety audit | Linux reliability |
| [#51](https://github.com/Mikedan37/BlazeDB/issues/51) | CI / Linux | Linux Tier1 enablement and CI contract alignment | Linux parity |
| [#58](https://github.com/Mikedan37/BlazeDB/issues/58) | Docs | Publish explicit shipped-core contract and deferred-feature boundaries | Documentation |

---

## Document Boundaries

This section clarifies what each key document is responsible for to prevent duplication and drift.

| Document | Scope | Not responsible for |
| -------- | ----- | ------------------- |
| **`README.md`** | First-contact onboarding: what it is, quick start, install, core concepts, limitations | Feature inventory, CI details, internal architecture |
| **`Docs/SYSTEM_MAP.md`** (this file) | Canonical feature inventory, status, surface, code locations, blockers | Onboarding prose, deep architecture explanations, API signatures |
| **`Docs/Testing/CI_AND_TEST_TIERS.md`** | CI lane definitions, triggers, test tier purposes, exclusion details | Feature status outside testing |
| **`Docs/API_STABILITY.md`** | API stability commitments and deprecation policy | Implementation details, feature completeness |
| **`Docs/RELEASE_POSTURE.md`** | Release line policy, version strategy, support expectations | Code-level feature inventory |
| **`Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md`** | Why distributed transport is deferred, re-enablement steps | Core engine features |
| **`Docs/COMPATIBILITY.md`** | Platform and Swift version compatibility matrix | Feature inventory |
| **`Docs/Architecture/`** | Deep design docs (storage engine, MVCC, etc.) | Status tracking, issue references |

---

## Governance

**Any PR that materially changes feature surface, support status, platform support, or module boundaries must update this file in the same PR.**

"Materially" means:
- Adding, removing, or renaming a public API
- Moving code between targets (e.g., into or out of `BlazeDBCore`)
- Changing a feature from deferred to shipped (or vice versa)
- Adding or removing platform support
- Adding or removing test target exclusions with an explanation

Bug fixes, internal refactors, and doc-only changes that do not change what is shipped or supported do not require an update.

---

_Last verified against tag **v2.7.4** on `main`. Deep surface census + truth extraction applied._
