# BlazeDB codebase map

**Audience:** contributors who need to find code, tests, and safe change surfaces.  
**Inspected tip:** `0b43a08c` (regenerate mappings if the tree moves).  
**Authority:** implementation → tests → `Package.swift` → CI/scripts → canonical docs.

Related: [LEARNING_PATHS](../Contributing/LEARNING_PATHS.md) · [ISSUE_CODE_INDEX](../Contributing/ISSUE_CODE_INDEX.md) · [Tours](TOURS/) · [ISSUE_GUIDE](../Contributing/ISSUE_GUIDE.md)

---

## Product boundaries

| Surface | Status | Notes |
|---------|--------|-------|
| Swift embedded engine (`BlazeDBCore` / product `BlazeDB`) | **Supported** | Encrypted local store; default OSS product |
| Public Swift APIs (`BlazeDBClient`, `BlazeDB.open`, typed `put`/`get`/`query`) | **Supported** | Prefer `open` over deprecated convenience inits |
| CLI `blazedb` + tools (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`) | **Supported** | Doctor/Dump/Info are **separate executables**, not `blazedb` subcommands today |
| Dynamic `BlazeDBC` C ABI (byte KV) | **Supported** | Header + `@_cdecl` exports; see [C_ABI_BYTE_KV](C_ABI_BYTE_KV.md) |
| Examples / benchmarks | **Supported as samples** | Not the product contract |
| Distributed sync / server / discovery / telemetry packaging | **Deferred** | Excluded from `BlazeDBCore` in `Package.swift` |
| `BlazeDBSyncStaging` / `BlazeDBTelemetryStaging` | **Staging only** | Not default product |
| Android bridge / KMM | **Experimental / deferred** | Compile/cross paths ≠ Tier1 runtime product |
| `BlazeDB/Indexing/ExperimentalBPlusTree.swift` | **Experimental stub** | Print-only; **not** production query path |
| SQLite/CoreData migrators under `BlazeDB/Migration/` | **Excluded from core package** | Source may exist; not shipped in `BlazeDBCore` |

---

## Package target map

| Target | Purpose | Public or internal | Important dependencies | Tests | Support state |
|--------|---------|--------------------|------------------------|-------|---------------|
| `BlazeDBCore` | Implementation module (path `BlazeDB/`, excludes distributed) | Internal module / advanced product | `swift-crypto` on Linux/Android | `BlazeDB_Tier0`… | **Supported** |
| `BlazeDB` | Umbrella re-export (`BlazeDBShim`) | **Public product** | `BlazeDBCore` | via consumers / SwiftUI tests | **Supported** |
| `BlazeCLICore` | Shared CLI/REPL/dev helpers (`BlazeShell/`) | Internal | `BlazeDBCore` | `BlazeDB_CLITests` | **Supported** |
| `BlazedbCLI` | `blazedb` executable | Public executable product | `BlazeDBCore`, `BlazeCLICore` | CLI smoke + CLITests | **Supported** |
| `BlazeDoctor` / `BlazeDump` / `BlazeInfo` | Operator tools | Build via `swift run` (not SPM products) | `BlazeDBCore` | Docs + manual | **Supported tools** |
| `BlazeDBC` | C ABI dynamic/static products | **Public ABI** | `BlazeDBCore` | `BlazeDBCSmokeTests` (Tier1) | **Supported** |
| `BlazeDBBenchmarks` | Throughput / open_profile / write_profile | Local tool | `BlazeDBCore` | `WriteProfileCollectorTests` | Tooling |
| `HelloBlazeDB`, `ReadmeSamples`, `BasicExample`, `CorePathSmoke`, `MVVMPattern`, `ReferenceConsumer` | Examples | Samples | `BlazeDB` / `BlazeDBCore` | Manual | Samples |
| `BlazeDBAndroidBridge` (+ KMM products) | Android JNI/KMM bridge | Experimental products | `BlazeDBCore` | Cross-compile scripts | **Experimental** |
| `BlazeDBSyncStaging` / `BlazeDBTelemetryStaging` | Staging modules | Internal staging | none | `BlazeDB_Staging` | **Not default product** |
| `BlazeDB_Tier0` | Gate durability/correctness | Tests | `BlazeDBCore` | path `BlazeDBTests/Tier0Core` | CI gate |
| `BlazeDB_Tier1` | PR/local correctness | Tests | `BlazeDBCore`, `BlazeDBC` | `BlazeDBTests/Tier1Core` | CI gate |
| `BlazeDB_CLITests` | CLI core unit tests | Tests | `BlazeCLICore` | `BlazeDBCLITests` | CI |
| `BlazeDB_Tier2` / `_Extended` / `Tier3_*` / `SwiftUITests` | Deeper suites | Tests | core / BlazeDB | various | Heavier lanes |

When `BLAZEDB_TEST_SCOPE=tier0`, only Tier0 (+ CLITests + Staging) targets are registered.

---

## Directory map (curated)

| Path | Responsibility | Important types/functions | Related tests | Related issues |
|------|----------------|---------------------------|---------------|----------------|
| `BlazeDB/Exports/` | Public client + facade | `BlazeDBClient`, `BlazeDB.open`, `put`→`upsert`, RLS wrappers, txn APIs | `BlazeDBTests/Tier1Core/API/`, `…/Security/RLS*`, `…/Transactions/` | #173–#174, #276–#280, #286–#288 |
| `BlazeDB/Core/` | Collection, batch, MVCC hooks | `DynamicCollection`, `insert`/`fetchAll`, `+Batch` | Tier0 durability; Tier1 Persistence/Core | #278, #280–#282, #284 |
| `BlazeDB/Storage/` | Pages, WAL, layout, recovery | `PageStore`, `WriteAheadLog`, `StorageLayout`, `VacuumRecovery` | `BlazeDBTests/Tier0Core/Durability/` | #276–#277, #281, #283, #293 |
| `BlazeDB/Crypto/` | KDF / keys / sessions | `KeyManager`, `DatabaseSessionStore` | `BlazeDBTests/Tier1Core/Security/Key*` | #270–#273 |
| `BlazeDB/Query/` | Query builder / explain / cache | `QueryBuilder._executeStandard`, `QueryExplain`, `QueryCache` | `BlazeDBTests/Tier1Core/Query/`, Tier0 planner contract | #261, #274, #279, #292 |
| `BlazeDB/Diagnostics/` | Opt-in profilers | `WriteProfileCollector`, `OpenProfileCollector` | `BlazeDBTests/Tier0Core/Diagnostics/` | #291 |
| `BlazeDB/Security/` | RLS policy engine | `PolicyEngine`, policies | Tier1 `Security/RLS*` | #286, #288 |
| `BlazeDB/Indexing/` | Experimental B+ stub | `BPlusTreeNode` | Tier0 `Indexes/BPlusTreeNodeTest.swift` | experimental only |
| `BlazeDBC/` | C ABI | `blazedb.h`, `BlazeDBC.swift` | `BlazeDBCSmokeTests` | #264–#267 |
| `BlazedbCLI/` + `BlazeShell/` | CLI entry + `dev` | `BlazedbEntry`, `DeveloperCommands` | `BlazeDBCLITests` | #258–#259, #289–#290 |
| `BlazeDoctor/` `BlazeDump/` `BlazeInfo/` | Operator binaries | `main.swift` each | manual / docs | #259, #290 |
| `BlazeDBBenchmarks/` | Bench harness | `WriteProfiler`, modes | write-profile docs | #270–#271, #291 |
| `Examples/` | Samples | `HelloBlazeDB`, `C/hello_blazedb.c` | smoke | #265 |
| `BlazeDBTests/Tier0Core/` | Gate tests | Durability, diagnostics, gate | `./dev tier0` | correctness |
| `BlazeDBTests/Tier1Core/` | Broad correctness | API, query, security, persistence | `./dev test …` | most feature work |

---

## Core execution paths

### Open database

```
BlazeDB.open / BlazeDBClient.open
  → resolve path (PathResolver / EasyOpen)
  → loadOrCreateKDFSalt (.salt) + KeyManager.getKey (PBKDF2; session warm path)
  → restoreDurableTransactionBackupIfPresent (txn_in_progress-*)
  → VacuumRecovery.recoverFromVacuumCrashIfNeeded
  → PageStore.init → WAL replay (_replayLegacyWAL / unified)
  → DynamicCollection.init → StorageLayout.loadSecure
  → migrations / post-open cleanup
  → public BlazeDBClient handle
```

Primary files: `Exports/PublicFacadeAPI.swift`, `Exports/BlazeDBClient+EasyOpen.swift`, `Exports/BlazeDBClient.swift`, `Crypto/KeyManager.swift`, `Storage/PageStore.swift`, `Storage/WriteAheadLog.swift`, `Core/DynamicCollection.swift`, `Storage/StorageLayout+Security.swift`.

### Single durable write

```
public insert / put
  → BlazeDBClient.performSafeWrite
  → DynamicCollection.insert (encode)
  → PageStore write (WAL appendDeferred on page image)
  → PageStore.synchronize (wal.sync + data fsync)
  → layout/metadata publish (saveSecure / saveLayout)
  → clearFetchAllCache / QueryCache.notifyWrite
  → return
```

`insertBatch` / `insertMany` batch page writes then **one** `synchronize` (`DynamicCollection+Batch.swift`).  
Instrumentation: `Diagnostics/WriteProfileCollector.swift` when `BLAZEDB_WRITE_PROFILE=1`.

### Client transaction

```
beginTransaction
  → persist + synchronize + checkpoint
  → createDurableTransactionBackups + state "open"
  → snapshot indexMap / secondary indexes / records
mutations
  → performSafeWrite skips per-write indexMap backup only
  → inserts remain write-through (page/WAL sync per insert)  ← current behavior (#276)
commitTransaction
  → state "committing" → persist + synchronize + checkpoint → clear backups
rollbackTransaction
  → restore snapshots / layout; clear caches
crash with txn artifacts
  → restoreDurableTransactionBackupIfPresent on next open (#277 risk window)
```

### Query

```
db.query()…execute()
  → QueryBuilder.execute → _executeStandard
  → QueryBuilder.standardQueryExecutor (LegacyQueryExecutor)
  → collection.fetchAll()          ← public path is scan-based today
  → in-memory filters / sort / offset / limit
  → QueryResult
```

Seam map: [CHANGE_MAP.md](CHANGE_MAP.md). Indexes may be **maintained** (`createIndex`) but are **not** used by default standard path (`QueryExecuting.swift` / `QueryBuilder.swift`). Explain stubs: `Query/QueryExplain.swift`. Docs honesty: #261, #274, #292.

### Recovery

```
open
  → interrupted txn backup restore (client artifacts)
  → vacuum crash recovery
  → PageStore WAL replay
  → load layout / rebuild if needed
  → ready handle
```

Tests: `Tier0Core/Durability/TransactionDurabilityTests.swift` (`testStartupRestoresInterruptedTransactionBackup`, `testCrashRecovery_*`), `PageStoreUnifiedWALTests`, `Tier1Core/Persistence/CrashRecoveryTests.swift`.

### BlazeDBC call

```
C caller
  → blazedb.h (blazedb_open/put/get/delete/close/free)
  → @_cdecl in BlazeDBC/BlazeDBC.swift
  → OpaquePointer → BlazeDBCBox → BlazeDBClient / byte-KV path
  → BlazeDBResult + blazedb_free ownership
```

Tests: `Tier1Core/API/BlazeDBCSmokeTests.swift` (`testOpenPutGetFreeDeleteClose`). Example: `Examples/C/hello_blazedb.c`.

---

## Safe vs maintainer-review

| Safer | Maintainer review required |
|-------|----------------------------|
| Docs truth, CLI help/version/JSON formatting | WAL/commit ordering, backup restore, encryption/KDF |
| Examples, smoke tests, issue-guide polish | C ABI symbols/layout/ownership |
| Dead-field cleanup with tests | RLS enforcement semantics, concurrency barriers |
| Benchmark attribution / matrix (#291) | Storage format, page layout |

---

## Focused validation

```bash
./dev help
./dev tests [search]
./dev test <FilterOrMethod>
arch -arm64 ./dev tier0          # Apple Silicon if arch mismatch (#289)
swift run HelloBlazeDB
BLAZEDB_BENCH_MODE=write_profile swift run -c release BlazeDBBenchmarks
```
