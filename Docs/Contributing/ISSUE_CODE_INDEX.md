# Issue → code / test index

Maps **current open issues** (as of tip `0b43a08c` + tracker state after gardening) to verified files and tests.  
**No new issues** are created by this document.

Difficulty: `starter` | `intermediate` | `advanced` | `maintainer-sensitive`  
Evidence: `Proven` | `Strongly supported` | `Investigation`

Hub: [LEARNING_PATHS](LEARNING_PATHS.md) · [CODEBASE_MAP](../Architecture/CODEBASE_MAP.md) · [ISSUE_GUIDE](ISSUE_GUIDE.md)

Label filters used: `good first issue`, `durability`, `performance`, `concurrency`, `needs design`, plus roadmap-sized Now items and correctness defects. There is **no** `roadmap` GitHub label today — roadmap Now work is listed explicitly. **`help wanted`:** none currently open with that label. Prefer specific risk labels over a generic priority tag.

---

## Good first issue

| Issue | Difficulty | Evidence | Suspected/confirmed files | Existing tests | Missing tests | Validation command | Maintainer review |
|-------|------------|----------|---------------------------|----------------|---------------|--------------------|-------------------|
| #173 | starter | Proven | `Docs/Guides/CONVENIENCE_API_GUIDE.md`; `BlazeDB/Exports/BlazeDBClient+Convenience.swift` (deprecated); `BlazeDB/Exports/PublicFacadeAPI.swift` | none required (docs) | n/a | `rg -n "BlazeDBClient\\(name:" Docs/Guides/CONVENIENCE_API_GUIDE.md` | no |
| #174 | starter | Proven | `BlazeDB/Exports/PublicFacadeAPI.swift` `put`→`upsert`; `README.md` | none (docs) | n/a | `rg -n "func put" BlazeDB/Exports/PublicFacadeAPI.swift` | no |
| #258 | starter | Proven | `BlazedbCLI/BlazedbEntry.swift`; `RELEASE.md` / version source of truth | CLI smoke / CLITests (extend) | `--version` assertion | `swift run blazedb --version` (after fix) | low |
| #259 | starter | Proven | `Docs/Guides/CLI_REFERENCE.md`; `BlazeDoctor/main.swift` vs `BlazedbEntry` | none | n/a | `rg -n "doctor" BlazedbCLI/BlazedbEntry.swift Docs/Guides/CLI_REFERENCE.md` | no |
| #261 | starter | Proven | query performance docs (see issue); related `QueryBuilder._executeStandard` | planner contract tests | n/a | `rg -n "O\\(log" Docs/` | no |
| #262 | starter | Proven | Homebrew / install docs (issue body) | n/a | n/a | docs only | no |
| #272 | starter | Proven | **`Docs/Benchmarks/LATENCY.md`** (not `Docs/Performance/`) | n/a | n/a | open/edit that file; compare to current bench | no |
| #273 | starter | Proven | `SECURITY.md`; `KeyManager` PBKDF2 iterations | `KeyManagerTests` | n/a | `rg -n "PBKDF2|600|10000|Argon2" SECURITY.md BlazeDB/Crypto/KeyManager.swift` | no (docs) |
| #286 | starter | Proven | migration/API docs vs `BlazeDBClient` RLS | `RLSEnforcementClientTests` | n/a | `./dev test RLSEnforcementClientTests` (behavior unchanged) | no |
| #287 | starter | Proven | `MIGRATION_GUIDE` vs `Package.swift` excludes | n/a | n/a | `rg -n "SQLiteMigrator|CoreDataMigrator" Package.swift` | no |
| #288 | starter | Proven | `BlazeDB/Exports/BlazeDBClient+RLS.swift` (`enableRLS`); `BlazeDB/Exports/BlazeDBClient.swift` (`shouldEnforceRLS`) | `testRLSEnabledWithoutPoliciesDoesNotBlock` | n/a | `./dev test RLSEnforcementClientTests.testRLSEnabledWithoutPoliciesDoesNotBlock` | **docs only** — no auth changes |
| #289 | starter | Strongly supported | `dev`; `BlazeShell/DeveloperCommands.swift` | `DeveloperCommandsTests` | arch mismatch case | `./dev help` | low |
| #290 | starter | Strongly supported | `BlazeDump/main.swift`, `BlazeInfo/main.swift` | none focused | JSON golden | `swift run BlazeInfo …` | low |
| #292 | starter | Proven | `Docs/Features/QUERY_PLANNER.md` | n/a | n/a | `rg -n "O\\(log" Docs/Features/QUERY_PLANNER.md` | no |
| #293 | starter | Proven | `Docs/Status/DURABILITY_MODE_SUPPORT.md`; `WriteAheadLog.appendDeferred` | n/a | n/a | `rg -n "appendDeferred|fsync" …` | no |
| #294 | starter | Proven | `Docs/Guarantees/SAFETY_MODEL.md`; txn write-through | #276 evidence | n/a | `rg -n "buffered" Docs/Guarantees/SAFETY_MODEL.md` | no |

---

## Durability

