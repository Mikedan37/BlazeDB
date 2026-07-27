# Next engineering audit

**Date:** 2026-07-26  
**Base commit:** `1760fb8d`  
**Method:** Seven parallel investigation agents + code verification.  
**Rules (original pass):** No speculative issue flood; evidence-first.  
**Rules (filing update 2026-07-26):** Cap removed. File every proven, supported, independently actionable defect. Hypotheses / experimental / duplicates stay here.

Known tracked work (#258–#299, especially #276–#283, #291, #295–#299) is treated as **already owned** where applicable.

Related: [ISSUE_TRACKER_AUDIT](ISSUE_TRACKER_AUDIT.md) · [ISSUE_CODE_INDEX](../Contributing/ISSUE_CODE_INDEX.md) · [CODEBASE_MAP](../Architecture/CODEBASE_MAP.md) · [ROADMAP](../../ROADMAP.md)

---

## Executive summary

BlazeDB’s hottest write/open/query defects are already ticketed. The audit’s value is elsewhere:

1. **New proven correctness hazards** around `close()` vs writers, `vacuum()` vs live I/O, and soft-delete / count contract lies.
2. **Latency gaps** that `#291` does not yet measure: `beginTransaction` O(N) snapshot + full-file backup, `deletePage` per-page fsync, Linux `insertMany` fallback, meta fsync under-count.
3. **Memory/lifecycle map**: unbounded/orphan caches (`QueryCache`, `RecordCache.forDatabase`, performance/async static maps) and O(DB) APIs.
4. **Coverage holes** that leave #277 and concurrent close/vacuum untested in PR gates.
5. **Feature asks** that stay in audit/backlog until designed (FFI handle generation, CLI argv secrets, Linux `.so`).

**Discipline is evidence quality, not issue-count cosmetics.** Speculative umbrellas and unsupported surfaces stay in this audit / roadmap.

---

## Proven high-risk findings (new)

| ID | Finding | Paths / symbols | Evidence | Related tracked |
|----|---------|-----------------|----------|-----------------|
| C-NEW-1 | `vacuum()` runs under `collection.queue` barrier, calls `store.close()`, then swaps `self.collection` — waiters can resume on closed FD; no `writeLock` / active-txn guard | `BlazeDB/Storage/VacuumCompaction.swift` `vacuum()` | Proven | none (distinct from #277) |
| C-NEW-2 | `close()` does not hold `writeLock` across teardown; `_isClosed` set **after** `collection.close()` — concurrent writers can pass `ensureNotClosed` then I/O on closed store | `BlazeDBClient+Lifecycle.close`, `performSafeWrite` | Proven | LifecycleTests are sequential only |
| C-NEW-3 | Soft-delete docstring claims “Can still fetch … isDeleted = true”; public `fetch`/`fetchAll`/`count` hide tombstones | `BlazeDBClient.softDelete` docs vs `fetchAll` filter | Proven | none |
| C-NEW-4 | Dual counters: `count()` = `fetchAll().count` (slow, excludes soft-deleted); `getRecordCount()` / `stats()` = `indexMap.count` (includes soft-deleted) | `count()`, `BlazeDBClient+Monitoring.getRecordCount` | Proven | not #268 |
| C-NEW-5 | BlazeDBC `blazedb_close` = `takeRetainedValue` with no generation — double-close / use-after-close = UB | `BlazeDBC/BlazeDBC.swift` | Proven | N7 unfiled; pairs #267 |

**Already tracked P0 (do not re-file):** #277, #278, #279, #281, #283.

---

## Performance investigations

| ID | Finding | Evidence | Missing measurement | Related |
|----|---------|----------|---------------------|---------|
| P-NEW-1 | `beginTransaction` builds full `transactionRecordSnapshot` (every record) + full-file backups | Proven | Stage split in write_profile; RSS vs N | near #276/#291/#277 |
| P-NEW-2 | `PageStore.deletePage` fsyncs every page; batch delete still loops it | Proven | deleteBatch fsync matrix | not #284 |
| P-NEW-3 | Linux `insertMany` / `deleteMany(ids:)` fall back to N individual ops (`#if BLAZEDB_LINUX_CORE`) | Proven | Linux write_profile | near #51 |
| P-NEW-4 | Meta `synchronizeFile` not counted in write-profile fsync totals | Proven | external fs_usage/strace | #291 |
| P-NEW-5 | `updateMany` / `deleteMany(where:)` are per-record durable paths, not `updateBatch`/`deleteBatch` | Proven | fsync vs M | #278/#284 adjacent |
| P-NEW-6 | BlazeDBC put = single insert only | Proven | C put throughput | #265/#267 |

**Rule:** no optimize PR until stage timing owns the wall (#291 first for write path).

---

## Memory / resource investigations

| ID | Finding | Evidence | Note |
|----|---------|----------|------|
| M-NEW-1 | `QueryCache.shared` unbounded; keys lack DB identity | Strongly supported | not a proven leak |
| M-NEW-2 | `RecordCache.removeForDatabase` never called | Strongly supported | registry grows per path |
| M-NEW-3 | `fetchAllCachePerformance` / `AsyncQueryCache` static maps lack close cleanup | Strongly supported | OID reuse risk |
| M-NEW-4 | `beginTransaction` O(DB) RAM + full backup files | Proven | durability contract |
| M-NEW-5 | O(DB) APIs: `fetchAll`, `count()`, `fetchPage`, default query, LiveQuery refresh | Proven | #275/#280 related |

---

## Concurrency findings (new)

| ID | Finding | Severity | Evidence |
|----|---------|----------|----------|
| C-NEW-1 | vacuum vs writers | Critical | Proven |
| C-NEW-2 | close vs writers | High | Proven |
| C-NEW-6 | `rawDump()` iterates `indexMap` with no queue | Medium | Proven |
| C-NEW-7 | PageStore async/mmap static OID maps not cleared on close | Med–High | Strongly supported |
| — | Android bridge close vs use | High | Proven (experimental surface) |

TSAN exists on macOS Tier0 nightly/weekly but **no concurrent close/vacuum/FFI close tests** → unlikely to catch C-NEW-1/2/5 today.

---

## API correctness findings (new)

| ID | Classification | Summary |
|----|----------------|---------|
| A-NEW-1 | Docs/API lie | softDelete visibility comments |
| A-NEW-2 | Contract mismatch | `count` vs `getRecordCount` |
| A-NEW-3 | Behavior hole | upsert/update can resurrect soft-deleted via `collection.fetch` |
| A-NEW-4 | Underspecified | `put([T])` not transactional |
| A-NEW-5 | Undocumented | `close()` rolls back open txn |
| A-NEW-6 | Security/CLI | Doctor/Dump/Info password on argv (N6) |
| A-NEW-7 | Policy split | CLI interactive 12+ vs engine ~8+ |

---

## Feature gaps

### Product gaps (supported product)

Already largely ticketed (#263–#267, #274, durability cluster). Untracked strong ones: FFI handle generation, overflow orphan reclaim test, short CI bench smoke, Linux BlazeDBC `.so` + ABI snapshot.

### Ergonomic

Mostly ticketed (#258–#262, #290, docs honesty).

### Experimental / Not planned

Android/KMM production, distributed default, ceremonial all-Apple runtime CI, compression parity (#43) stays enhancement.

---

## Coverage gaps

| Gap | Detail |
|-----|--------|
| #277 window | Crash after commit persist / before backup clear — **missing** dedicated test |
| Concurrent close / vacuum | No stress regression |
| Compat fixtures | Still skippable (#263) |
| C example | Not in CI (#265) |
| BlazeDBC | Tier1 macOS only; no UAF tests |
| Linux PR | No Tier1 (#51) |
| Perf CI | No threshold lane |
| SecureConnectionTests | Still excluded (#73) |
| Memory metrics | Stripped on `GITHUB_ACTIONS` |

---

## Questions requiring maintainer decisions

1. Soft-delete: hide-from-public-API forever, or restore fetch-of-tombstones? Docs currently contradict code.
2. Should `count()` match `indexMap` (O(1), includes deleted) or stay “visible only” and lose the “fast” claim?
3. Is full-record snapshot on `beginTransaction` load-bearing for rollback, or can rollback use backup files only?
4. Vacuum: fail closed if txn open / writers active, or require exclusive lock API?
5. BlazeDBC: generation handles (ABI-sensitive) now, or after #267?
6. CLI passwords on argv: document-only vs env/prompt-only enforcement?
7. Linux `insertMany` fallback: bug to fix or intentional portability limit to document?
8. QueryCache: disable by default, add max size, or scope keys by DB path?
9. What is explicitly **declined** for vNext: distributed, in-place rekey, iterator C ABI?
10. Release-blocking set: is #277+#278+#279 enough, or must C-NEW-1/2 join?

---

## Proposed sequencing

### Now (release / correctness)

| Action | Evidence | Related | Effort | Risk |
|--------|----------|---------|--------|------|
| Fix or harden #277 with crash-after-commit test | Proven tracked | #277 | M | High |
| Fix #278 / #279 | Proven tracked | #278 #279 | M | High |
| Design+fix vacuum exclusive protocol (C-NEW-1) | Proven new | — | M | Critical |
| Close/write barrier protocol (C-NEW-2) | Proven new | — | M | High |
| Soft-delete + count docs/API decision (A-NEW-1/2) | Proven new | — | S–M | Med |

### Next (measurement + maturity)

| Action | Related | Effort |
|--------|---------|--------|
| Widen #291 matrix: beginTxn snapshot/backup, delete fsync, meta fsync, Linux insertMany | #291 | M |
| #263 / #264 / #265 / #267 | existing | M |
| Cache lifecycle cleanup (M-NEW-1–3) after #280 | #280 | M |
| Contributor GFI docs (#292–#294, #173–#174) | existing | S |

### Later

Linux BlazeDBC `.so`, ABI snapshot, iOS Simulator Tier0, LiveQuery coalesce (#275), platform PBKDF2 (#270), compression (#43).

### Not now

Speculative durability-boundary mega-refactor as separate epic; distributed; “make it like SQLite” feature laundry.

---

## Answers to required audit questions (short)

1. **No trustworthy latency baseline:** BlazeDBC put, Linux insertMany, beginTxn setup, deleteBatch fsync, CLI open.  
2. **Hot paths without stage timing:** beginTxn snapshot/backup, saveLayout/meta fsync, deletePage loop, C put.  
3. **O(DB) allocators:** fetchAll, count(), fetchPage, default query, LiveQuery, beginTxn snapshot.  
4. **Unbounded caches:** QueryCache; static fetchAll/performance/async maps without close eviction.  
5. **Ownership gaps:** BlazeDBC handle generation; RecordCache registry; PageStore async statics.  
6. **Apple vs Linux sync:** insertMany/deleteMany batch vs loop; #283 overflow barrier; Linux Tier1 only nightly.  
7. **Docs ≠ behavior:** softDelete fetch comment; count “fast”; SAFETY_MODEL buffered (#294); QUERY_PLANNER O(log n) (#292).  
8. **Crash-after-success:** #277 window missing.  
9. **Silent success/data drop:** #282; soft-delete upsert resurrection hole.  
10. **Skip-heavy:** compat fixtures (#263); batch timing on CI.  
11. **Not in PR CI:** Linux Tier1, C hello, SecureConnectionTests, threshold benches.  
12. **Advertised incomplete:** indexed query complexity; migrators “shipped” (#287).  
13. **Too-visible experimental:** Experimental B+; Android products in Package.swift.  
14. **Recurring asks:** Go/cgo, BlazeDBC packaging, schema guide, CLI honesty — already ticketed.  
15. **Refactors that collapse classes:** exclusive vacuum/close protocol; cache invalidation centralization — **after** defects.  
16. **Refactors that wait:** durability commit boundary epic until #291+#277.  
17. **Release-blocking set (proposal):** #277, #278, #279, C-NEW-1, C-NEW-2.  
18. **Safe external work:** GFI docs/CLI (#173–174, #258–259, #290, #292–294).  
19. **Maintainer design first:** soft-delete semantics, vacuum exclusivity, BlazeDBC handle gen, #276 amortize.  
20. **Decline:** distributed-as-default, KMM production SDK, ceremony CI without runtime proof.

---

## GitHub filing status (cap removed)

| Candidate | Disposition |
|-----------|-------------|
| Vacuum closed-store resume (C-NEW-1) | **#295** (closed; fixed) |
| close/write TOCTOU (C-NEW-2) | **#296** (closed; fixed) |
| softDelete docs + count/getRecordCount (A-NEW-1/2) | **#297** (`needs design`) |
| BlazeDBC handle UAF / double-close (C-NEW-5) | **#298** |
| rawDump unsynchronized (C-NEW-6) | **#299** |
| Soft-delete upsert resurrection (A-NEW-3) | **#304** |
| Meta fsync undercount (P-NEW-4) | **#305** |
| QueryCache cross-DB keys (M-NEW-1 observable) | **#306** |
| RecordCache close/registry (M-NEW-2) | **#307** |
| PageStore static OID maps (C-NEW-7) | **#308** |
| put([T]) non-atomic (A-NEW-4) | **#309** |
| CLI password argv (A-NEW-6 / N6) | **#310** |
| deletePage per-page fsync (P-NEW-2) | **#311** |
| Linux insertMany silent fallback (P-NEW-3) | **#312** (+ comment on #51) |
| beginTxn O(N) snapshot/backup (P-NEW-1 / M-NEW-4) | **update #291** / near #276 — not a separate bug |
| #277 crash-after-commit test | owned by **#277** |
| BlazeDBC put throughput (P-NEW-6) | **withheld** — needs measurement (#291); not filed |
| Android SessionRegistry race | **withheld** — experimental surface |
| Linux `.so` packaging | **withheld** — unimplemented distribution goal |
| Overflow orphan reclaim test | **ROADMAP_BACKLOG** |
| close() rolls back open txn (A-NEW-5) | **intentional contract** — document only |
| CLI vs engine password policy split (A-NEW-7) | **intentional / design** — not filed as defect |
| “Unbounded cache cleanup” umbrella | **rejected** — filed observable defects only |

**Reject / do not file:** duplicate latency of #276; LiveQuery (#275); fetchAll (#280); index-before-sync (#281); nested sync (#279 closed); RLS fail-open behavior change; BlazeDBC “could be faster” without measurement.

---

## Validation run this audit

| Command | Result |
|---------|--------|
| `git rev-parse HEAD` | `1760fb8d` |
| `./dev help` | OK |
| `./dev tiers` | OK |
| `./dev tests Cache` / `Vacuum` | Cache: 3 matches; Vacuum: no name match |
| `./dev test LifecycleTests` | **6 passed** (sequential only) |
| `swift build -c release --product BlazeDBC` | OK |
| `swift build -c release --product BlazeDB` | OK |
| write_profile bench | **Not re-run** this pass (recently exercised for #269/#291) |
| Tier0 full | **Not run** |
| Instruments / fs_usage / TSAN | **Not run** |

Unverified: deterministic vacuum+insert crash; BlazeDBC double-close crash on this machine; soft-delete upsert resurrection end-to-end (code-path strongly supported).

**Validation explicitly not run this audit:** full Tier0, `BLAZEDB_BENCH_MODE=write_profile`, Thread Sanitizer, Instruments / `fs_usage` / `strace`.

### Linux `insertMany` note

Filed as **#312**; measurement remains under #291; Tier1/CI contract remains #51.

### Filing pass (complete)

First wave: #295–#299. Cap-removed wave: #304–#312. See table above.
