# BlazeDB Documentation Inventory (2026-07)

**Status:** Phase 1–2 inventory and classification only. No files were moved, renamed, merged, archived, or deleted in this pass.

**Method:** `git ls-files '*.md'` enumeration; Markdown link graph BFS from primary entry points; full-repo path searches excluding `.build/`, `DerivedData/`, and `Docs/Product/observer-audit-exports/` path dumps; heading/anchor checks for local links.

**Primary entry points:** `README.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `Docs/README.md`.

**Secondary indexes (not treated as public authority):** `Docs/MASTER_DOCUMENTATION_INDEX.md`, `Docs/ARCHIVE_INDEX.md`.

---

## 1. Executive summary

| Metric | Count |
|--------|------:|
| Git-tracked Markdown files | 547 |
| Total documentation lines | 167759 |
| Reachable from primary entry points (link BFS) | 100 |
| Not reachable from primary entry points | 447 |
| Broken local file links (unique link instances) | 71 |
| Broken/missing anchors | 13 true + 3 false positives (HTML `<a id>` on README) |

### Counts by recommendation

| Recommendation | Count |
|----------------|------:|
| KEEP_CANONICAL | 69 |
| KEEP_REFERENCE | 188 |
| MERGE | 31 |
| ARCHIVE | 251 |
| DELETE_CANDIDATE | 6 |
| REVIEW_REQUIRED | 2 |
| **Total** | **547** |

### Key findings

1. **Documentation volume is dominated by historical material:** `Docs/Archive/` alone holds 135 files; `Docs/Status/` + `Docs/Audit/` + `Docs/Project/` + `Docs/Meta/` + `Docs/Tests/` add large completed-narrative corpora. Only ~100 files are reachable via Markdown links from the four primary entry points.
2. **`Docs/README.md` is the curated public authority map** (support-state labels). `Docs/MASTER_DOCUMENTATION_INDEX.md` is a maintainer inventory that still presents sync guides as core “Start Here” material and uses stale relative basenames — it should not be treated as public navigation.
3. **Three architecture maps are complementary, not duplicates:** `ARCHITECTURE.md` (layers), `SYSTEM_MAP.md` (feature status inventory), `CODEBASE_MAP.md` (package/directories/paths). Large `ARCHITECTURE_DETAILED.md` / `BLAZEDB_ARCHITECTURE_AND_LIMITS.md` / `BLAZEDB_SYSTEM_DESIGN_DIAGRAM.md` substantially overlap those plus `WHY_EACH_PART_EXISTS.md`.
4. **Broken links cluster in** (a) archived START_HERE/V3 docs pointing at removed numbered guides, (b) sibling-relative links that ignore the new folder layout (`ARCHITECTURE.md` → `PROTOCOL.md` instead of `../Design/PROTOCOL.md`), and (c) GitHub PR template paths resolved from `.github/`.
5. **Operational automation references a small set of docs** (CI tiers, freeze checklist, KMM/Android status, benchmark sinks, storage paths). Those must stay even if navigation-unlinked.
6. **Safe immediate deletes are few:** only proven identical/near-identical copies under `Tests/BlazeDBTests/*.md` and the Meta `REORGANIZATION_COMPLETE 2.md` filename duplicate — after human confirmation.

---

## 2. Canonical documentation hierarchy (proposed target)

Keep the existing folders where useful; make **navigation** match this compact hierarchy:

```
Product homepage          README.md
Getting started           Docs/GettingStarted/  (+ HOW_TO_USE, Linux, paths, SwiftUI patterns)
Feature guides            Docs/Features/ + Docs/Guides/  (transactions, SwiftUI, CLI, production)
API / reference           Docs/API/ + Docs/API_STABILITY.md + BlazeDB.docc
Architecture              Docs/Architecture/ARCHITECTURE.md
                          Docs/SYSTEM_MAP.md
                          Docs/Architecture/CODEBASE_MAP.md
                          Docs/Architecture/TOURS/
Compatibility/stability   Docs/COMPATIBILITY.md + Docs/Status/{DURABILITY,KEY_MANAGEMENT,*COMPAT*}
Security                  SECURITY.md + Docs/Security/{SECURITY,THREAT_MODEL,ENCRYPTION_STRATEGY}
Contributing              CONTRIBUTING.md + Docs/Contributing/
Roadmap                   ROADMAP.md + Docs/Product/ROADMAP_BACKLOG.md
Release / changelog       RELEASE.md + CHANGELOG.md + Docs/Release/
Testing / CI              Docs/TESTING_GUIDE.md + Docs/Testing/CI_AND_TEST_TIERS.md
Tools                     Docs/Tools/ + Examples/
Deferred surfaces         Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md → Docs/Sync/ (design only)
Archive                   Docs/Archive/ + Docs/ARCHIVE_INDEX.md
```

**Authority rule (already stated in Docs/README.md):** `Package.swift`, tests, and CI win when docs disagree. Historical material is non-authoritative unless a maintained doc explicitly points at it.

---

## 3. Inventory table

Inbound references = count of other Markdown files with a `[]()` link to this file (not bare path mentions).
Reachable from = which primary entry-point BFS roots can reach this file (`README` / `CONTRIBUTING` / `ROADMAP` / `Docs/README`), or `unlinked` / `ops` if only automation mentions it.

| Path | Audience | Inbound | Reachable from | Recommendation | Canonical destination | Evidence / notes |
|------|----------|--------:|----------------|----------------|----------------------|------------------|
| `.github/ISSUE_TEMPLATE/bug_report.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | GitHub template/automation docs (platform-referenced) |
| `.github/ISSUE_TEMPLATE/feature_request.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | GitHub template/automation docs (platform-referenced) |
| `.github/ISSUE_TEMPLATE/security_review_tracking.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | GitHub template/automation docs (platform-referenced) |
| `.github/pull_request_template.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | GitHub template/automation docs (platform-referenced) |
| `.github/REPOSITORY_AUTOMATION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | — | GitHub template/automation docs (platform-referenced) |
| `.github/workflows/README.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `BlazeDB/BlazeDB.docc/BlazeDB.md` | API/reference | 0 | ops | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/strip_markdown_emojis.py |
| `BlazeDB/Distributed/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `BlazeDBC/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `BlazeDBExtraTests/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `BlazeDBTests/Performance/LEGACY_BENCHMARKS.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Benchmarks/README.md | Legacy benchmark note beside Performance tests; unlinked; historical |
| `BlazeDBVisualizer/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `CHANGELOG.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `CODE_OF_CONDUCT.md` | contributor | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `CONTRIBUTING.md` | contributor | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/strip_markdown_emojis.py |
| `Docs/AGENTS_GUIDE.md` | contributor | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/android-status.md` | contributor | 9 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/ci-android-cross-compile.sh |
| `Docs/API/API_REFERENCE.md` | API/reference | 9 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/API/COMPLETE_PROJECT_DOCUMENTATION.md` | API/reference | 1 | unlinked | MERGE | Docs/API/API_REFERENCE.md + Docs/DEVELOPER_GUIDE.md | Large omnibus doc; split unique API bits into API_REFERENCE |
| `Docs/API/GRAPH_QUERY_API.md` | API/reference | 2 | unlinked | KEEP_REFERENCE | Docs/API/API_REFERENCE.md | Graph query API reference |
| `Docs/API/README.md` | API/reference | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/API_STABILITY.md` | API/reference | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/ARCHITECTURE.md` | architecture | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/ARCHITECTURE_COMPARISON.md` | architecture | 0 | unlinked | MERGE | Docs/Architecture/ARCHITECTURE.md + Docs/SYSTEM_MAP.md | Overlaps architecture/system map; preserve unique diagrams/limits |
| `Docs/Architecture/ARCHITECTURE_DETAILED.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | MERGE | Docs/Architecture/ARCHITECTURE.md + Docs/SYSTEM_MAP.md | Overlaps architecture/system map; preserve unique diagrams/limits |
| `Docs/Architecture/BLAZEBINARY_PROTOCOL.md` | architecture | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/BLAZEDB_ARCHITECTURE_AND_LIMITS.md` | architecture | 1 | unlinked | MERGE | Docs/Architecture/ARCHITECTURE.md + Docs/SYSTEM_MAP.md | Overlaps architecture/system map; preserve unique diagrams/limits |
| `Docs/Architecture/BLAZEDB_RELAY.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed architecture; mark deferred |
| `Docs/Architecture/BLAZEDB_SYSTEM_DESIGN_DIAGRAM.md` | architecture | 0 | unlinked | MERGE | Docs/Architecture/ARCHITECTURE.md + Docs/SYSTEM_MAP.md | Overlaps architecture/system map; preserve unique diagrams/limits |
| `Docs/Architecture/C_ABI_BYTE_KV.md` | API/reference | 8 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/CHANGE_MAP.md` | architecture | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/ARCHITECTURE.md | Architecture reference |
| `Docs/Architecture/CODEBASE_MAP.md` | architecture | 8 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/DISTRIBUTED_ARCHITECTURE.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed architecture; mark deferred |
| `Docs/Architecture/EXTENSION_POINTS.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Architecture/ARCHITECTURE.md | Architecture reference |
| `Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md` | architecture | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/ARCHITECTURE.md | Architecture reference |
| `Docs/Architecture/README.md` | architecture | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/SERVER_CLIENT_ARCHITECTURE.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed architecture; mark deferred |
| `Docs/Architecture/STORAGE_ENGINE_NOTES.md` | architecture | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Architecture/TOURS/01_OPEN_AND_RECOVERY.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/02_WRITE_PATH.md` | architecture | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/03_QUERY_PATH.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/04_TRANSACTIONS.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/05_BLAZEDBC.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/06_CLI.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/07_TESTING_AND_BENCHMARKS.md` | architecture | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Architecture/TOURS/README.md | Architecture walkthrough series |
| `Docs/Architecture/TOURS/README.md` | architecture | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Archive/6_GARBAGE_COLLECTION_GUIDE.md` | historical/audit | 1 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/7_FOREIGN_KEYS_GUIDE.md` | historical/audit | 1 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/8_PRODUCTION_GUIDE.md` | historical/audit | 2 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/9_SWIFTUI_TYPE_SAFETY.md` | historical/audit | 1 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ADVANCED_COMPRESSION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ADVANCED_FEATURES_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ADVANCED_TESTING_EXPLAINED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/AGGRESSIVE_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ALL_OPTIMIZATIONS_SUMMARY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ANIMATIONS_ADDED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ARCHITECTURE_CRITIQUE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ASYNC_IMPLEMENTATION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BATTERY_AND_POWER_ANALYSIS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BATTERY_LIFE_AND_PROTOCOL_COMPARISON.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BATTERY_OPTIMIZATION_SUMMARY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEBINARY_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEBINARY_SPECIFICATION.md` | historical/audit | 1 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEBINARY_ULTIMATE_VERIFICATION_COMPLETE.md` | historical/audit | 1 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEBINARY_WEBSOCKET_PROTOCOL.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_CRAZY_METRICS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_FINAL_STATUS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_GRPC.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_MANAGER_ARCHITECTURE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/blazedb_medium_article.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_PLATFORM.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BLAZEDB_VISUALIZER_FINAL.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BlazeServerPrototype/README.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BOTTLENECKS_AND_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BRUTALLY_HONEST_VALUE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/BULLETPROOF_TESTING_SUITE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CLEANUP_SUMMARY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CLIENT_READY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CLIENT_SIDE_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/COMPETITIVE_LANDSCAPE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/COMPLETE_GC_FINAL.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/COMPRESSION_ANALYSIS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CORRECTED_PERFORMANCE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CRASH_SAFETY_FIXES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CRC32_CHECKSUMS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CREATIVE_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CREATIVE_OPTIMIZATIONS_IMPLEMENTED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CRITICAL_BLOCKERS_FIXED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CRITICAL_BUGS_FIXED_2025-11-12.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/CROSS_APP_SYNC.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/DETAILED_DATABASE_COMPARISON.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/DEVELOPER_GUIDE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/DISCOVERY_AND_CONNECTION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/DISTRIBUTED_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/DISTRIBUTED_STATUS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/EDITING_IMPLEMENTATION_STATUS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/EDITING_READY_TO_TEST.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/EFFICIENCY_BREAKDOWN.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/EXTREME_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/GRPC_ARCHITECTURE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/HONEST_SYNC_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/HONEST_THOUGHTS_AND_ASSESSMENT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/HOW_DATABASES_FIND_EACH_OTHER.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/HOW_IT_WORKS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/HOW_WE_MADE_IT_FASTER.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/IMPLEMENTATION_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/IMPLEMENTATION_PLAN.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/INCREMENTAL_SYNC.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/LEVEL_10_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/LEVEL_8_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MASTER_INTEGRATION_PLAN.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MONITORING_API.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MONITORING_SECURITY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MVCC_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MVCC_IMPLEMENTATION_PROGRESS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MVCC_PHASE1_TESTING_GUIDE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MVCC_PHASE2_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MVCC_PHASE2_PROGRESS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/MY_HONEST_OPINION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/NETWORK_BANDWIDTH_REALITY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/NEXT_STEPS_ACTION_PLAN.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/OPEN_SOURCE_REAUDIT_2026-03-16.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/OPERATIONS_READINESS_TABLE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/OPTIMIZATIONS_IMPLEMENTED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/P2P_ARCHITECTURE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/P2P_SECURITY_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/PROTOCOL_AND_THROUGHPUT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/PROTOCOL_ARCHITECTURE_DECISION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/PROTOCOL_COMPARISON.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/QUICK_REFERENCE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/QUICK_START_LEVEL_10.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RAPID_SYNC_ARCHITECTURE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RAPID_SYNC_IMPLEMENTATION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RASPBERRY_PI_DEPLOYMENT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RASPBERRY_PI_VAPOR_SETUP.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RBAC_GUIDE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/README.md` | historical/audit | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/ARCHIVE_INDEX.md | Archive directory index |
| `Docs/Archive/REAL_NUMBERS_AND_FIXES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/REAL_TIME_SYNC.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/REAL_WORLD_USE_CASES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/REALISTIC_LIMITS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/REALISTIC_METRICS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/REALISTIC_NUMBERS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/RELEASE_EVIDENCE_BLOCKERS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/Roadmaps/FEATURE_ROADMAP.md` | historical/audit | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/Roadmaps/OPTIMIZATION_ROADMAP.md` | historical/audit | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/Roadmaps/PRODUCTION_READINESS_ROADMAP.md` | historical/audit | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SECURITY_AUDIT_IMPLEMENTATION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SECURITY_FIXES_IMPLEMENTED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SECURITY_PERFORMANCE_ANALYSIS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SHARED_SECRET_IMPLEMENTATION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SMOOTH_AS_BUTTER.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/START_HERE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SYNC_DOCUMENTATION_INDEX.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SYNC_GUIDE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/SYNC_QUICK_START.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/THE_BIG_PICTURE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/THE_VISION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/THIS_IS_IT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/TRANSFER_LIMITS_AND_USE_CASES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/TRANSPORT_PROTOCOL_EXPLAINED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/TUTORIALS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ULTRA_FAST_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ULTRA_FAST_SUMMARY.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/ULTRA_OPTIMIZATIONS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VERIFICATION_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_COMPLETE_STATUS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_EDITING_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_EDITING_PROPOSAL.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_SECURITY_ANALYSIS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_TEST_RUNNER_NOTE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_UPGRADE_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_UPGRADE_PLAN.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/VISUALIZER_V1.2_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHAT_IS_COMPRESSION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHAT_THIS_ENABLES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHAT_WE_JUST_ADDED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHATS_NEW_LEVEL_10.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_CHOOSE_BLAZEDB.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_NOT_FAST_AND_LIMITS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_NOT_STANDARD.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_THIS_DOESNT_EXIST.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_THIS_IS_UNIQUE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/Archive/WHY_THIS_MATTERS.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/ | Already under Docs/Archive/; historical completed notes |
| `Docs/ARCHIVE_INDEX.md` | historical/audit | 0 | full-index | KEEP_REFERENCE | Docs/Archive/README.md | Archive pointer list; many entries are basenames without paths and some already moved — Batch A fix |
| `Docs/Audit/ARM_CODE_REVIEW.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/ARM_CODE_REVIEW_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Completed/dated audit or fix summary |
| `Docs/Audit/BLAZEBINARY_PROTOCOL_AND_IO_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/BLAZEBINARY_PROTOCOL_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/BLAZEDB_AUDIT_REPORT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/BLAZEDB_GAPS_AND_ISSUES_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/CODE_AUDIT_FIXES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/CODE_AUDIT_REPORT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/COMPREHENSIVE_AUDIT_REPORT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/CRASH_POINTS_FIXED.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Completed/dated audit or fix summary |
| `Docs/Audit/DISTRIBUTED_SYNC_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/DUAL_CODEC_VALIDATION_COMPLETE.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Completed/dated audit or fix summary |
| `Docs/Audit/FATALERROR_REMOVAL.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/FILE_LOCKING_AUDIT_REPORT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/FINAL_LINUX_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/FORENSIC_FEATURE_EXTRACTION.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/IMPLEMENTATION_PLAN_INSANE_FEATURES.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/LINUX_COMPATIBILITY_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/LOGGING_AUDIT_REPORT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/PERFORMANCE_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md` | historical/audit | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Audit/README.md` | historical/audit | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md | Audit index |
| `Docs/Audit/REAUDIT_AFTER_HARDENING.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/SAFETY_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/SECURITY_AND_TESTING_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/SECURITY_LINUX.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/SIZE_AUDIT.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Historical audit report; keep POST_AUDIT_FINDINGS_2026_07 as current |
| `Docs/Audit/SUMMARY_INSANE_FEATURES_2025.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Completed/dated audit or fix summary |
| `Docs/Audit/TODO_DIRECT_CODABLE_ENCODER.md` | historical/audit | 0 | unlinked | ARCHIVE | Docs/Archive/Audits/ | Completed/dated audit or fix summary |
| `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md` | maintainer | 0 | ops | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/generate_benchmark_environment.py, Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/COMPARISON.md` | maintainer | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/publish_benchmark_results.py |
| `Docs/Benchmarks/CONCURRENT_MVCC.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/run_concurrent_mvcc_comparison.sh |
| `Docs/Benchmarks/ENERGY.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/FULL_BENCHMARK_SUMMARY.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/GC_BENCHMARKS.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/LATENCY.md` | maintainer | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/generate_latency_report.py, Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/LIMITS.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/generate_limits_report.py, Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/OBSERVABILITY_BENCHMARKS.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/POWER_BENCHMARKS.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/README.md` | user | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Benchmarks/RESULTS.md` | maintainer | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: BlazeDBBenchmarks/main.swift, Scripts/publish_benchmark_results.py, Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/results_baseline.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced) |
| `Docs/Benchmarks/results_encryption_off_requested.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced) |
| `Docs/Benchmarks/results_mvcc_off.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced) |
| `Docs/Benchmarks/results_wal_off_requested.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced) |
| `Docs/Benchmarks/RUN_STATUS.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/SQLITE_LIMITS_COMPARISON.md` | maintainer | 0 | ops | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced); ops: Scripts/generate_sqlite_comparison.py, Scripts/refresh_benchmark_suite.py |
| `Docs/Benchmarks/WRITE_PATH_PROFILE.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Benchmarks/README.md | Benchmark results/environment (tooling-referenced) |
| `Docs/Build/BUILD_ERRORS_RESOLUTION.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Build/README.md | Resolved build-issue notes |
| `Docs/Build/BUILD_SYSTEM_ISSUES.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Build/README.md | Resolved build-issue notes |
| `Docs/Build/README.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Build/README.md | Build/schemes reference |
| `Docs/Build/TEST_BUILD_GRAPH.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Build/README.md | Build/schemes reference |
| `Docs/Build/XCODE_BUILD_FIX.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Build/README.md | Resolved build-issue notes |
| `Docs/Build/XCODE_SCHEMES.md` | maintainer | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Build/README.md | Build/schemes reference |
| `Docs/COMPATIBILITY.md` | maintainer | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/ci-android-cross-compile.sh |
| `Docs/Compliance/CHECKLIST_COMPLETE.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Compliance/ | Completed compliance checklist |
| `Docs/Compliance/CONCURRENCY_COMPLIANCE.md` | contributor | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Compliance/README.md | Compliance/hardening records |
| `Docs/Compliance/PHASE_1_FREEZE.md` | contributor | 0 | ops | KEEP_REFERENCE | Docs/Compliance/README.md | Compliance/hardening records; ops: Scripts/check-freeze.sh |
| `Docs/Compliance/PHASE_2_PARALLELISM.md` | contributor | 0 | unlinked | KEEP_REFERENCE | Docs/Compliance/README.md | Compliance/hardening records |
| `Docs/Compliance/PRE_USER_HARDENING.md` | contributor | 0 | unlinked | KEEP_REFERENCE | Docs/Compliance/README.md | Compliance/hardening records |
| `Docs/Compliance/QUALITY_IMPROVEMENTS.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Compliance/ | Completed compliance checklist |
| `Docs/Compliance/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Compliance/README.md | Compliance/hardening records |
| `Docs/Contributing/ISSUE_CODE_INDEX.md` | contributor | 6 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Contributing/ISSUE_GUIDE.md` | contributor | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: .github/ISSUE_TEMPLATE/config.yml |
| `Docs/Contributing/LEARNING_PATHS.md` | contributor | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Contributing/OSS_CORE_BUILD_EXCLUDES.md` | contributor | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md` | contributor | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Design/CLI_DOCTOR_REPORT.md` | architecture | 1 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/Design/CLI_DOCTOR_REPORT_PLAN.md` | architecture | 1 | unlinked | ARCHIVE | Docs/Design/ | Completed DX/plan notes |
| `Docs/Design/COMPRESSION_DESIGN.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/Design/DEVELOPER_EXPERIENCE_IMPROVEMENTS.md` | architecture | 0 | unlinked | ARCHIVE | Docs/Design/ | Completed DX/plan notes |
| `Docs/Design/DX_IMPROVEMENTS_SUMMARY.md` | architecture | 0 | unlinked | ARCHIVE | Docs/Design/ | Completed DX/plan notes |
| `Docs/Design/PROTOCOL.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/Design/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/Design/SECURE_HANDSHAKE_EXPLAINED.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/Design/SNAPSHOT_SYNC_DESIGN.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Design/README.md | Design reference |
| `Docs/DEVELOPER_GUIDE.md` | user | 6 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Features/EVENT_TRIGGERS.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/FEATURE_VERIFICATION_REPORT.md` | user | 1 | unlinked | ARCHIVE | Docs/Features/README.md | Feature hype/verification narrative |
| `Docs/Features/GEOSPATIAL_ENHANCEMENTS.md` | user | 0 | unlinked | ARCHIVE | Docs/Features/README.md | Feature hype/verification narrative |
| `Docs/Features/GEOSPATIAL_INSANE_FEATURES.md` | user | 0 | unlinked | ARCHIVE | Docs/Features/README.md | Feature hype/verification narrative |
| `Docs/Features/GEOSPATIAL_QUERIES.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/INSANE_FEATURES.md` | user | 0 | unlinked | ARCHIVE | Docs/Features/README.md | Feature hype/verification narrative |
| `Docs/Features/LAZY_DECODING.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/MATH_OPERATIONS.md` | user | 1 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/MULTI_WORKSPACE_OPTIMIZATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/ORDERING_INDEX.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/ORDERING_INDEX_ADVANCED.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/OVERFLOW_PAGES_IMPLEMENTATION.md` | user | 1 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/QUERY_PLANNER.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/REACTIVE_QUERIES_EXPLAINED.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/README.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Features/ROW_LEVEL_SECURITY.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/ROW_MANIPULATION.md` | user | 1 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/Features/TRANSACTIONS.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Features/VECTOR_QUERIES.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Features/README.md | Feature guide |
| `Docs/GC/GC_ENHANCEMENTS_NEEDED.md` | architecture | 0 | unlinked | REVIEW_REQUIRED | Docs/Architecture/STORAGE_ENGINE_NOTES.md | Large TODO list; may contain still-open GC work — do not archive until checked against code/issues |
| `Docs/GC/GC_IMPLEMENTATION_SUMMARY.md` | architecture | 0 | unlinked | ARCHIVE | Docs/Architecture/STORAGE_ENGINE_NOTES.md | Completed GC implementation narrative |
| `Docs/GC/GC_PROOF.md` | architecture | 0 | unlinked | ARCHIVE | Docs/Architecture/STORAGE_ENGINE_NOTES.md | Completed GC implementation narrative |
| `Docs/GC/GC_TODO_CRITICAL.md` | architecture | 0 | unlinked | REVIEW_REQUIRED | Docs/Architecture/STORAGE_ENGINE_NOTES.md | Critical GC TODO narrative; verify open items before ARCHIVE |
| `Docs/GC/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/GC/README.md | GC docs |
| `Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md` | user | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: BlazeDB/Exports/BlazeDBClient+EasyOpen.swift, BlazeDB/Telemetry/TelemetryConfiguration.swift, BlazeDB/Utils/PathResolver.swift |
| `Docs/GettingStarted/FEATURE_ROADMAP.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | MERGE | ROADMAP.md | Tiny stub overlapping ROADMAP |
| `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md` | user | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/GettingStarted/KMM_GETTING_STARTED.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/package-kmm-artifacts.sh |
| `Docs/GettingStarted/LINUX_GETTING_STARTED.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/GettingStarted/LINUX_PLATFORM_MODEL.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/GettingStarted/README.md | Positioning/platform guidance |
| `Docs/GettingStarted/OPERATIONAL_CONFIDENCE.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/GettingStarted/README.md | Positioning/platform guidance |
| `Docs/GettingStarted/QUERY_PERFORMANCE.md` | user | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/GettingStarted/README.md | Getting started material; ops: Examples/QuickStart.swift |
| `Docs/GettingStarted/README.md` | user | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Examples/HelloBlazeDB/main.swift |
| `Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md` | user | 10 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/GettingStarted/README.md | Getting started material; ops: Examples/SwiftUIExample.swift |
| `Docs/GettingStarted/SWIFTUI_FACADE_MIGRATION.md` | maintainer | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/GettingStarted/README.md | Getting started material |
| `Docs/GettingStarted/USABILITY_PORTABILITY.md` | user | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/GettingStarted/README.md | Getting started material |
| `Docs/GettingStarted/USE_CASE_ANALYSIS.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/GettingStarted/README.md | Positioning/platform guidance |
| `Docs/GettingStarted/WHY_BLAZEDB_EXISTS.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/GettingStarted/README.md | Positioning/platform guidance |
| `Docs/GettingStarted/WHY_NOT_SQLITE.md` | user | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/GettingStarted/README.md | Getting started material |
| `Docs/Guarantees/SAFETY_MODEL.md` | architecture | 2 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/ANTI_PATTERNS.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Guides/CLI_REFERENCE.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/CONNECTING_DATABASES_GUIDE.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed/sync guide; note deferred status |
| `Docs/Guides/CONVENIENCE_API_GUIDE.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Guides/DEVELOPMENT_PERFORMANCE.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Guides/DEVICE_DISCOVERY.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed/sync guide; note deferred status |
| `Docs/Guides/MIGRATION_GUIDE.md` | maintainer | 1 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/NULL_HANDLING.md` | user | 1 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Guides/PRODUCTION_DEPLOYMENT.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/QUICK_START_DISTRIBUTED.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed/sync guide; note deferred status |
| `Docs/Guides/README.md` | user | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/README_SYNC.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Distributed/sync guide; note deferred status |
| `Docs/Guides/RUNNING_IN_SERVERS.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Guides/SWIFTUI_INTEGRATION.md` | user | 9 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Guides/USAGE_BY_TASK.md` | user | 0 | ops | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide; ops: Examples/QuickStart.swift |
| `Docs/Guides/WORKFLOW_AND_STYLE_GUIDE.md` | contributor | 0 | unlinked | KEEP_REFERENCE | Docs/Guides/README.md | User/contributor guide |
| `Docs/Internal/DOC_CONSOLIDATION_AND_ARTIFACT_REMOVAL_REPORT.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | — | Maintainer hygiene/plan still relevant to doc cleanup |
| `Docs/Internal/README.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Internal maintainer notes |
| `Docs/Internal/REPO_HYGIENE_AUDIT.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | — | Maintainer hygiene/plan still relevant to doc cleanup |
| `Docs/Internal/RLS_FULL_IMPLEMENTATION_PLAN.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | — | Maintainer hygiene/plan still relevant to doc cleanup |
| `Docs/Internal/SWIFTUI_OBSERVATION_DOC_UPDATE_REPORT.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | — | Internal maintainer notes |
| `Docs/Internal/SWIFTUI_PATH_MAINTAINER_NOTE.md` | maintainer | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Internal maintainer notes |
| `Docs/INTERVIEW_MASTER_LIST.md` | contributor | 0 | unlinked | KEEP_REFERENCE | Docs/WHY_EACH_PART_EXISTS.md | Maintainer/interview architecture narrative cluster |
| `Docs/INTERVIEW_PREPARATION.md` | contributor | 1 | unlinked | KEEP_REFERENCE | Docs/WHY_EACH_PART_EXISTS.md | Maintainer/interview architecture narrative cluster |
| `Docs/MASTER_DOCUMENTATION_INDEX.md` | contributor | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/README.md | Maintainer inventory; Docs/README.md is curated authority. MASTER still lists sync as primary and broken relative names — Batch A fix |
| `Docs/Meta/COMPLETE_REORGANIZATION.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/DEPRECATE_BLAZECOLLECTION.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/DOC_AUDIT_TRACKER.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/FINAL_MIGRATION_INSTRUCTIONS.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/FINAL_MOVES_COMPLETE.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/FINAL_REORGANIZATION_INSTRUCTIONS.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/MIGRATION_SCRIPT.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/ORGANIZATION_SUMMARY.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/README.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Directory index for historical reorg notes |
| `Docs/Meta/REORGANIZATION_COMPLETE 2.md` | maintainer | 0 | unlinked | DELETE_CANDIDATE | Docs/Meta/REORGANIZATION_COMPLETE.md | Filename has space+"2"; longer sibling of REORGANIZATION_COMPLETE.md — pick one canonical Meta copy then delete other |
| `Docs/Meta/REORGANIZATION_COMPLETE.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/REORGANIZATION_PLAN.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/REORGANIZATION_STATUS.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Meta/REORGANIZATION_SUMMARY.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/MIGRATION.md` | maintainer | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Migration/WORKSPACE_PROJECTROOT_MIGRATION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/MIGRATION.md | Specific migration guide |
| `Docs/Performance/ARM_OPTIMIZATION_SUMMARY.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/ASYNC_AND_SERVER_READINESS.md` | roadmap/planning | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/BANDWIDTH_ANALYSIS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/BENCHMARK_INSTRUCTIONS.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Performance/PERFORMANCE.md | Performance reference |
| `Docs/Performance/BLAZEDB_BINARY_IO_OPTIMIZATION.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/IMPROVEMENTS_SUMMARY.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/LATENCY_BREAKDOWN.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/PERFORMANCE.md` | maintainer | 0 | ops | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: Scripts/publish_benchmark_results.py |
| `Docs/Performance/PERFORMANCE_ANALYSIS_AND_OPTIMIZATIONS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/PERFORMANCE_BLAZE_RECORD_ENCODER.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/PERFORMANCE_NUMBERS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/PERFORMANCE_OPTIMIZATIONS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/QUERY_OPTIMIZATIONS.md` | maintainer | 1 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Performance/PERFORMANCE.md | Performance hub |
| `Docs/Performance/REALISTIC_PERFORMANCE_ANALYSIS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/RELIABILITY_COMPARISON.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/RLS_OPTIMIZATION.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/TCP_RELIABILITY.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/THROUGHPUT_ANALYSIS.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Performance/ULTRA_FAST_PROTOCOL.md` | maintainer | 0 | unlinked | MERGE | Docs/Performance/PERFORMANCE.md | Overlapping performance analysis; preserve unique measured numbers/sections |
| `Docs/Product/COMMIT_HISTORY_AUDIT.md` | roadmap/planning | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster |
| `Docs/Product/ISSUE_TRACKER_AUDIT.md` | roadmap/planning | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster |
| `Docs/Product/NEXT_ENGINEERING_AUDIT.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster |
| `Docs/Product/OUTSIDE_OBSERVER_AUDIT.md` | roadmap/planning | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster |
| `Docs/Product/PRODUCT_AUDIT.md` | roadmap/planning | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster; ops: BlazeDB/Indexing/ExperimentalBPlusTree.swift |
| `Docs/Product/ROADMAP_BACKLOG.md` | roadmap/planning | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Product/roadmap audit cluster |
| `Docs/Project/100_PERCENT_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/BETA_READINESS_SUMMARY.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/BLAZEDB_ASSESSMENT.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/COMPLETION_STATUS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/FINAL_STATUS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/HONEST_GAPS_ASSESSMENT.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md | Gaps assessment superseded by newer audits |
| `Docs/Project/HONEST_GAPS_ASSESSMENT_2025.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md | Gaps assessment superseded by newer audits |
| `Docs/Project/HONEST_PROJECT_AUDIT.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Long-form project audit; product audits may supersede |
| `Docs/Project/OPTIMIZATION_ROADMAP.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | MERGE | ROADMAP.md | Overlaps root ROADMAP; preserve unique optimization items |
| `Docs/Project/OPTIMIZATION_STATUS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/PERFORMANCE_METRICS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Project/ | Completed project status narrative |
| `Docs/Project/README.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Product/PRODUCT_AUDIT.md | Project status/completion narrative |
| `Docs/README.md` | user | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/README_AUDIT.md` | historical/audit | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Audit/DOCUMENTATION_INVENTORY_2026_07.md | Onboarding/authority audit still linked from Docs/README; complementary to this inventory |
| `Docs/Release/FINAL_RELEASE_STATUS.md` | maintainer | 1 | unlinked | ARCHIVE | Docs/Release/RELEASE.md | Completed release readiness snapshot |
| `Docs/Release/README.md` | maintainer | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Release/RELEASE.md` | maintainer | 1 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Release/RELEASE_NOTES_v0.1.0.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Release/RELEASE.md | Release notes/process |
| `Docs/Release/RELEASE_NOTES_v0.1.1.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Release/RELEASE.md | Release notes/process |
| `Docs/Release/RELEASE_NOTES_v0.1.2.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Release/RELEASE.md | Release notes/process |
| `Docs/Release/RELEASE_NOTES_v0.1.3.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Release/RELEASE.md | Release notes/process |
| `Docs/Release/RELEASE_READINESS_CHECKLIST.md` | roadmap/planning | 1 | unlinked | ARCHIVE | Docs/Release/RELEASE.md | Completed release readiness snapshot |
| `Docs/Release/VALIDATION_SUMMARY.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Release/RELEASE.md | Completed release readiness snapshot |
| `Docs/RELEASE_POSTURE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/SYSTEM_MAP.md | Cited from SYSTEM_MAP.md intro as release-line policy; not in primary nav |
| `Docs/Security/AUTH_TOKEN_MANAGEMENT.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/BLAZEDB_THREAT_MODEL.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | MERGE | Docs/Security/THREAT_MODEL.md | 859-line BlazeDB-specific threat model vs 432-line THREAT_MODEL.md; preserve unique controls into one canonical threat doc |
| `Docs/Security/COMPLETE_SHARED_SECRET_GUIDE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/DATABASE_SESSION_KEY_LIFECYCLE.md` | maintainer | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security doc; ops: Scripts/publish_benchmark_results.py |
| `Docs/Security/ENCRYPTION_STRATEGY.md` | maintainer | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Security/P2P_ENCRYPTION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Security/SECURE_TCP_HANDSHAKE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/SECURITY.md` | maintainer | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Security/SECURITY_ANALYSIS.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/SECURITY_AND_APP_STORE_COMPLIANCE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Security/SECURITY.md | Security topic guide |
| `Docs/Security/SECURITY_AUDIT_CHECKLIST.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/Security/ | Security planning/checklist snapshot |
| `Docs/Security/SECURITY_AUDIT_PREPARATION.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/Security/ | Security planning/checklist snapshot |
| `Docs/Security/SECURITY_ENHANCEMENT_PLAN.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/Security/ | Security planning/checklist snapshot |
| `Docs/Security/SECURITY_ISSUE_KEY_DERIVATION.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/Security/ | Security planning/checklist snapshot |
| `Docs/Security/THREAT_MODEL.md` | maintainer | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/SQL/COMPLETE_SQL_IMPLEMENTATION.md` | architecture | 0 | unlinked | MERGE | Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md | Overlapping SQL completion narratives; preserve unique coverage claims |
| `Docs/SQL/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/SQL/README.md | SQL status/reference |
| `Docs/SQL/SQL_COMPLETE_IMPLEMENTATION_SUMMARY.md` | architecture | 0 | unlinked | MERGE | Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md | Overlapping SQL completion narratives; preserve unique coverage claims |
| `Docs/SQL/SQL_COVERAGE_STATUS.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/SQL/README.md | SQL status/reference |
| `Docs/SQL/SQL_FEATURES_COMPARISON.md` | architecture | 1 | unlinked | KEEP_REFERENCE | Docs/SQL/README.md | SQL status/reference |
| `Docs/SQL/SQL_FEATURES_COMPLETE_OPTIMIZED.md` | architecture | 1 | unlinked | MERGE | Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md | Overlapping SQL completion narratives; preserve unique coverage claims |
| `Docs/SQL/SQL_FEATURES_FINAL_STATUS.md` | architecture | 0 | unlinked | MERGE | Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md | Overlapping SQL completion narratives; preserve unique coverage claims |
| `Docs/SQL/SQL_FEATURES_IMPLEMENTATION.md` | architecture | 1 | unlinked | MERGE | Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md | Overlapping SQL completion narratives; preserve unique coverage claims |
| `Docs/Status/ADOPTION_READINESS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/AI_API_VERIFICATION.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/AUDIT_GAPS_RESOLVED.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/BETA_PRODUCTION_READINESS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/BLAZEDB_ASSURANCE_MATRIX.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/BLAZEDB_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/BLAZEDB_VERIFICATION_STATUS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/BLAZEFSM_PIN_ISSUE.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | Docs/Status/KNOWN_ISSUES.md | Named issue/status note; confirm whether still open |
| `Docs/Status/BUILD_STATUS.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/COMPATIBILITY_HARNESS.md` | roadmap/planning | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Status/COMPATIBILITY_VERIFICATION.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/COMPILATION_FIXES_SUMMARY.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/CRASH_SURVIVAL.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` | roadmap/planning | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Status/DURABILITY_MODE_SUPPORT.md` | roadmap/planning | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: BlazeDB/Core/BlazeDBManager.swift |
| `Docs/Status/ENGINE_INTEGRATION_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/EXTERNAL_SECURITY_REVIEW_PLAN.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/FATALERROR_FIXES.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/HARDENING_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md` | roadmap/planning | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Status/KNOWN_ISSUES.md` | roadmap/planning | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/LINUX_BRINGUP_STATUS.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/NETWORK_FRAMEWORK_FIX_SUMMARY.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/OPEN_SOURCE_READINESS_CHECKLIST.md` | roadmap/planning | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/PATCH_VERIFICATION_REPORT.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/PRODUCTION_READINESS_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/PRODUCTION_READINESS_REVIEW.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/PRODUCTION_READINESS_ROADMAP.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/README.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | — | Status index |
| `Docs/Status/RELEASE_ROLLBACK.md` | roadmap/planning | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | — | Operational status still cited or current |
| `Docs/Status/RELEASE_V0.1.0.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/SWIFTPM_DEPENDENCY_STATUS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_COMPILATION_FIXES.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_EXECUTION.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_STABILIZATION_COMPLETE.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_STABILIZATION_FINAL.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_STABILIZATION_PROGRESS.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_STABILIZATION_SUMMARY.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/TEST_TIERS.md` | roadmap/planning | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Status/VALIDATION_REPORT.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/Status/WHAT_NEXT.md` | roadmap/planning | 0 | unlinked | ARCHIVE | Docs/Archive/Status/ | Completed status snapshot or superseded readiness note |
| `Docs/superpowers/plans/2026-07-26-blazedb-dev-commands.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | Recent design/plan artifacts |
| `Docs/superpowers/specs/2026-07-26-blazedb-dev-commands-design.md` | contributor | 0 | unlinked | KEEP_REFERENCE | — | Recent design/plan artifacts |
| `Docs/SUPPORT_POLICY.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Sync/DISTRIBUTED_SYNC_CLARIFICATION.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md | Sync deferral/clarification |
| `Docs/Sync/IN_MEMORY_VS_UNIX_SOCKETS.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/README.md` | user | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Sync/SYNC_EXAMPLES.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/SYNC_MEMORY_SAFETY.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/SYNC_TOPOLOGY.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/SYNC_TRANSPORT_GUIDE.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/SYNC_TRANSPORT_SUMMARY.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/Sync/UNIX_DOMAIN_SOCKETS.md` | architecture | 0 | unlinked | KEEP_REFERENCE | Docs/Sync/README.md | Sync/transport reference (distributed deferred) |
| `Docs/SYSTEM_MAP.md` | architecture | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Testing/CI_AND_TEST_TIERS.md` | maintainer | 5 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: .github/workflows/ci.yml, Scripts/ci-apple-cross-compile.sh, Scripts/run-tier2-tier3-companions.sh |
| `Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/DESTRUCTIVE_TESTS_STATUS.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/GC_TEST_COVERAGE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/OVERFLOW_PAGES_TEST_COVERAGE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing doc |
| `Docs/Testing/OVERFLOW_REACTIVE_TEST_COMPLETE.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/PR3_RECLASSIFICATION_MAP.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/PRE_RUNTIME_BUG_PREVENTION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/PRODUCTION_GRADE_TESTING.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/PRODUCTION_READINESS_ASSESSMENT.md` | roadmap/planning | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/README.md` | maintainer | 0 | unlinked | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Testing/TEST_COVERAGE_DISTRIBUTED.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_COVERAGE_DOCUMENTATION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_ENUMERATION.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_EXAMPLES_VISUAL_GUIDE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_FIXES_COMPLETE.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/TEST_FIXES_SUMMARY.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/TEST_INFRASTRUCTURE_CHECKLIST.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_PLAN.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_REORGANIZATION_PROPOSAL.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/TEST_RUNNER_DEBUGGING.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing reference |
| `Docs/Testing/TEST_RUNNER_GUIDE.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/Testing/README.md | Testing doc |
| `Docs/Testing/TEST_STABILITY_FIXES.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/TEST_SUITES_SUMMARY.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Testing/README.md | Completed test fix/reorg narrative |
| `Docs/Testing/TESTS_DIRECTORY.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Docs/Testing/README.md | Testing doc |
| `Docs/TESTING_GUIDE.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Tests/COMPLETE_REORGANIZATION.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/FINAL_MIGRATION_INSTRUCTIONS.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/FINAL_MOVES_COMPLETE.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/FINAL_REORGANIZATION_INSTRUCTIONS.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/MIGRATION_SCRIPT.md` | maintainer | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/REORGANIZATION_COMPLETE.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/REORGANIZATION_COMPLETE_2.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/REORGANIZATION_PLAN.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/REORGANIZATION_STATUS.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/REORGANIZATION_SUMMARY.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tests/TEST_SUITES_SUMMARY.md` | contributor | 0 | unlinked | ARCHIVE | Docs/Archive/ or Docs/Meta/ | Reorganization/migration meta notes; supersession cluster with Docs/Tests/* and Tests/BlazeDBTests/* duplicates |
| `Docs/Tools/BLAZEDBVISUALIZER_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/BLAZEDOCTOR_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/BLAZEDUMP_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/BLAZEINFO_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/BLAZESHELL_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/BLAZESTUDIO_DOCUMENTATION.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/MCP_SERVER.md` | user | 1 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/Tools/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Docs/Tools/USING_BLAZELOGGER_IN_VISUALIZER.md` | user | 0 | unlinked | KEEP_REFERENCE | Docs/Tools/README.md | Tool documentation |
| `Docs/WALKTHROUGH_CHECKLIST.md` | contributor | 1 | unlinked | KEEP_REFERENCE | Docs/WHY_EACH_PART_EXISTS.md | Maintainer/interview architecture narrative cluster |
| `Docs/WHY_EACH_PART_EXISTS.md` | architecture | 2 | unlinked | KEEP_REFERENCE | Docs/WHY_EACH_PART_EXISTS.md | Maintainer/interview architecture narrative cluster |
| `Examples/android/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/BasicExample/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/BlazeDBAndroidBridge/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/C/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README; ops: Examples/C/hello_blazedb.c |
| `Examples/CorePathSmoke/README.md` | user | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/Go/README.md` | user | 3 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/MVVMPattern/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `Examples/ReadmeSamples/README.md` | user | 2 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README; ops: Examples/ReadmeSamples/main.swift, Scripts/check-readme-sample-coverage.sh |
| `Examples/ReferenceConsumer/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Examples/SYNC_EXAMPLES_INDEX.md` | user | 0 | ops | KEEP_REFERENCE | Examples/README.md | Package/example README; ops: Scripts/strip_markdown_emojis.py |
| `Examples/VaporServer/README.md` | user | 0 | unlinked | KEEP_REFERENCE | Examples/README.md | Package/example README |
| `Experiments/README.md` | user | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_REFERENCE | Examples/README.md | Package/example README; ops: BlazeDBCLITests/DeveloperCommandsTests.swift, BlazeShell/CLIHelp.swift, BlazeShell/DeveloperCommands.swift |
| `README.md` | user | 7 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: .github/workflows/release.yml, BlazeDBCLITests/DeveloperCommandsTests.swift, BlazeShell/CLIHelp.swift |
| `README_HOMEBREW_TAP.md` | contributor | 0 | unlinked | KEEP_REFERENCE | RELEASE.md | Homebrew tap instructions; link from RELEASE/README |
| `RELEASE.md` | maintainer | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |
| `ROADMAP.md` | roadmap/planning | 20 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: .github/ISSUE_TEMPLATE/config.yml, BlazeDB/Indexing/ExperimentalBPlusTree.swift |
| `SECURITY.md` | maintainer | 4 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract; ops: .github/ISSUE_TEMPLATE/config.yml |
| `Tests/BlazeDBTests/CREATE_TEST_PLANS_IN_XCODE.md` | contributor | 0 | unlinked | DELETE_CANDIDATE | Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md | SHA256-identical to Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md |
| `Tests/BlazeDBTests/FINAL_REORGANIZATION_INSTRUCTIONS.md` | contributor | 0 | unlinked | DELETE_CANDIDATE | Docs/Tests/FINAL_REORGANIZATION_INSTRUCTIONS.md | Near-duplicate of Docs/Tests copy; completed instructions |
| `Tests/BlazeDBTests/REORGANIZATION_PLAN.md` | contributor | 0 | unlinked | DELETE_CANDIDATE | Docs/Tests/REORGANIZATION_PLAN.md | Near-duplicate of Docs/Tests copy (67 lines; byte diff trivial); completed reorg plan |
| `Tests/BlazeDBTests/REORGANIZATION_STATUS.md` | contributor | 0 | unlinked | DELETE_CANDIDATE | Docs/Tests/REORGANIZATION_STATUS.md | SHA256-identical to Docs/Tests/REORGANIZATION_STATUS.md; zero unique content |
| `Tests/BlazeDBTests/TEST_PLAN.md` | contributor | 0 | unlinked | DELETE_CANDIDATE | Docs/Testing/TEST_PLAN.md | Near-duplicate of Docs/Testing/TEST_PLAN.md (499 lines; trivial byte diff) |
| `Tests/BlazeDBTests/TEST_REORGANIZATION_PROPOSAL.md` | contributor | 0 | unlinked | MERGE | Docs/Testing/TEST_REORGANIZATION_PROPOSAL.md | Same title/structure as Docs/Testing copy but DIFFER content size (8932 vs 11312 bytes); preserve any unique sections then delete Tests/ copy |
| `Tests/CompatibilityFixtures/README.md` | maintainer | 0 | unlinked | KEEP_REFERENCE | Docs/COMPATIBILITY.md | Fixtures README for compatibility harness; operational even if unlinked from Docs/README |
| `THIRD_PARTY_NOTICES.md` | maintainer | 1 | CONTRIBUTING.md,README.md,ROADMAP.md | KEEP_CANONICAL | — | Primary navigation or stability/ops contract |

---

## 4. Duplicate and overlap groups

### Architecture / system maps

**Strongest canonical:** `Docs/Architecture/ARCHITECTURE.md + Docs/SYSTEM_MAP.md + Docs/Architecture/CODEBASE_MAP.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/Architecture/ARCHITECTURE.md` | KEEP_CANONICAL | Layered architecture overview (241 lines) |
| `Docs/SYSTEM_MAP.md` | KEEP_CANONICAL | Feature inventory with status/surface/code locations (293 lines) |
| `Docs/Architecture/CODEBASE_MAP.md` | KEEP_CANONICAL | Package targets, directories, execution paths for contributors (185 lines) |
| `Docs/Architecture/ARCHITECTURE_DETAILED.md` | MERGE | 1742-line omnibus overlapping ARCHITECTURE + WHY_* + limits |
| `Docs/Architecture/BLAZEDB_ARCHITECTURE_AND_LIMITS.md` | MERGE | 1208-line limits/architecture overlap |
| `Docs/Architecture/BLAZEDB_SYSTEM_DESIGN_DIAGRAM.md` | MERGE | 960-line design diagram narrative |
| `Docs/Architecture/ARCHITECTURE_COMPARISON.md` | MERGE | Comparison essay vs other DBs |
| `Docs/WHY_EACH_PART_EXISTS.md` | KEEP_REFERENCE | Rationale deep-dive; distinct purpose from maps |
| `Docs/Architecture/TOURS/*` | KEEP_REFERENCE | Symbol-level walkthroughs; complementary |

### Roadmap / planning stubs

**Strongest canonical:** `ROADMAP.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `ROADMAP.md` | KEEP_CANONICAL | Root roadmap |
| `Docs/Product/ROADMAP_BACKLOG.md` | KEEP_REFERENCE | Backlog detail linked from Docs/README maintainer section |
| `Docs/GettingStarted/FEATURE_ROADMAP.md` | MERGE | 8-line stub |
| `Docs/Project/OPTIMIZATION_ROADMAP.md` | MERGE | 8-line stub |
| `Docs/Status/PRODUCTION_READINESS_ROADMAP.md` | ARCHIVE | 8-line stub; completed framing |
| `Docs/Archive/Roadmaps/*` | ARCHIVE | Already archived roadmaps |

### Performance narratives

**Strongest canonical:** `Docs/Performance/PERFORMANCE.md + Docs/Benchmarks/`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/Performance/PERFORMANCE.md` | KEEP_CANONICAL | Performance hub |
| `Docs/Benchmarks/*` | KEEP_REFERENCE | Measured results + methodology; scripts generate several |
| `Docs/Performance/{ULTRA_FAST,BANDWIDTH,LATENCY,THROUGHPUT,TCP_*,RLS_*,...}.md` | MERGE | 17 overlapping analysis docs (~6.5k+ lines) |
| `Docs/Archive/*OPTIM*` | ARCHIVE | Already archived optimization essays |

### SQL completion narratives

**Strongest canonical:** `Docs/SQL/README.md + Docs/SQL/SQL_COVERAGE_STATUS.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/SQL/README.md` | KEEP_REFERENCE | SQL index |
| `Docs/SQL/SQL_COVERAGE_STATUS.md` | KEEP_REFERENCE | Coverage status |
| `Docs/SQL/SQL_FEATURES_COMPARISON.md` | KEEP_REFERENCE | Comparison table |
| `Docs/SQL/COMPLETE_SQL_IMPLEMENTATION.md et al.` | MERGE | 5 overlapping complete/final/implementation writeups |

### Security / threat models

**Strongest canonical:** `SECURITY.md (policy) + Docs/Security/SECURITY.md + Docs/Security/THREAT_MODEL.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `SECURITY.md` | KEEP_CANONICAL | Vulnerability reporting policy |
| `Docs/Security/SECURITY.md` | KEEP_CANONICAL | Security architecture |
| `Docs/Security/THREAT_MODEL.md` | KEEP_CANONICAL | Canonical threat model |
| `Docs/Security/BLAZEDB_THREAT_MODEL.md` | MERGE | Longer alternate threat model |
| `Docs/Security/ENCRYPTION_STRATEGY.md` | KEEP_CANONICAL | Encryption design |
| `Docs/Security/*AUDIT*` | ARCHIVE | Planning/checklist snapshots |

### Release docs

**Strongest canonical:** `RELEASE.md + Docs/Release/RELEASE.md + CHANGELOG.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `RELEASE.md` | KEEP_CANONICAL | Current release notes (root; linked from README badge) |
| `Docs/Release/RELEASE.md` | KEEP_REFERENCE | Release process/notes under Docs |
| `CHANGELOG.md` | KEEP_CANONICAL | Changelog |
| `Docs/Release/RELEASE_NOTES_v0.1.*` | KEEP_REFERENCE | Historical version notes |
| `Docs/Release/FINAL_RELEASE_STATUS.md etc.` | ARCHIVE | Completed readiness snapshots |

### Getting started / usage

**Strongest canonical:** `Docs/GettingStarted/README.md + HOW_TO_USE_BLAZEDB.md + Docs/DEVELOPER_GUIDE.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/GettingStarted/README.md` | KEEP_CANONICAL | First-run index |
| `Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md` | KEEP_CANONICAL | Long usage guide |
| `Docs/DEVELOPER_GUIDE.md` | KEEP_CANONICAL | API walkthrough (1324 lines) |
| `Docs/API/COMPLETE_PROJECT_DOCUMENTATION.md` | MERGE | 593-line omnibus overlapping API+developer guides |
| `Docs/Archive/START_HERE.md / DEVELOPER_GUIDE.md` | ARCHIVE | Archived getting-started copies |

### Distributed / sync (deferred)

**Strongest canonical:** `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md + Docs/Sync/README.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` | KEEP_CANONICAL | Authoritative deferral notice |
| `Docs/Sync/*` | KEEP_REFERENCE | Design/context only |
| `Docs/Guides/*SYNC* / CONNECTING / DEVICE_DISCOVERY / QUICK_START_DISTRIBUTED` | KEEP_REFERENCE | Guides; must stay labeled deferred |
| `Docs/Architecture/DISTRIBUTED_* / RELAY / SERVER_CLIENT` | KEEP_REFERENCE | Architecture for deferred surfaces |
| `Docs/Archive/*SYNC* / P2P_* / RAPID_SYNC_*` | ARCHIVE | Already archived sync essays |

### Test reorganization duplicates

**Strongest canonical:** `Docs/Testing/* + Docs/Tests/*`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/Testing/TEST_PLAN.md` | KEEP_REFERENCE | Prefer Docs/ tree |
| `Tests/BlazeDBTests/*.md` | DELETE_CANDIDATE / MERGE | Identical or near-duplicate copies under Tests/ |
| `Docs/Meta/*REORGANIZATION*` | ARCHIVE | Doc-tree reorg meta |
| `Docs/Tests/*REORGANIZATION*` | ARCHIVE | Test-tree reorg meta |

### Audits

**Strongest canonical:** `Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md + Docs/Product/PRODUCT_AUDIT.md`

| Member | Recommendation | Notes |
|--------|----------------|-------|
| `Docs/Audit/POST_AUDIT_FINDINGS_2026_07.md` | KEEP_CANONICAL | Latest engineering findings audit |
| `Docs/Product/*_AUDIT.md` | KEEP_REFERENCE | Product/observer audits linked from Docs/README |
| `Docs/Audit/*.md (other)` | ARCHIVE | Older safety/protocol/linux audits |
| `Docs/README_AUDIT.md` | KEEP_REFERENCE | Onboarding doc authority audit |

---

## 5. Unlinked documents (not reachable from primary entry points)

Total not reachable from primary BFS: **447** of 547.

### 5.1 Still operationally referenced (scripts / CI / source)

| Path | Ops refs (sample) | Recommendation |
|------|-------------------|----------------|
| `BlazeDB/BlazeDB.docc/BlazeDB.md` | `Scripts/strip_markdown_emojis.py` | KEEP_CANONICAL |
| `CONTRIBUTING.md` | `Scripts/strip_markdown_emojis.py` | KEEP_CANONICAL |
| `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md` | `Scripts/generate_benchmark_environment.py`, `Scripts/refresh_benchmark_suite.py` | KEEP_CANONICAL |
| `Docs/Benchmarks/COMPARISON.md` | `Scripts/publish_benchmark_results.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/CONCURRENT_MVCC.md` | `Scripts/run_concurrent_mvcc_comparison.sh` | KEEP_REFERENCE |
| `Docs/Benchmarks/ENERGY.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/FULL_BENCHMARK_SUMMARY.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/GC_BENCHMARKS.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/LATENCY.md` | `Scripts/generate_latency_report.py`, `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/LIMITS.md` | `Scripts/generate_limits_report.py`, `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/OBSERVABILITY_BENCHMARKS.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/POWER_BENCHMARKS.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/RESULTS.md` | `BlazeDBBenchmarks/main.swift`, `Scripts/publish_benchmark_results.py`, `Scripts/refresh_benchmark_suite.py`, `Scripts/run_comparison_benchmarks.sh` | KEEP_CANONICAL |
| `Docs/Benchmarks/RUN_STATUS.md` | `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/Benchmarks/SQLITE_LIMITS_COMPARISON.md` | `Scripts/generate_sqlite_comparison.py`, `Scripts/refresh_benchmark_suite.py` | KEEP_REFERENCE |
| `Docs/COMPATIBILITY.md` | `Scripts/ci-android-cross-compile.sh` | KEEP_CANONICAL |
| `Docs/Compliance/PHASE_1_FREEZE.md` | `Scripts/check-freeze.sh` | KEEP_REFERENCE |
| `Docs/Contributing/ISSUE_GUIDE.md` | `.github/ISSUE_TEMPLATE/config.yml` | KEEP_CANONICAL |
| `Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md` | `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift`, `BlazeDB/Telemetry/TelemetryConfiguration.swift`, `BlazeDB/Utils/PathResolver.swift` | KEEP_CANONICAL |
| `Docs/GettingStarted/KMM_GETTING_STARTED.md` | `Scripts/package-kmm-artifacts.sh` | KEEP_CANONICAL |
| `Docs/GettingStarted/QUERY_PERFORMANCE.md` | `Examples/QuickStart.swift` | KEEP_REFERENCE |
| `Docs/GettingStarted/README.md` | `Examples/HelloBlazeDB/main.swift` | KEEP_CANONICAL |
| `Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md` | `Examples/SwiftUIExample.swift` | KEEP_REFERENCE |
| `Docs/Guides/USAGE_BY_TASK.md` | `Examples/QuickStart.swift` | KEEP_REFERENCE |
| `Docs/Performance/PERFORMANCE.md` | `Scripts/publish_benchmark_results.py` | KEEP_CANONICAL |
| `Docs/Product/PRODUCT_AUDIT.md` | `BlazeDB/Indexing/ExperimentalBPlusTree.swift` | KEEP_REFERENCE |
| `Docs/Security/DATABASE_SESSION_KEY_LIFECYCLE.md` | `Scripts/publish_benchmark_results.py` | KEEP_REFERENCE |
| `Docs/Status/DURABILITY_MODE_SUPPORT.md` | `BlazeDB/Core/BlazeDBManager.swift` | KEEP_CANONICAL |
| `Docs/Testing/CI_AND_TEST_TIERS.md` | `.github/workflows/ci.yml`, `Scripts/ci-apple-cross-compile.sh`, `Scripts/run-tier2-tier3-companions.sh` | KEEP_CANONICAL |
| `Docs/android-status.md` | `Scripts/ci-android-cross-compile.sh` | KEEP_CANONICAL |
| `Examples/C/README.md` | `Examples/C/hello_blazedb.c` | KEEP_REFERENCE |
| `Examples/ReadmeSamples/README.md` | `Examples/ReadmeSamples/main.swift`, `Scripts/check-readme-sample-coverage.sh` | KEEP_REFERENCE |
| `Examples/SYNC_EXAMPLES_INDEX.md` | `Scripts/strip_markdown_emojis.py` | KEEP_REFERENCE |
| `Experiments/README.md` | `BlazeDBCLITests/DeveloperCommandsTests.swift`, `BlazeShell/CLIHelp.swift`, `BlazeShell/DeveloperCommands.swift` | KEEP_REFERENCE |
| `README.md` | `.github/workflows/release.yml`, `BlazeDBCLITests/DeveloperCommandsTests.swift`, `BlazeShell/CLIHelp.swift`, `BlazeShell/DeveloperCommands.swift` | KEEP_CANONICAL |
| `ROADMAP.md` | `.github/ISSUE_TEMPLATE/config.yml`, `BlazeDB/Indexing/ExperimentalBPlusTree.swift` | KEEP_CANONICAL |
| `SECURITY.md` | `.github/ISSUE_TEMPLATE/config.yml` | KEEP_CANONICAL |

### 5.2 Likely useful but undiscoverable from primary nav

These are `KEEP_*` / `MERGE` recommendations among primary-unreachable files (sample of highest-signal paths; full list is in the inventory table with `Reachable from = unlinked`).

| Path | Lines | Notes |
|------|------:|-------|
| `Docs/INTERVIEW_MASTER_LIST.md` | 1813 | Maintainer/interview architecture narrative cluster |
| `Docs/Testing/TEST_ENUMERATION.md` | 1511 | Testing reference |
| `Docs/Sync/SYNC_TOPOLOGY.md` | 1483 | Sync/transport reference (distributed deferred) |
| `Docs/Tools/MCP_SERVER.md` | 1406 | Tool documentation |
| `Docs/WALKTHROUGH_CHECKLIST.md` | 1337 | Maintainer/interview architecture narrative cluster |
| `Docs/Security/P2P_ENCRYPTION.md` | 1140 | Security topic guide |
| `Docs/Testing/TEST_COVERAGE_DOCUMENTATION.md` | 1094 | Testing reference |
| `Docs/WHY_EACH_PART_EXISTS.md` | 983 | Maintainer/interview architecture narrative cluster |
| `Docs/Security/ENCRYPTION_STRATEGY.md` | 912 | Primary navigation or stability/ops contract |
| `Docs/Security/SECURITY_ANALYSIS.md` | 886 | Security topic guide |
| `Docs/Architecture/BLAZEDB_RELAY.md` | 843 | Distributed architecture; mark deferred |
| `Docs/INTERVIEW_PREPARATION.md` | 817 | Maintainer/interview architecture narrative cluster |
| `Docs/Architecture/DISTRIBUTED_ARCHITECTURE.md` | 743 | Distributed architecture; mark deferred |
| `Docs/Guides/CONNECTING_DATABASES_GUIDE.md` | 721 | Distributed/sync guide; note deferred status |
| `Docs/Sync/DISTRIBUTED_SYNC_CLARIFICATION.md` | 701 | Sync deferral/clarification |
| `Docs/superpowers/plans/2026-07-26-blazedb-dev-commands.md` | 669 | Recent design/plan artifacts |
| `Docs/Architecture/BLAZEBINARY_PROTOCOL.md` | 655 | Primary navigation or stability/ops contract |
| `Docs/Security/SECURE_TCP_HANDSHAKE.md` | 633 | Security topic guide |
| `Docs/Guides/DEVICE_DISCOVERY.md` | 615 | Distributed/sync guide; note deferred status |
| `Docs/SQL/SQL_FEATURES_COMPARISON.md` | 609 | SQL status/reference |
| `Docs/Guides/PRODUCTION_DEPLOYMENT.md` | 604 | Primary navigation or stability/ops contract |
| `Docs/Testing/TEST_EXAMPLES_VISUAL_GUIDE.md` | 586 | Testing reference |
| `Docs/Design/SECURE_HANDSHAKE_EXPLAINED.md` | 583 | Design reference |
| `Docs/Guides/MIGRATION_GUIDE.md` | 577 | Primary navigation or stability/ops contract |
| `Docs/Security/SECURITY_AND_APP_STORE_COMPLIANCE.md` | 576 | Security topic guide |
| `Docs/Testing/TEST_PLAN.md` | 499 | Testing reference |
| `Docs/Security/AUTH_TOKEN_MANAGEMENT.md` | 493 | Security topic guide |
| `Docs/Tools/USING_BLAZELOGGER_IN_VISUALIZER.md` | 491 | Tool documentation |
| `Docs/Design/SNAPSHOT_SYNC_DESIGN.md` | 462 | Design reference |
| `Docs/Features/GEOSPATIAL_QUERIES.md` | 447 | Feature guide |
| `Docs/Security/COMPLETE_SHARED_SECRET_GUIDE.md` | 438 | Security topic guide |
| `Docs/Security/THREAT_MODEL.md` | 432 | Primary navigation or stability/ops contract |
| `Docs/Sync/SYNC_TRANSPORT_GUIDE.md` | 431 | Sync/transport reference (distributed deferred) |
| `Docs/Features/ORDERING_INDEX_ADVANCED.md` | 420 | Feature guide |
| `Docs/Tools/BLAZEDBVISUALIZER_DOCUMENTATION.md` | 412 | Tool documentation |
| `Docs/API/GRAPH_QUERY_API.md` | 401 | Graph query API reference |
| `Docs/Features/MATH_OPERATIONS.md` | 376 | Feature guide |
| `Docs/Sync/SYNC_EXAMPLES.md` | 368 | Sync/transport reference (distributed deferred) |
| `Docs/GettingStarted/LINUX_PLATFORM_MODEL.md` | 367 | Positioning/platform guidance |
| `Docs/Features/ROW_LEVEL_SECURITY.md` | 355 | Feature guide |
| `Docs/Architecture/SERVER_CLIENT_ARCHITECTURE.md` | 354 | Distributed architecture; mark deferred |
| `Docs/Features/ORDERING_INDEX.md` | 345 | Feature guide |
| `Docs/Design/COMPRESSION_DESIGN.md` | 341 | Design reference |
| `Docs/Tools/BLAZESHELL_DOCUMENTATION.md` | 329 | Tool documentation |
| `Docs/Design/CLI_DOCTOR_REPORT.md` | 325 | Design reference |
| `Docs/Testing/TEST_RUNNER_DEBUGGING.md` | 318 | Testing reference |
| `Docs/superpowers/specs/2026-07-26-blazedb-dev-commands-design.md` | 314 | Recent design/plan artifacts |
| `Docs/Features/ROW_MANIPULATION.md` | 312 | Feature guide |
| `Docs/Testing/GC_TEST_COVERAGE.md` | 311 | Testing reference |
| `Docs/Guides/RUNNING_IN_SERVERS.md` | 307 | User/contributor guide |
| `Docs/Testing/PRODUCTION_GRADE_TESTING.md` | 305 | Testing reference |
| `Docs/Guides/CLI_REFERENCE.md` | 304 | Primary navigation or stability/ops contract |
| `Docs/Guarantees/SAFETY_MODEL.md` | 303 | Primary navigation or stability/ops contract |
| `Docs/Compliance/PRE_USER_HARDENING.md` | 301 | Compliance/hardening records |
| `Docs/Tools/BLAZESTUDIO_DOCUMENTATION.md` | 290 | Tool documentation |
| `Docs/Guides/CONVENIENCE_API_GUIDE.md` | 288 | User/contributor guide |
| `Docs/Features/MULTI_WORKSPACE_OPTIMIZATION.md` | 268 | Feature guide |
| `Docs/Features/OVERFLOW_PAGES_IMPLEMENTATION.md` | 265 | Feature guide |
| `Docs/Product/NEXT_ENGINEERING_AUDIT.md` | 258 | Product/roadmap audit cluster |
| `Docs/Guides/DEVELOPMENT_PERFORMANCE.md` | 255 | User/contributor guide |

_Showing top 60 by size; 150 total in this bucket._

### 5.3 Archival

Count in ARCHIVE recommendation: **251**.

Largest ARCHIVE clusters:

- `Docs/Archive/**` (already quarantined; 135 files) — keep tree; fix `Docs/ARCHIVE_INDEX.md` basename drift in Batch A.
- `Docs/Audit/**` except `POST_AUDIT_FINDINGS_2026_07.md` and `README.md` — historical audits.
- `Docs/Status/*COMPLETE*`, `*FINAL*`, `*STABILIZATION*`, `*READINESS*` snapshots — completed narratives.
- `Docs/Meta/**` and `Docs/Tests/**` reorganization writeups — completed doc/test moves.
- `Docs/Project/*COMPLETE*`, `FINAL_STATUS`, optimization status banners.
- `Docs/Release/FINAL_*`, `VALIDATION_SUMMARY`, readiness checklists once released.

### 5.4 Deletion candidates

| Path | Canonical destination | Evidence |
|------|----------------------|----------|
| `Docs/Meta/REORGANIZATION_COMPLETE 2.md` | Docs/Meta/REORGANIZATION_COMPLETE.md | Filename has space+"2"; longer sibling of REORGANIZATION_COMPLETE.md — pick one canonical Meta copy then delete other |
| `Tests/BlazeDBTests/CREATE_TEST_PLANS_IN_XCODE.md` | Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md | SHA256-identical to Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md |
| `Tests/BlazeDBTests/FINAL_REORGANIZATION_INSTRUCTIONS.md` | Docs/Tests/FINAL_REORGANIZATION_INSTRUCTIONS.md | Near-duplicate of Docs/Tests copy; completed instructions |
| `Tests/BlazeDBTests/REORGANIZATION_PLAN.md` | Docs/Tests/REORGANIZATION_PLAN.md | Near-duplicate of Docs/Tests copy (67 lines; byte diff trivial); completed reorg plan |
| `Tests/BlazeDBTests/REORGANIZATION_STATUS.md` | Docs/Tests/REORGANIZATION_STATUS.md | SHA256-identical to Docs/Tests/REORGANIZATION_STATUS.md; zero unique content |
| `Tests/BlazeDBTests/TEST_PLAN.md` | Docs/Testing/TEST_PLAN.md | Near-duplicate of Docs/Testing/TEST_PLAN.md (499 lines; trivial byte diff) |

### 5.5 Uncertain (`REVIEW_REQUIRED`)

| Path | Lines | Evidence |
|------|------:|----------|
| `Docs/GC/GC_ENHANCEMENTS_NEEDED.md` | 418 | Large TODO list; may contain still-open GC work — do not archive until checked against code/issues |
| `Docs/GC/GC_TODO_CRITICAL.md` | 651 | Critical GC TODO narrative; verify open items before ARCHIVE |

---

## 6. Proposed cleanup batches

Each batch is independently reviewable. **Do not execute until explicitly approved.**

### Batch A — Navigation / index fixes only

- Fix broken sibling-relative links (cite exact sources):
  - `Docs/Architecture/ARCHITECTURE.md` → `PROTOCOL.md`, `TRANSACTIONS.md`, `SECURITY.md` (should target `Docs/Design/PROTOCOL.md`, `Docs/Features/TRANSACTIONS.md`, `Docs/Security/SECURITY.md`).
  - `Docs/Security/SECURITY.md` → `ARCHITECTURE.md`, `PROTOCOL.md`.
  - `Docs/Security/README.md` → `../SECURITY.md` (resolves to missing `Docs/SECURITY.md`; should be `../../SECURITY.md`).
  - `Docs/Features/TRANSACTIONS.md` → `ARCHITECTURE.md`, `PERFORMANCE.md`.
  - `Docs/Design/PROTOCOL.md` → `ARCHITECTURE.md`.
  - `Docs/Performance/PERFORMANCE.md` → `ARCHITECTURE.md`, `TRANSACTIONS.md`.
- Fix `.github/pull_request_template.md` links that resolve under `.github/` instead of repo root.
- Update `Docs/Audit/README.md` to feature `POST_AUDIT_FINDINGS_2026_07.md` as current.
- Add a banner to `Docs/MASTER_DOCUMENTATION_INDEX.md`: not public authority; sync section is deferred (`DISTRIBUTED_TRANSPORT_DEFERRED.md`).
- Repair `Docs/ARCHIVE_INDEX.md` entries to real paths under `Docs/Archive/` / current homes (many are bare basenames).
- Confirm `Docs/Architecture/TOURS/README.md` remains linked from `Docs/Architecture/README.md` / CONTRIBUTING path.

### Batch B — Archive completed audits / plans

- Move (git mv) into `Docs/Archive/Audits/` or `Docs/Archive/Status/` without content edits:
  - Most of `Docs/Audit/*` except `README.md`, `POST_AUDIT_FINDINGS_2026_07.md`, and this inventory.
  - `Docs/Status/` files matching `*COMPLETE*`, `*FINAL*`, `*STABILIZATION*`, `*FIXED*`, `PRODUCTION_READINESS_*` (keep the KEEP_REFERENCE status docs listed in §7).
  - `Docs/Project/` completion banners (`100_PERCENT_COMPLETE.md`, `FINAL_STATUS.md`, `COMPLETION_STATUS.md`, …).
  - `Docs/Meta/*REORGANIZATION*` and `Docs/Tests/*REORGANIZATION*` after Batch A index updates.
- Update `Docs/Archive/README.md` + `Docs/ARCHIVE_INDEX.md` pointers only.

### Batch C — Merge obvious duplicates

- Performance: fold unique measured claims from the 17 `Docs/Performance/*` MERGE docs into `PERFORMANCE.md` / Benchmarks; then archive sources.
- SQL: fold unique coverage claims from five `SQL_*COMPLETE*` / `IMPLEMENTATION*` docs into `SQL_COVERAGE_STATUS.md`.
- Architecture: extract unique diagrams/limits from `ARCHITECTURE_DETAILED.md`, `BLAZEDB_ARCHITECTURE_AND_LIMITS.md`, `BLAZEDB_SYSTEM_DESIGN_DIAGRAM.md` into `ARCHITECTURE.md` / `SYSTEM_MAP.md`; archive remainder.
- Threat models: merge `BLAZEDB_THREAT_MODEL.md` unique controls into `THREAT_MODEL.md`.
- API omnibus: extract unique API tables from `COMPLETE_PROJECT_DOCUMENTATION.md` into `API_REFERENCE.md`.
- Roadmap stubs: replace 8-line `FEATURE_ROADMAP.md` / `OPTIMIZATION_ROADMAP.md` with links to `ROADMAP.md`.
- Resolve `Tests/BlazeDBTests/TEST_REORGANIZATION_PROPOSAL.md` vs `Docs/Testing/` copy (DIFFER sizes) before deleting.

### Batch D — Delete only proven-empty or fully superseded documents

Only after checksum confirmation in a PR checklist:

- `Tests/BlazeDBTests/REORGANIZATION_STATUS.md` (identical to `Docs/Tests/REORGANIZATION_STATUS.md`).
- `Tests/BlazeDBTests/CREATE_TEST_PLANS_IN_XCODE.md` (identical to `Docs/Testing/CREATE_TEST_PLANS_IN_XCODE.md`).
- Near-identical Tests/ copies of `REORGANIZATION_PLAN.md`, `FINAL_REORGANIZATION_INSTRUCTIONS.md`, `TEST_PLAN.md` after diff review.
- `Docs/Meta/REORGANIZATION_COMPLETE 2.md` after choosing the canonical Meta file.

**Do not** delete Archive contents in Batch D; archiving is Batch B.

### Batch E — Remaining manual review

- `Docs/GC/GC_TODO_CRITICAL.md` and `GC_ENHANCEMENTS_NEEDED.md` vs current GC code/issues.
- Android/KMM docs currency: `Docs/android-status.md`, `KMM_GETTING_STARTED.md`, Examples android READMEs vs CI scripts.
- Whether `Docs/API/COMPLETE_PROJECT_DOCUMENTATION.md` retains any non-API project claims worth keeping.
- Interview/walkthrough cluster (`INTERVIEW_*`, `WALKTHROUGH_CHECKLIST`, `WHY_EACH_PART_EXISTS`) — keep vs move under Internal.
- `README_HOMEBREW_TAP.md` discoverability from `RELEASE.md`.
- Superpowers plan/spec under `Docs/superpowers/` — retain as session artifacts or move to Internal.

---

## 7. Safety constraints

**Do not remove or gut without manual approval** (API/compat/security/ops):

| Document | Why |
|----------|-----|
| `Docs/API_STABILITY.md` | API stability contract |
| `Docs/COMPATIBILITY.md` | Compatibility matrix / platform tiers |
| `Docs/MIGRATION.md` | Migration entry point |
| `Docs/Guides/MIGRATION_GUIDE.md` | Migration guide |
| `Docs/Migration/WORKSPACE_PROJECTROOT_MIGRATION.md` | Workspace path migration |
| `Docs/Status/LEGACY_LAYOUT_MIGRATION_GUIDANCE.md` | Legacy layout migration |
| `Docs/Architecture/STORAGE_ENGINE_NOTES.md` | Storage-format / engine notes |
| `Docs/Architecture/BLAZEBINARY_PROTOCOL.md` | On-disk/protocol codec documentation |
| `Docs/Security/SECURITY.md` | Security architecture |
| `Docs/Security/ENCRYPTION_STRATEGY.md` | Encryption design |
| `Docs/Security/THREAT_MODEL.md` | Threat model |
| `Docs/Security/DATABASE_SESSION_KEY_LIFECYCLE.md` | Key lifecycle |
| `Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md` | Key management contract |
| `SECURITY.md` | Vulnerability reporting policy |
| `Docs/Architecture/C_ABI_BYTE_KV.md` | C ABI contract |
| `BlazeDBC/README.md` | C library package README |
| `RELEASE.md` | Current release notes |
| `Docs/Release/RELEASE.md` | Release procedure/notes |
| `CHANGELOG.md` | Changelog |
| `Docs/Testing/CI_AND_TEST_TIERS.md` | CI/test tiers referenced by workflows/scripts |
| `Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md` | Storage change gate (PR template) |
| `Docs/Contributing/OSS_CORE_BUILD_EXCLUDES.md` | Build exclude policy |
| `Docs/Status/DURABILITY_MODE_SUPPORT.md` | Durability/recovery guarantees |
| `Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md` | Deferred sync authority |
| `Docs/Guarantees/SAFETY_MODEL.md` | Safety model |
| `Docs/Benchmarks/BENCHMARK_ENVIRONMENT.md` | Generated/used by benchmark scripts |
| `Docs/Benchmarks/RESULTS.md` | Benchmark results sink |
| `Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md` | Referenced from PathResolver/source comments |
| `Docs/GettingStarted/KMM_GETTING_STARTED.md` | Referenced by package-kmm script |
| `Docs/Compliance/PHASE_1_FREEZE.md` | Referenced by Scripts/check-freeze.sh |
| `CONTRIBUTING.md` | Contributor contract |
| `Docs/SUPPORT_POLICY.md` | Support boundaries |

Additional constraints:

- Do not treat “unlinked” as “deletable.”
- Do not infer obsolescence from age alone.
- Do not rewrite git history.
- Prefer `git mv` into `Docs/Archive/` over deletion for completed narratives.
- When merging, preserve unique headings/tables cited in evidence notes; archive the source file rather than deleting until a follow-up pass confirms no loss.
- Distributed/sync docs may be archived or demoted but must not be deleted until `DISTRIBUTED_TRANSPORT_DEFERRED.md` and `Package.swift` staging story are reviewed together.

---

## 8. Broken local links (inventory)

### 8.1 Missing file targets (71)

| Source | Link href | Resolved path |
|--------|-----------|---------------|
| `.github/pull_request_template.md` | `CONTRIBUTING.md#pr-expectations` | `.github/CONTRIBUTING.md` |
| `.github/pull_request_template.md` | `Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md` | `.github/Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md` |
| `Docs/API/GRAPH_QUERY_API.md` | `AGGREGATION_API.md` | `Docs/API/AGGREGATION_API.md` |
| `Docs/API/GRAPH_QUERY_API.md` | `QUERY_BUILDER_API.md` | `Docs/API/QUERY_BUILDER_API.md` |
| `Docs/API/GRAPH_QUERY_API.md` | `SWIFTUI_INTEGRATION.md` | `Docs/API/SWIFTUI_INTEGRATION.md` |
| `Docs/Architecture/ARCHITECTURE.md` | `PROTOCOL.md` | `Docs/Architecture/PROTOCOL.md` |
| `Docs/Architecture/ARCHITECTURE.md` | `SECURITY.md` | `Docs/Architecture/SECURITY.md` |
| `Docs/Architecture/ARCHITECTURE.md` | `TRANSACTIONS.md` | `Docs/Architecture/TRANSACTIONS.md` |
| `Docs/Archive/6_GARBAGE_COLLECTION_GUIDE.md` | `../BlazeDB/Storage/PageReuseGC.swift` | `Docs/BlazeDB/Storage/PageReuseGC.swift` |
| `Docs/Archive/6_GARBAGE_COLLECTION_GUIDE.md` | `Docs/GARBAGE_COLLECTION_COMPLETE_FINAL.md` | `Docs/Archive/Docs/GARBAGE_COLLECTION_COMPLETE_FINAL.md` |
| `Docs/Archive/7_FOREIGN_KEYS_GUIDE.md` | `4_SCHEMA_VALIDATION.md` | `Docs/Archive/4_SCHEMA_VALIDATION.md` |
| `Docs/Archive/9_SWIFTUI_TYPE_SAFETY.md` | `../Examples/CodableExample.swift` | `Docs/Examples/CodableExample.swift` |
| `Docs/Archive/9_SWIFTUI_TYPE_SAFETY.md` | `../Examples/SwiftUIExample.swift` | `Docs/Examples/SwiftUIExample.swift` |
| `Docs/Archive/9_SWIFTUI_TYPE_SAFETY.md` | `../Examples/TypeSafeUsageExample.swift` | `Docs/Examples/TypeSafeUsageExample.swift` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `10_API_REFERENCE.md` | `Docs/Archive/10_API_REFERENCE.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `1_GETTING_STARTED.md` | `Docs/Archive/1_GETTING_STARTED.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `2_CORE_FEATURES.md` | `Docs/Archive/2_CORE_FEATURES.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `3_QUERY_GUIDE.md` | `Docs/Archive/3_QUERY_GUIDE.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `4_SCHEMA_VALIDATION.md` | `Docs/Archive/4_SCHEMA_VALIDATION.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `5_TELEMETRY_GUIDE.md` | `Docs/Archive/5_TELEMETRY_GUIDE.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `BLAZEBINARY_EXPERT_GUIDE.md` | `Docs/Archive/BLAZEBINARY_EXPERT_GUIDE.md` |
| `Docs/Archive/BLAZEDB_V3_FINAL_COMPLETE.md` | `BLAZEBINARY_MASTERCLASS.md` | `Docs/Archive/BLAZEBINARY_MASTERCLASS.md` |
| `Docs/Archive/START_HERE.md` | `../Examples/` | `Docs/Examples` |
| `Docs/Archive/START_HERE.md` | `../Examples/AshPileDebugMenu.swift` | `Docs/Examples/AshPileDebugMenu.swift` |
| `Docs/Archive/START_HERE.md` | `../Examples/BasicUsageExample.swift` | `Docs/Examples/BasicUsageExample.swift` |
| `Docs/Archive/START_HERE.md` | `../Examples/QueryBuilderExample.swift` | `Docs/Examples/QueryBuilderExample.swift` |
| `Docs/Archive/START_HERE.md` | `../Examples/README.md` | `Docs/Examples/README.md` |
| `Docs/Archive/START_HERE.md` | `../Examples/TelemetryBasicExample.swift` | `Docs/Examples/TelemetryBasicExample.swift` |
| `Docs/Archive/START_HERE.md` | `10_API_REFERENCE.md` | `Docs/Archive/10_API_REFERENCE.md` |
| `Docs/Archive/START_HERE.md` | `1_GETTING_STARTED.md` | `Docs/Archive/1_GETTING_STARTED.md` |
| `Docs/Archive/START_HERE.md` | `2_CORE_FEATURES.md` | `Docs/Archive/2_CORE_FEATURES.md` |
| `Docs/Archive/START_HERE.md` | `3_QUERY_GUIDE.md` | `Docs/Archive/3_QUERY_GUIDE.md` |
| `Docs/Archive/START_HERE.md` | `5_TELEMETRY_GUIDE.md` | `Docs/Archive/5_TELEMETRY_GUIDE.md` |
| `Docs/Archive/START_HERE.md` | `MASTER_DOCUMENTATION_V3.md` | `Docs/Archive/MASTER_DOCUMENTATION_V3.md` |
| `Docs/Audit/SECURITY_LINUX.md` | `Docs/ARCHITECTURE.md` | `Docs/Audit/Docs/ARCHITECTURE.md` |
| `Docs/Audit/SECURITY_LINUX.md` | `Docs/SECURITY.md` | `Docs/Audit/Docs/SECURITY.md` |
| `Docs/Design/PROTOCOL.md` | `ARCHITECTURE.md` | `Docs/Design/ARCHITECTURE.md` |
| `Docs/Design/PROTOCOL.md` | `ARCHITECTURE.md#network-layer` | `Docs/Design/ARCHITECTURE.md` |
| `Docs/Features/MATH_OPERATIONS.md` | `../SQL/AGGREGATIONS.md` | `Docs/SQL/AGGREGATIONS.md` |
| `Docs/Features/MATH_OPERATIONS.md` | `../SQL/WINDOW_FUNCTIONS.md` | `Docs/SQL/WINDOW_FUNCTIONS.md` |
| `Docs/Features/ROW_LEVEL_SECURITY.md` | `API/GRAPH_QUERY_API.md` | `Docs/Features/API/GRAPH_QUERY_API.md` |
| `Docs/Features/ROW_LEVEL_SECURITY.md` | `API/QUERY_BUILDER_API.md` | `Docs/Features/API/QUERY_BUILDER_API.md` |
| `Docs/Features/ROW_LEVEL_SECURITY.md` | `Security/` | `Docs/Features/Security` |
| `Docs/Features/ROW_MANIPULATION.md` | `../SQL/WINDOW_FUNCTIONS.md` | `Docs/SQL/WINDOW_FUNCTIONS.md` |
| `Docs/Features/TRANSACTIONS.md` | `ARCHITECTURE.md` | `Docs/Features/ARCHITECTURE.md` |
| `Docs/Features/TRANSACTIONS.md` | `PERFORMANCE.md` | `Docs/Features/PERFORMANCE.md` |
| `Docs/Guides/MIGRATION_GUIDE.md` | `../Examples/QUERY_EXAMPLES.md` | `Docs/Examples/QUERY_EXAMPLES.md` |
| `Docs/Guides/MIGRATION_GUIDE.md` | `../Performance/PERFORMANCE_GUIDE.md` | `Docs/Performance/PERFORMANCE_GUIDE.md` |
| `Docs/Guides/MIGRATION_GUIDE.md` | `../Sync/SYNC_GUIDE.md` | `Docs/Sync/SYNC_GUIDE.md` |
| `Docs/Guides/PRODUCTION_DEPLOYMENT.md` | `../Performance/PERFORMANCE_GUIDE.md` | `Docs/Performance/PERFORMANCE_GUIDE.md` |
| `Docs/Guides/PRODUCTION_DEPLOYMENT.md` | `../Sync/SYNC_GUIDE.md` | `Docs/Sync/SYNC_GUIDE.md` |
| `Docs/INTERVIEW_MASTER_LIST.md` | `INTERVIEW_PREPARATION.md:28-73` | `Docs/INTERVIEW_PREPARATION.md:28-73` |
| `Docs/INTERVIEW_MASTER_LIST.md` | `WALKTHROUGH_CHECKLIST.md:48-210` | `Docs/WALKTHROUGH_CHECKLIST.md:48-210` |
| `Docs/INTERVIEW_MASTER_LIST.md` | `WHY_EACH_PART_EXISTS.md:700-800` | `Docs/WHY_EACH_PART_EXISTS.md:700-800` |
| `Docs/Performance/PERFORMANCE.md` | `ARCHITECTURE.md` | `Docs/Performance/ARCHITECTURE.md` |
| `Docs/Performance/PERFORMANCE.md` | `TRANSACTIONS.md` | `Docs/Performance/TRANSACTIONS.md` |
| `Docs/Performance/QUERY_OPTIMIZATIONS.md` | `API/QUERY_BUILDER_API.md` | `Docs/Performance/API/QUERY_BUILDER_API.md` |
| `Docs/Performance/QUERY_OPTIMIZATIONS.md` | `Project/PERFORMANCE_METRICS.md` | `Docs/Performance/Project/PERFORMANCE_METRICS.md` |
| `Docs/Performance/RLS_OPTIMIZATION.md` | `../ROW_LEVEL_SECURITY.md` | `Docs/ROW_LEVEL_SECURITY.md` |
| `Docs/Performance/RLS_OPTIMIZATION.md` | `PERFORMANCE_METRICS.md` | `Docs/Performance/PERFORMANCE_METRICS.md` |
| `Docs/Security/README.md` | `../SECURITY.md` | `Docs/SECURITY.md` |
| `Docs/Security/SECURITY.md` | `ARCHITECTURE.md` | `Docs/Security/ARCHITECTURE.md` |
| `Docs/Security/SECURITY.md` | `PROTOCOL.md` | `Docs/Security/PROTOCOL.md` |
| `Docs/Tools/MCP_SERVER.md` | `../ROW_LEVEL_SECURITY.md` | `Docs/ROW_LEVEL_SECURITY.md` |

### 8.2 Missing / unmatched anchors

Heading-slug checker initially reported 17 raw hits. Three are **valid HTML anchors** on `README.md` (`start-here-new-users`, `try-blazedb-from-this-repo`) and are **not broken**. True missing anchors: **13**, mostly stale Example deep-links into older README section ids.

| Source | Link | Target | Anchor | Notes |
|--------|------|--------|--------|-------|
| `Docs/GettingStarted/README.md` | `../../README.md#start-here-new-users` | `README.md` | `start-here-new-users` | OK via HTML id (false positive) |
| `Examples/ReadmeSamples/README.md` | `../../README.md#start-here-new-users` | `README.md` | `start-here-new-users` | OK via HTML id (false positive) |
| `Examples/ReadmeSamples/README.md` | `../../README.md#try-blazedb-from-this-repo` | `README.md` | `try-blazedb-from-this-repo` | OK via HTML id (false positive) |
| `Examples/Go/README.md` | `../../README.md#go-integration-preview` | `README.md` | `go-integration-preview` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#add-blazedb-to-your-app` | `README.md` | `add-blazedb-to-your-app` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#default-api-recommended` | `README.md` | `default-api-recommended` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#direct-crud-secondary` | `README.md` | `direct-crud-secondary` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#example-lists-and-list-items` | `README.md` | `example-lists-and-list-items` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#opening-a-database` | `README.md` | `opening-a-database` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#raw-api-advanced` | `README.md` | `raw-api-advanced` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#swiftui-query-wappers-apple-platforms-only` | `README.md` | `swiftui-query-wappers-apple-platforms-only` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#transactions` | `README.md` | `transactions` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#two-typed-protocols` | `README.md` | `two-typed-protocols` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#typedstore` | `README.md` | `typedstore` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#utilities` | `README.md` | `utilities` | missing |
| `Examples/ReadmeSamples/README.md` | `../../README.md#which-api-should-i-use` | `README.md` | `which-api-should-i-use` | missing |

---

## 9. Validation notes

- Scope limited to **git-tracked** `*.md` files (547).
- Link checker resolves relative paths case-sensitively; reports missing files and anchors.
- Inbound “ops” references searched Swift/shell/YAML/JSON/Python/etc., excluding observer audit export text dumps that list every doc path.
- Classification is conservative: uncertain items are `REVIEW_REQUIRED`, not `DELETE_CANDIDATE`.
- This file is the only new audit artifact from this pass.

---

## 10. Session totals (print block)

```
files_inspected:              547
files_reachable_primary:     100
files_unreferenced_primary:  447
broken_local_file_links:     71
broken_anchors:              13 (plus 3 README HTML-id false positives)
KEEP_CANONICAL:              69
KEEP_REFERENCE:              188
MERGE:                       31
ARCHIVE:                     251
DELETE_CANDIDATE:            6
REVIEW_REQUIRED:             2
```

### Five safest cleanup actions

1. Batch A: Fix broken relative links in Docs/Architecture/ARCHITECTURE.md, Docs/Security/SECURITY.md, Docs/Features/TRANSACTIONS.md, and Docs/Security/README.md (point to real canonical paths).
2. Batch A: Update Docs/Audit/README.md to list POST_AUDIT_FINDINGS_2026_07.md as current; demote MASTER_DOCUMENTATION_INDEX sync section as deferred.
3. Batch D: Delete Tests/BlazeDBTests/REORGANIZATION_STATUS.md and CREATE_TEST_PLANS_IN_XCODE.md after confirming SHA256 identity with Docs/ copies.
4. Batch D: Delete or rename Docs/Meta/REORGANIZATION_COMPLETE 2.md after choosing one Meta canonical file.
5. Batch B: Move completed Docs/Status/*COMPLETE* / *FINAL* / *STABILIZATION* snapshots into Docs/Archive/Status/ without rewriting content.

### Five highest-risk documentation areas

1. Docs/Security/* and encryption/key-lifecycle docs — incorrect merge/delete can erase security contracts.
2. Docs/Architecture/C_ABI_BYTE_KV.md and BlazeBinary/storage docs — ABI/on-disk compatibility.
3. Docs/Status/DURABILITY_MODE_SUPPORT.md + recovery/WAL docs — correctness guarantees.
4. Distributed/sync corpus (Docs/Sync, Guides, Architecture DISTRIBUTED_*) — easy to accidentally present deferred features as shipped.
5. Docs/SYSTEM_MAP.md vs CODEBASE_MAP vs ARCHITECTURE_DETAILED — large unique inventories; naive merge loses status tables.

---

**Stop.** No cleanup batches implemented. Approve Batch A/B/C/D/E explicitly to proceed.
