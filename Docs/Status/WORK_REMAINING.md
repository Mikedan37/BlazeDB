# BlazeDB — Work Remaining

**Last updated:** 2026-06-30  
**Purpose:** Single prioritized tracker for open work. Use this for sprint planning and issue filing.  
**Related:** [WHAT_NEXT.md](WHAT_NEXT.md) (adoption philosophy), [OPEN_SOURCE_READINESS_CHECKLIST.md](OPEN_SOURCE_READINESS_CHECKLIST.md) (release gates)

---

## How to use this doc

1. Pick a **sprint** (below) or filter by **area** (Release, Trust, Platform, Engine, CI, Deferred).
2. File GitHub issues from unchecked items; link back here.
3. When an item ships, check it off and note the release or PR in the **Evidence** column.

**Priority key:** P0 = ship blocker / hygiene · P1 = adoption & platform · P2 = engine polish · P3 = deferred / large bets

---

## Sprint 1 — Release hygiene & trust (P0)

Target: make `main` honest and shippable before the next tag.

| Done | ID | Work | Evidence / notes |
|:----:|----|------|------------------|
| [x] | R-01 | Align README release version with latest tag (`v2.7.7`) | README, Getting Started |
| [x] | R-02 | Add CHANGELOG entries for `2.7.7` and `[Unreleased]` on `main` | `CHANGELOG.md` |
| [ ] | R-03 | Cut release tag after `[Unreleased]` items are finalized | Tag + release workflow |
| [ ] | R-04 | Add compatibility fixture for latest stable line (e.g. `v2.7.7` dump) | `Tests/CompatibilityFixtures/` |
| [ ] | R-05 | Confirm Tier0 + Tier1 green in **hosted** CI (OSS checklist item) | `OPEN_SOURCE_READINESS_CHECKLIST.md` §1 |
| [ ] | R-06 | Reconcile stale status docs with current code | Audit gaps doc, `PRODUCTION_READINESS_ROADMAP.md`, `BLAZEDB_GAPS_AND_ISSUES_AUDIT.md` |
| [ ] | R-07 | Document dump signature / legacy-hash behavior in `KNOWN_ISSUES.md` or close with explicit policy | `allowLegacyHashMismatch`, CLI signature messaging |

### Trust blockers (same sprint or immediately after)

| Done | ID | Work | Evidence / notes |
|:----:|----|------|------------------|
| [ ] | T-01 | Complete external security audit (at-rest crypto, metadata integrity, recovery, import/export) | `EXTERNAL_SECURITY_REVIEW_PLAN.md` |
| [ ] | T-02 | Publish audit summary + remediation for any critical/high findings | Release evidence docs |
| [ ] | T-03 | Run BlazeDB in at least one maintainer app for multi-week soak | Real-world validation |
| [ ] | T-04 | Publish reproducible benchmarks vs SQLite (insert, query, memory, file size) | `Docs/Performance/BENCHMARKS.md` (new) |
| [ ] | T-05 | Publish essay: "Why BlazeDB exists (and when you should not use it)" | Blog or `Docs/GettingStarted/` |
| [ ] | T-06 | First external adopter issue or integration (non-maintainer) | GitHub issue / reference app |

---

## Sprint 2 — Android / KMM productization (P1)

Target: move from "integration scaffolding" to a supportable consumer story.

| Done | ID | Work | Evidence / notes |
|:----:|----|------|------------------|
| [x] | A-01 | KMM iOS simulator runtime in PR CI | `iosSimulatorArm64Test` |
| [x] | A-02 | KMM Android emulator runtime in PR CI | `kmm-android-runtime` workflow job |
| [x] | A-03 | `BlazeLiveQuery` in core + architecture doc | #231, `LIVE_QUERY_ARCHITECTURE.md` |
| [x] | A-04 | Typed Todo + Flow sample + getting-started guide | `KMM_GETTING_STARTED.md`, `Examples/android/` |
| [ ] | A-05 | Publish AAR + XCFramework to Maven Central / CocoaPods (or documented private feed) | `package-kmm-artifacts.sh` |
| [ ] | A-06 | Document Android default storage paths; recommend `open(at:password:)` | `DEFAULT_STORAGE_PATHS.md`, android-status |
| [ ] | A-07 | Update product wording when publish story exists ("KMM supported") | README, `android-status.md` |
| [ ] | A-08 | Live query / observation on Android KMM (Flow adapter over JNI) | Optional; CRUD path proven |
| [ ] | A-09 | Official Android app integration support statement (exit "experimental") | `COMPATIBILITY.md`, README |

---