| Issue | Difficulty | Evidence | Files | Existing tests | Missing tests | Validation | Maintainer review |
|-------|------------|----------|-------|----------------|---------------|------------|-------------------|
| #276 | advanced | Proven | `BlazeDBClient.performSafeWrite`, `beginTransaction`; `DynamicCollection.insert`; `PageStore.synchronize`; `WriteAheadLog` | `WriteProfileCollectorTests`; `TransactionDurabilityTests` | commit-boundary fsync count after amortize | write_profile bench + durability tests | **yes**; optimize blocked on #291 |
| #277 | maintainer-sensitive | Proven | `createDurableTransactionBackups`, `commitTransaction`, `restoreDurableTransactionBackupIfPresent` | `testStartupRestoresInterruptedTransactionBackup`; crash survival suites | crash **after** commit persist / **before** backup clear | Tier0 durability + new regression | **yes** |
| #281 | advanced | Proven | `DynamicCollection+Batch.insertBatch` (secondary indexes vs `synchronize`) | batch/persistence suites (partial) | sync-failure index desync | focused batch + fault injection | **yes** |
| #283 | advanced | Proven | `BlazeDB/Storage/PageStore+Overflow.swift` overflow write helpers (`_writeOverflowPage` / Linux queue.sync vs `.barrier` — confirm on current Linux path) | overflow / persistence tests | Linux-specific race | Linux + barrier review | **yes** |

---

## Performance / investigation

| Issue | Difficulty | Evidence | Files | Existing tests | Missing tests | Validation | Maintainer review |
|-------|------------|----------|-------|----------------|---------------|------------|-------------------|
| #270 | advanced | Strongly supported | `KeyManager`, open path, open_profile | Key/open tests | platform PBKDF2 parity bench | `BLAZEDB_BENCH_MODE=open_profile` | **yes** (crypto) |
| #271 | intermediate | Proven | `BlazeDBBenchmarks` / `OpenProfiler` attribution | none for mis-attribution | engine_only without KDF | open_profile modes | low–med |
| #275 | intermediate | Strongly supported | LiveQuery / SwiftUI observers (`BlazeDB/SwiftUI/`, live query types) | Tier1 Query live-query tests | coalesce under write load | focused live-query tests | med |
| #284 | intermediate | Proven | `updateBatch` vs `insertBatch` sync deferral | batch tests | updateBatch fsync count | write_profile / batch tests | med |
| #291 | intermediate | Investigation | `WriteProfiler`, `WriteProfileCollector`, WRITE_PATH_PROFILE.md | `WriteProfileCollectorTests` | matrix N + external fsync | write_profile + `fs_usage`/`strace` | low (instrumentation) |

---

## Roadmap-sized Now (no `roadmap` label)

| Issue | Difficulty | Evidence | Files | Existing tests | Missing tests | Validation | Maintainer review |
|-------|------------|----------|-------|----------------|---------------|------------|-------------------|
| #263 | intermediate | Strongly supported | Compatibility fixtures + CI workflows | fixtures may skip today | non-skippable gate | CI workflow change | med |
| #264 | intermediate | Proven | `Examples/Go/README.md` (no `.go` yet); `BlazeDBC` | `BlazeDBCSmokeTests` | Go/cgo CI | build BlazeDBC + planned go test | med |
| #265 | intermediate | Strongly supported | `Examples/C/hello_blazedb.c`; release scripts | C example not always CI-linked | artifact + CI link | `swift build --product BlazeDBC` | med |
| #266 | starter–intermediate | Strongly supported | schema docs under consolidation | `SchemaValidationTests` | n/a (docs) | schema guide + tests unchanged | low |
| #267 | intermediate | Proven | `blazedb.h`, `BlazeDBC.swift` | smoke tests | last_error coverage | `BlazeDBCSmokeTests` + new | **ABI review** |

---

## High-risk correctness (not GFI; mapped for Path D/C)

| Issue | Difficulty | Evidence | Files | Existing tests | Missing tests | Validation | Maintainer review |
|-------|------------|----------|-------|----------------|---------------|------------|-------------------|
| #278 | maintainer-sensitive | Proven | `BlazeDBClient.updateMany` / `deleteMany(where:)` iterate `collection.indexMap.keys` while mutating | concurrency suites (partial) | mutation-during-iteration crash | focused batch mutation test | **yes** |
| #279 | maintainer-sensitive | Proven | `DynamicCollection.runQuery*` nested `queue.sync` + `fetchAll` | `testPerformSafeWrite_NestedReentrancyDoesNotDeadlock` (related, not same) | runQuery+fetchAll deadlock | hang-detecting test | **yes** |
| #280 | advanced | Proven | `DynamicCollection+Optimized` fetchAll cache; MVCC update paths | optimized/cache tests (partial) | stale hit after MVCC update | cache invalidation test | **yes** |
| #282 | intermediate | Proven | typed bulk decode `compactMap try?` (typed-store paths) | TypedStore tests | decode failure surfacing | typed bulk tests | med |

---

## Unmapped / weakly grounded

| Issue | Reason |
|-------|--------|
| #30 | Broad alignment audit; residual sites need fresh Linux repro — map after locating remaining `load(fromByteOffset:)` call sites |
| #43 | Compression portability enhancement; backend choice needs design — files span `PageStore` compression paths; treat as design-first |
| #51 | Linux Tier1 CI contract — workflow/docs heavy; exact failing suites change over time |
| #73 | Move `SecureConnectionTests` — file excluded from Tier1; target destination is distributed/transport (deferred product) |
| #268 | `stats()`/`profile` cacheHit fields — need exact dead property sites confirmed in current Metrics types before coding |
| #285 | `transactionPagesWritten` dead metric — confirm all write sites still empty before remove-vs-fix |

If you ground one of these, update this table in the same PR as the investigation notes.

---

## Quick chooser

| Background | Start path | First issues |
|------------|------------|--------------|
| Docs / Swift beginner | Path A | #173, #174, #294 |
| CLI | Path B | #258, #290 |
| C / Go | Path E | #264, #265, #267 |
| Concurrency | Tour 03 + 04 | #279, #278 (advanced) |
| Performance | Path F | #291 then #276 |
| Durability | Path D | #277 first among P0s |
