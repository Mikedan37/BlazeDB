# BlazeDB Repository Metrics

> **Generated file.** Do not edit by hand.
> Regenerate with `./Scripts/repo-metrics.sh`.
> Machine-readable source of truth: `.metrics/repository-metrics.json`.
> Inventory source: `git ls-files` only (no `.build`, DerivedData, or untracked paths).

| Field | Value |
|-------|-------|
| Generated at (UTC) | `2026-07-27T21:36:54Z` |
| Commit | `f9b05b2987ea023a365ed0701774f017b4ab3694` |
| Commit date | `2026-07-27T14:20:38-07:00` |

## 1. Bucket definitions

- **text_files**: Tracked paths that exist on disk and are not binary (extension denylist + NUL check)
- **source**: Text files outside test trees, Docs/, *.md, Examples/, Scripts/, and noise prefixes
- **tests**: Text files under Tests/, BlazeDBTests/, BlazeDBIntegrationTests/, BlazeDBCLITests/, BlazeDBVisualizerTests/, BlazeDBExtraTests/, BlazeDBTests_SPM/
- **docs_bucket**: All files under Docs/ plus every tracked *.md/*.markdown anywhere (explains Docs > Markdown)
- **markdown**: Every tracked *.md / *.markdown regardless of directory
- **archive**: Files under Docs/Archive/
- **noise**: .build/, DerivedData/, Vendor/, vendor/, Carthage/, node_modules/
- **curated_subsystems** (curated — maintained classification, not filesystem-derived): engine core, storage/WAL, query, crypto, transactions, C ABI, CLI. Used for human-facing scale narrative only; not counted by scanning directories

### Why Docs lines can exceed Markdown lines

Docs bucket = all files under Docs/ (any extension) plus every tracked *.md anywhere. Markdown count is *.md only. Non-Markdown under Docs/ (txt, json, scripts, exports) and double-counting rules explain the gap.

## 2. Repository size

| Metric | Files | Lines | Precision |
|--------|------:|------:|-----------|
| Tracked paths | 1858 | — | exact |
| Tracked text | 1848 | 548082 | exact |
| Swift | 1119 | 333090 | exact |
| Markdown | 546 | 167482 | exact |
| Source bucket | 459 | 100928 | exact |
| Tests bucket | 681 | 229325 | exact |
| Docs bucket | 568 | 199654 | exact |
| `BlazeDB/` engine tree | 282 | 66441 | exact |
| `Tests/` prefix only | 241 | 86498 | exact |
| `Docs/` prefix only | 529 | 195860 | exact |
| `Docs/Archive/` | 143 | 64509 | exact |

**Test-to-source line ratio:** 2.27  
**SwiftPM products / targets:** 7 / 28 (exact package manifest counts; products ≠ curated subsystems)

### Swift declarations (approximate)

| Declaration | Count |
|-------------|------:|
| class | 894 |
| struct | 605 |
| protocol | 17 |
| enum | 221 |

## 3. Test execution and discovery

| Metric | Value | Precision |
|--------|------:|-----------|
| Test-tree Swift files | 668 | exact |
| XCTest `func test…` declarations | 7165 | approximate |
| Swift Testing `@Test` declarations | 1 | approximate |
| Files with ≥1 test declaration | 643 | approximate |
| Helper/fixture Swift without test decl | 25 | approximate |
| XCTSkip occurrences | 33 | approximate |
| Files with `#if os(` | 28 | approximate |
| Wired SPM test Swift files | 247 | exact path membership |
| Orphan on-disk test Swift (not in Package test paths) | 421 | exact |
| Runner-discovered tests (`swift test list`) | 284 | approximate (ok) |

_Runner note:_ swift test list --skip-build; may undercount if package was last evaluated with BLAZEDB_TEST_SCOPE=tier0 or stale build graph

**Important:** `func test…` counts are **not** executed-test counts. Skips, filters, parameterization, and platform conditionals change what CI runs.

## 4. Test review candidates

Candidates only — **not** obsolete. Compatibility and regression tests may remain valuable indefinitely.

| Path | Kind | Confidence | Evidence |
|------|------|------------|----------|
| `BlazeDBTests/SwiftUI` | orphan_test_target | high | Package.swift test target BlazeDB_SwiftUITests has empty lane list in static CI mapping |
| `BlazeDBTests/Staging` | orphan_test_target | high | Package.swift test target BlazeDB_Staging has empty lane list in static CI mapping |
| `BlazeDBIntegrationTests/ChaosEngineeringTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBIntegrationTests/ChaosEngineeringTests.swift, BlazeDBTests/Tier2Integration/BlazeDBI |
| `BlazeDBTests/Core/ImportExportTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Core/ImportExportTests.swift, BlazeDBTests/Gate/ImportExportTests.swift |
| `BlazeDBTests/Core/LifecycleTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Core/LifecycleTests.swift, BlazeDBTests/Gate/LifecycleTests.swift |
| `BlazeDBTests/Core/OperationalConfidenceTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Core/OperationalConfidenceTests.swift, BlazeDBTests/Gate/OperationalConfidence |
| `BlazeDBTests/Core/SchemaMigrationTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Core/SchemaMigrationTests.swift, BlazeDBTests/Gate/SchemaMigrationTests.swift |
| `BlazeDBTests/Gate/CLISmokeTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Gate/CLISmokeTests.swift, BlazeDBTests/Integration/CLISmokeTests.swift |
| `BlazeDBTests/Helpers/TestCleanupHelpers.swift` | duplicate_test_file | high | SHA256-identical to 3 paths: BlazeDBTests/Helpers/TestCleanupHelpers.swift, BlazeDBTests/Tier3Destructive/Helpers/TestCl |
| `BlazeDBTests/Legacy/PageStoreTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Legacy/PageStoreTests.swift, BlazeDBTests/Tier3Heavy/Legacy/PageStoreTests.swi |
| `BlazeDBTests/Tier1Core/Helpers/TypeSafetyTestBug.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBTests/Tier1Core/Helpers/TypeSafetyTestBug.swift, BlazeDBTests/Tier2Integration/Blaze |
| `BlazeDBTests/Tier1Core/Helpers/XCTestCase+FixtureRequire.swift` | duplicate_test_file | high | SHA256-identical to 3 paths: BlazeDBTests/Tier1Core/Helpers/XCTestCase+FixtureRequire.swift, BlazeDBTests/Tier2Integrati |
| `BlazeDBVisualizerTests/AdvancedFeaturesIntegrationTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/AdvancedFeaturesIntegrationTests.swift, Tests/BlazeDBVisualizerTests |
| `BlazeDBVisualizerTests/FullTextSearchTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/FullTextSearchTests.swift, Tests/BlazeDBVisualizerTests/FullTextSear |
| `BlazeDBVisualizerTests/PermissionTesterTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/PermissionTesterTests.swift, Tests/BlazeDBVisualizerTests/Permission |
| `BlazeDBVisualizerTests/QueryPerformanceTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/QueryPerformanceTests.swift, Tests/BlazeDBVisualizerTests/QueryPerfo |
| `BlazeDBVisualizerTests/RelationshipVisualizerTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/RelationshipVisualizerTests.swift, Tests/BlazeDBVisualizerTests/Rela |
| `BlazeDBVisualizerTests/TelemetryDashboardTests.swift` | duplicate_test_file | high | SHA256-identical to 2 paths: BlazeDBVisualizerTests/TelemetryDashboardTests.swift, Tests/BlazeDBVisualizerTests/Telemetr |
| `BlazeDBCLITests/BlazeCLICoreTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/CoreCorrectness/CoreCorrectnessTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/CoreCorrectness/PathResolverDefaultLocationTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/Durability/BlazeDBRecoveryTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/Durability/PageStoreUnifiedWALTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/Durability/TransactionDurabilityTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier0Core/Gate/CLISmokeTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Core/API/TriggerPersistenceAPITests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Core/Integration/CLISmokeTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Core/Integration/ConvenienceAPITests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Extended/Concurrency/BatchOperationTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Extended/Indexes/FullTextSearchTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Extended/Indexes/OptimizedSearchTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier1Perf/Indexes/SearchPerformanceBenchmarks.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |
| `BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests/CrossVersionExportRestoreHarnessTests.swift` | contains_XCTSkip | medium | File contains XCTSkip / throw XCTSkip |

## 5. Documentation activity and reachability

| Metric | Value | Precision |
|--------|------:|-----------|
| Tracked Markdown files | 546 | exact |
| Inventory used | True | — |
| KEEP_CANONICAL | 69 | inventory |
| KEEP_REFERENCE | 188 | inventory |
| ARCHIVE (recommendation) | 251 | inventory |
| MERGE | 31 | inventory |
| DELETE_CANDIDATE | 6 | inventory |
| REVIEW_REQUIRED | 2 | inventory |
| Docs/Archive Markdown files | 141 | exact |
| Reachable from primary entry points | 100 | exact BFS |
| Reachable active docs | 92 | mixed |
| Unreachable active docs | 165 | mixed |
| Broken local file links | 41 | exact |
| Broken anchors | 62 | approximate |
| Code fence blocks (non-archive) | 4802 | approximate |

_Documentation examples:_ Executable README samples verified via Examples/ReadmeSamples + Scripts/verify-readme-samples.sh; not a full fence audit of Docs/

## 6. Documentation review candidates

| Path | Kind | Confidence | Evidence |
|------|------|------------|----------|
| `.github/ISSUE_TEMPLATE/bug_report.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `.github/ISSUE_TEMPLATE/feature_request.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `.github/ISSUE_TEMPLATE/security_review_tracking.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `.github/REPOSITORY_AUTOMATION.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `.github/pull_request_template.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `.github/workflows/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `BlazeDB/BlazeDB.docc/BlazeDB.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `BlazeDB/Distributed/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `BlazeDBC/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `BlazeDBExtraTests/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `BlazeDBVisualizer/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/API/GRAPH_QUERY_API.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/API/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/ARCHIVE_INDEX.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/ARCHITECTURE.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/BLAZEBINARY_PROTOCOL.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/BLAZEDB_RELAY.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/DISTRIBUTED_ARCHITECTURE.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/EXTENSION_POINTS.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/SERVER_CLIENT_ARCHITECTURE.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/STORAGE_ENGINE_NOTES.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Architecture/TOURS/README.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Benchmarks/CONCURRENT_MVCC.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Benchmarks/ENERGY.md` | unreachable_active_doc | medium | Classified active (or non-archive) but not reachable from primary entry-point BFS |
| `Docs/Meta/REORGANIZATION_COMPLETE 2.md` | inventory_delete_candidate | medium | Filename has space+"2"; longer sibling of REORGANIZATION_COMPLETE.md — pick one canonical Meta copy then delete other |
| `Tests/BlazeDBTests/CREATE_TEST_PLANS_IN_XCODE.md` | inventory_delete_candidate | medium | SHA256-identical to Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md |
| `Tests/BlazeDBTests/FINAL_REORGANIZATION_INSTRUCTIONS.md` | inventory_delete_candidate | medium | Near-duplicate of Docs/Tests copy; completed instructions |
| `Tests/BlazeDBTests/REORGANIZATION_PLAN.md` | inventory_delete_candidate | medium | Near-duplicate of Docs/Tests copy (67 lines; byte diff trivial); completed reorg plan |
| `Tests/BlazeDBTests/REORGANIZATION_STATUS.md` | inventory_delete_candidate | medium | SHA256-identical to Docs/Tests/REORGANIZATION_STATUS.md; zero unique content |
| `Tests/BlazeDBTests/TEST_PLAN.md` | inventory_delete_candidate | medium | Near-duplicate of Docs/Testing/TEST_PLAN.md (499 lines; trivial byte diff) |
| `Docs/Meta/COMPLETE_REORGANIZATION.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/COMPLETE_REORGANIZATION.md, Docs/Tests/COMPLETE_REORGANIZATION.md |
| `Docs/Meta/FINAL_MIGRATION_INSTRUCTIONS.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/FINAL_MIGRATION_INSTRUCTIONS.md, Docs/Tests/FINAL_MIGRATION_INSTRUCTIONS.md |
| `Docs/Meta/FINAL_MOVES_COMPLETE.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/FINAL_MOVES_COMPLETE.md, Docs/Tests/FINAL_MOVES_COMPLETE.md |
| `Docs/Meta/FINAL_REORGANIZATION_INSTRUCTIONS.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/FINAL_REORGANIZATION_INSTRUCTIONS.md, Docs/Tests/FINAL_REORGANIZATION_INSTRUCTIONS.md |
| `Docs/Meta/MIGRATION_SCRIPT.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/MIGRATION_SCRIPT.md, Docs/Tests/MIGRATION_SCRIPT.md |
| `Docs/Meta/REORGANIZATION_COMPLETE.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/REORGANIZATION_COMPLETE.md, Docs/Tests/REORGANIZATION_COMPLETE.md |
| `Docs/Meta/REORGANIZATION_PLAN.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/REORGANIZATION_PLAN.md, Docs/Tests/REORGANIZATION_PLAN.md |
| `Docs/Meta/REORGANIZATION_STATUS.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/REORGANIZATION_STATUS.md, Docs/Tests/REORGANIZATION_STATUS.md |
| `Docs/Meta/REORGANIZATION_SUMMARY.md` | duplicate_markdown | high | Byte-identical group: Docs/Meta/REORGANIZATION_SUMMARY.md, Docs/Tests/REORGANIZATION_SUMMARY.md |

## 7. CI lane coverage

| Target | Path | Lanes | In normal lane? |
|--------|------|-------|-----------------|
| `BlazeDB_Tier0` | `BlazeDBTests/Tier0Core` | pr_macos, pr_linux, nightly_macos_tsan, release_macos | yes |
| `BlazeDB_CLITests` | `BlazeDBCLITests` | pr_macos, pr_linux, release_macos | yes |
| `BlazeDB_Tier1` | `BlazeDBTests/Tier1Core` | pr_macos, nightly_linux, release_macos | yes |
| `BlazeDB_SwiftUITests` | `BlazeDBTests/SwiftUI` | _(none)_ | **no** |
| `BlazeDB_Tier2` | `BlazeDBTests/Tier2Integration/BlazeDBIntegrationTests` | nightly_macos, nightly_linux, release_macos | yes |
| `BlazeDB_Tier2_Extended` | `BlazeDBTests/Tier1Extended` | weekly_linux, release_macos | yes |
| `BlazeDB_Tier3_Heavy` | `BlazeDBTests/Tier3Heavy` | weekly_macos, weekly_linux, release_macos | yes |
| `BlazeDB_Tier3_Heavy_Perf` | `BlazeDBTests/Tier1Perf` | weekly_macos, weekly_linux, release_macos | yes |
| `BlazeDB_Tier3_Destructive` | `BlazeDBTests/Tier3Destructive` | weekly_macos | yes |
| `BlazeDB_Staging` | `BlazeDBTests/Staging` | _(none)_ | **no** |

- macOS: PR Tier0+Tier1; nightly Tier2; weekly Tier3/Heavy/Perf/Destructive
- Linux: PR Tier0+CLITests; nightly Tier1+Tier2; weekly Extended+Heavy(+Perf)
- Android: PR gate: cross-compile + KMM emulator smoke — no SPM XCTest tier execution

## 8. Changes since previous snapshot

No previous committed snapshot

## 9. Methodology limitations

- Named XCTest methods ≠ executed cases (parameterization, skips, filters).
- swift test list may undercount when BLAZEDB_TEST_SCOPE=tier0 or .build is cold/stale.
- Documentation inventory classifications are used when the inventory file is present; they are human/agent judgments, not proofs of obsolescence.
- Old regression/compatibility tests are never auto-labeled obsolete.
- Curated subsystem list is architectural narrative, not a derived metric.
- Unreferenced-fixture detection is basename heuristic only.

## Files by extension

| Extension | Files | Lines |
|-----------|------:|------:|
| `swift` | 1119 | 333090 |
| `md` | 546 | 167482 |
| `sh` | 61 | 4474 |
| `py` | 19 | 4390 |
| `json` | 17 | 1870 |
| `kt` | 14 | 549 |
| `yml` | 11 | 1804 |
| `xctestplan` | 9 | 425 |
| `(none)` | 7 | 325 |
| `txt` | 6 | 29670 |
| `kts` | 4 | 317 |
| `xcscheme` | 4 | 434 |
| `pbxproj` | 3 | 1625 |
| `resolved` | 3 | 90 |
| `svg` | 3 | 384 |
| `xcworkspacedata` | 3 | 21 |
| `blazedump` | 2 | 2 |
| `c` | 2 | 333 |
| `entitlements` | 2 | 50 |
| `h` | 2 | 143 |
| `properties` | 2 | 10 |
| `bat` | 1 | 92 |
| `def` | 1 | 7 |
| `gitignore` | 1 | 61 |
| `html` | 1 | 272 |
| `mdc` | 1 | 23 |
| `podspec` | 1 | 22 |
| `rb` | 1 | 19 |
| `xml` | 1 | 17 |
| `zsh` | 1 | 81 |

## Top 20 directories by file count

| Directory | Files | Lines |
|-----------|------:|------:|
| `Tests/BlazeDBTests` | 200 | 72452 |
| `Docs/Archive` | 143 | 64509 |
| `BlazeDBTests/Tier1Core` | 93 | 21276 |
| `BlazeDB/Core` | 57 | 14218 |
| `BlazeDB/Exports` | 46 | 10507 |
| `BlazeDBVisualizer/BlazeDBVisualizer` | 45 | 13371 |
| `BlazeDB/Query` | 42 | 10247 |
| `BlazeDBTests/Tier1Extended` | 42 | 18848 |
| `Docs/Status` | 42 | 5827 |
| `BlazeDBTests/Tier2Integration` | 37 | 15082 |
| `BlazeDB/Storage` | 32 | 11411 |
| `BlazeDBTests/Tier0Core` | 30 | 6255 |
| `BlazeDB/Distributed` | 29 | 6611 |
| `Docs/Audit` | 29 | 12167 |
| `Docs/Benchmarks` | 29 | 2577 |
| `Examples/android` | 29 | 1645 |
| `Tests/BlazeDBIntegrationTests` | 29 | 12222 |
| `BlazeStudio/BlazeStudio` | 28 | 1221 |
| `Docs/Testing` | 25 | 8189 |
| `BlazeDBTests/Core` | 24 | 5274 |

## Top 20 directories by line count

| Directory | Lines | Files |
|-----------|------:|------:|
| `Tests/BlazeDBTests` | 72452 | 200 |
| `Docs/Archive` | 64509 | 143 |
| `Docs/Product` | 31036 | 11 |
| `BlazeDBTests/Tier1Core` | 21276 | 93 |
| `BlazeDBTests/Tier1Extended` | 18848 | 42 |
| `BlazeDBTests/Tier2Integration` | 15082 | 37 |
| `BlazeDB/Core` | 14218 | 57 |
| `BlazeDBVisualizer/BlazeDBVisualizer` | 13371 | 45 |
| `Tests/BlazeDBIntegrationTests` | 12222 | 29 |
| `Docs/Audit` | 12167 | 29 |
| `BlazeDB/Storage` | 11411 | 32 |
| `BlazeDB/Exports` | 10507 | 46 |
| `BlazeDB/Query` | 10247 | 42 |
| `Docs/Architecture` | 8344 | 24 |
| `Docs/Testing` | 8189 | 25 |
| `BlazeDBTests/Tier1Perf` | 7979 | 18 |
| `Docs/Security` | 7950 | 16 |
| `Docs/Performance` | 6705 | 20 |
| `BlazeDB/Distributed` | 6611 | 29 |
| `BlazeDBTests/Tier0Core` | 6255 | 30 |

---

*End of generated metrics.*