## Sprint 3 — Engine & API polish (P2)

Target: close gaps called out in README limitations and source TODOs.

| Done | ID | Work | Area |
|:----:|----|------|------|
| [ ] | E-01 | Stable public index creation APIs + onboarding example | Indexes |
| [ ] | E-02 | Cost-based query optimizer (or document permanent rule-based scope) | Query |
| [ ] | E-03 | Window functions in `QueryBuilder` | Query |
| [ ] | E-04 | Implement or remove query hints (`USE INDEX`, `FORCE TABLE SCAN`) | Query |
| [ ] | E-05 | Graph query KeyPath support (beyond string field names) | Graph |
| [ ] | E-06 | Vector query specialized index / post-processing path | Query |
| [ ] | E-07 | Direct Codable encoder (no JSON intermediate) | Encoding — `TODO_DIRECT_CODABLE_ENCODER.md` |
| [ ] | E-08 | Wire cache hit rate in stats API | Observability |
| [ ] | E-09 | Proactive `checkIntegrity()` / `repair()` API + CLI hook | Storage |
| [ ] | E-10 | TriggerContext: `rebalanceOrderIndex()` / `updateSearchIndex()` | Triggers |
| [ ] | E-11 | Memory-mapped decryption optimization | Storage — `PageStore+Async.swift` |
| [ ] | E-12 | RLS: document and/or enable default engine enforcement beyond CLI/REPL | Security |
| [ ] | E-13 | JSON/CSV export for migration (beyond `.blazedump`) | Import/export |
| [ ] | E-14 | Clarify single-process vs `flock()` policy in SAFETY_MODEL / README | Docs |

---

## Sprint 4 — CI & test housekeeping (P2)

| Done | ID | Work | Evidence / notes |
|:----:|----|------|------------------|
| [ ] | C-01 | PR4: normalize Tier2/Tier3 companion targets (remove transitional layout) | `PR3_RECLASSIFICATION_MAP.md` |
| [ ] | C-02 | Finish test tree reorganization (`Tests/BlazeDBTests/`) | `REORGANIZATION_STATUS.md` |
| [ ] | C-03 | Split `BlazeDBCoreTests` vs `BlazeDBDistributedTests` | `TEST_COMPILATION_FIXES.md` |
| [ ] | C-04 | visionOS: require success when toolchain supports `xros` (`BLAZEDB_APPLE_REQUIRE_VISIONOS=1`) | `ci-apple-cross-compile.sh` |
| [ ] | C-05 | Deduplicate / reconcile `BlazeDBTests/` vs `Tests/BlazeDBTests/` layouts | Contributor confusion |

---

## Backlog — Deferred & experimental (P3)

**Do not start without explicit scope approval** (`WHAT_NEXT.md` warns against distributed scope creep).

| Done | ID | Work | Blocker / doc |
|:----:|----|------|---------------|
| [ ] | D-01 | Public fetchable `BlazeTransport` dependency (HTTPS, no private SSH) | `DISTRIBUTED_TRANSPORT_DEFERRED.md` |
| [ ] | D-02 | Resolve BlazeFSM pin conflict with BlazeTransport | `BLAZEFSM_PIN_ISSUE.md` |
| [ ] | D-03 | Distributed modules Swift 6 strict concurrency compliance | `COMPATIBILITY.md` |
| [ ] | D-04 | Re-enable `BLAZEDB_DISTRIBUTED_TRANSPORT` + CI coverage | Package.swift gate |
| [ ] | D-05 | Network compression (safe Swift, no stub passthrough) | `TCPRelay+Compression.swift` |
| [ ] | D-06 | Unix domain socket **server** (POSIX, not NWListener) | `UnixDomainSocketRelay.swift` |
| [ ] | D-07 | Snapshot-based initial sync (not op-log-only) | Distributed audit |
| [ ] | D-08 | Windows port | README: planned |
| [ ] | D-09 | Add `BlazeMCP` to `Package.swift` target graph or document permanent exclusion | README tools table |
| [ ] | D-10 | Full distributed checklist (CRDT, WebSocket, E2E, delta sync) | `DISTRIBUTED_ARCHITECTURE.md` |

---

## Issue filing template

Copy into GitHub when creating issues from this tracker:

```markdown
**Tracker ID:** E-01  
**Sprint:** 3 — Engine polish  
**Priority:** P2  

## Problem
(one sentence)

## Acceptance criteria
- [ ] …
- [ ] Tests / docs updated

## References
- Docs/Status/WORK_REMAINING.md
```

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-30 | Initial tracker created from repo audit; R-01/R-02 marked done in same PR |
