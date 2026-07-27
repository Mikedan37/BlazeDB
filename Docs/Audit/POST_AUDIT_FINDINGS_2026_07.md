# Post-Audit Findings (July 2026)

**Status:** Tracking document — not a substitute for GitHub issues.
**Purpose:** Preserve verified audit results without instantly doubling the public open-issue count.
**Audit date:** 2026-07-26 (updated 2026-07-27 with follow-up audits)
**Method:** Read-only subsystem audit against source; deduplicated against all open issues at audit time.

## How to use this document

1. **Promote** an item to a GitHub issue only when it passes the gate below.
2. **Fold** addenda into existing issues as comments (do not open duplicates).
3. **Keep** maintainer-only items here until a maintainer is ready to own them.
4. **Update the Status column** whenever an item changes state.
5. **Close** findings that are investigated and intentionally not pursued — do not leave them looking actionable forever.

### Status values

| Status | Meaning |
|--------|---------|
| `Promoted` | Became a public GitHub issue |
| `Ready for promotion` | Fully formed; backlog pacing only |
| `Planned` | Maintainer intends to own this |
| `Held` | Design/product decision needed before the right fix is clear |
| `Folded` | Incorporated into an existing issue |
| `Needs investigation` | Hypothesis only; one more diagnostic step required |
| `Closed` | Investigated and intentionally not pursued (reason required) |

Terminal states: **Promoted**, **Folded**, **Closed**. Everything else should eventually reach one of those.

### Promotion gate (all five must be yes)

1. Can someone reproduce this from the issue alone?
2. Is the expected behavior unambiguous?
3. Are the affected files and symbols identified?
4. Is there at least one concrete acceptance criterion?
5. Would I happily review a PR that implements only this issue?

If any answer is "no" or "maybe," keep in tracking doc and note what is missing.

### Closed reasons (use one)

`expected behavior` · `acceptable tradeoff` · `obsolete after refactor` · `superseded by #N` · `fixed by #N / commit` · `cannot automate (documented)` · `out of scope`

---

## Continuous Verification Priorities

> Every confirmed correctness defect should either become a permanent regression test or have a documented reason why it cannot be tested automatically.

Organize work around **invariants**, not test types. Invariants survive WAL rewrites and query-engine refactors; the harness implementation may change.

### Crash recovery invariants

- Real process-boundary crash harness in CI (`Tests/CrashRecoveryHarness` / [#322](https://github.com/Mikedan37/BlazeDB/issues/322)).
- Kill at multiple write phases (WAL append, main-page write, metadata save, commit, vacuum swap).
- Verify reopen succeeds and committed state is preserved; uncommitted work is absent.

### Rollback invariants

- Every failed write restores: primary records, secondary indexes, B-tree indexes, `indexMap`, caches, metadata.
- Batch failures leave identical state before and after (see [#323](https://github.com/Mikedan37/BlazeDB/issues/323)).
- `performSafeWrite` rollback must restore the same structures as `rollbackTransaction` (see B21 / B23 below).

### Durability invariants

- Reopen after: vacuum, backup/restore, checkpoint, migration.
- Verify page counts, metadata, KDF salts, and indexes match the pre-operation logical state.
- Checkpoint never truncates WAL without a prior WAL sync (M2).

### Query semantics invariants

- Missing-field comparisons (`notEquals` vs absent field — [#327](https://github.com/Mikedan37/BlazeDB/issues/327)).
- Stable ordering when sort keys tie (B24).
- `count()` consistency across public APIs ([#325](https://github.com/Mikedan37/BlazeDB/issues/325); soft-delete aspects → [#297](https://github.com/Mikedan37/BlazeDB/issues/297)).
- Soft-delete visibility contract ([#297](https://github.com/Mikedan37/BlazeDB/issues/297)).
- LiveQuery decode / delivery behavior (A12).

### Index invariants

- Every index entry points to an existing record.
- Every indexed record appears exactly once under its current key.
- No ghost entries after rollback, failed write, or delete.

### API contract invariants

- Swift, C ABI, Android, and Go expose equivalent semantics where claimed.
- Errors are surfaced consistently (not collapsed to `nil` / `-1` / `[]` without docs).
- Return values and complexity claims match documentation.

---

## Inventory at audit time

Open issues reviewed: **#30, #43, #51, #73, #173, #174, #258–#324** (and peers in audit prompt).
Deduplication prevents: **#283** (Linux overflow barrier), **#297** (soft-delete contract), **#282** (typed bulk silent drop), **#293/#294** (durability/safety docs), **#299** (`rawDump` queue), **#261/#292** (query planner / O(log n) docs).

---

## Contributor-facing (promoted to GitHub)

| ID | Status | Title | Severity | Suitability | Issue |
|----|--------|-------|----------|-------------|-------|
| A5 | Promoted | `updateBatch` has no pre-loop indexMap/secondaryIndexes backup | High | intermediate | [#323](https://github.com/Mikedan37/BlazeDB/issues/323) |
| A7 | Promoted | `insertMany` RLS runs before record normalization | High | good first issue | [#321](https://github.com/Mikedan37/BlazeDB/issues/321) |
| A8 | Promoted | `deleteBatch` omits `clearFetchAllCache()` | High | good first issue | [#320](https://github.com/Mikedan37/BlazeDB/issues/320) |
| A10 | Promoted | Crash-recovery CI does not run real process-boundary harness | High | intermediate | [#322](https://github.com/Mikedan37/BlazeDB/issues/322) |
| A14 | Promoted | Create `~/.blazedb` as `0700` before writing master keyring | Medium | good first issue | [#324](https://github.com/Mikedan37/BlazeDB/issues/324) |
| B25 | Promoted | `count()` loads all records despite claiming not to | Medium | good first issue | [#325](https://github.com/Mikedan37/BlazeDB/issues/325) |
| V2 | Promoted | tests: rollback restores secondary indexes | Medium | good first issue / verification | [#326](https://github.com/Mikedan37/BlazeDB/issues/326) |
| B19 | Promoted | `where(notEquals:)` treats missing field as non-match | High | good first issue | [#327](https://github.com/Mikedan37/BlazeDB/issues/327) |
| V1 | Promoted | tests: vacuum close+reopen durability | Medium | good first issue / verification | [#328](https://github.com/Mikedan37/BlazeDB/issues/328) |
| H1 | Promoted | Docs: `close()` rolls back open transaction | Medium | good first issue | [#329](https://github.com/Mikedan37/BlazeDB/issues/329) |
| H2 | Promoted | Tooling: crypto-change checklist + PR checkbox | Medium | good first issue | [#330](https://github.com/Mikedan37/BlazeDB/issues/330) |
| H3 | Promoted | tests: overflow orphan reclaim invariant | Medium | good first issue / verification | [#331](https://github.com/Mikedan37/BlazeDB/issues/331) |
| F1–F3 | Promoted | Docs: unsupported distributed architecture claims | Medium | good first issue | [#332](https://github.com/Mikedan37/BlazeDB/issues/332) |
| F6 | Promoted | Tooling: benchmark-change checklist | Medium | good first issue | [#333](https://github.com/Mikedan37/BlazeDB/issues/333) |
| RLS-GQ | Promoted | Public GraphQuery APIs bypass client RLS context | High | intermediate | [#334](https://github.com/Mikedan37/BlazeDB/issues/334) |
| RLS-UC | Promoted | `update`/`updateMany` lack post-mutation RLS (WITH CHECK) | High | intermediate | [#335](https://github.com/Mikedan37/BlazeDB/issues/335) |
| RLS-CNT | Promoted | `getRecordCount`/`stats` ignore RLS (side channel) | Medium | intermediate | [#336](https://github.com/Mikedan37/BlazeDB/issues/336) |
| RLS-OBS | Promoted | Filtered ChangeObservation forwards deletes without RLS | Medium | intermediate | [#337](https://github.com/Mikedan37/BlazeDB/issues/337) |

---

## Covered by existing issues (addenda only)

| ID | Status | Finding | Existing issue | Action |
|----|--------|---------|----------------|--------|
| D1 | Folded | Linux overflow `queue.sync` without `.barrier` — rediscovery | [#283](https://github.com/Mikedan37/BlazeDB/issues/283) | No new issue |
| D2 | Folded | Soft-delete docstring claims `fetch` returns tombstones | [#297](https://github.com/Mikedan37/BlazeDB/issues/297) | Comment added 2026-07-26 |
| D3 | Folded | `ARCHITECTURE_DETAILED.md` "WAL fsync before ack" | [#293](https://github.com/Mikedan37/BlazeDB/issues/293) | Comment added 2026-07-26 |
| D4 | Folded | `SAFETY_MODEL.md` "No partial records" omits overflow orphan caveat | [#294](https://github.com/Mikedan37/BlazeDB/issues/294) | Comment added 2026-07-26 |
| D5 | Folded | `Scripts/run_benchmarks.sh` stale XCTest filter names | [#291](https://github.com/Mikedan37/BlazeDB/issues/291) | Comment added 2026-07-26 |
| A18 | Folded | `softDelete` docstring contradicts `fetch` nil behavior | [#297](https://github.com/Mikedan37/BlazeDB/issues/297) | Folded into D2 |
| D6 | Folded | `rawDump()` still reads without `collection.queue` | [#299](https://github.com/Mikedan37/BlazeDB/issues/299) | Confirmed still open; no new issue |
| D7 | Folded | `explain()` never emits `.indexScan` steps | [#292](https://github.com/Mikedan37/BlazeDB/issues/292) | Fold into QUERY_PLANNER honesty |
| D8 | Folded | `getRecordCount()` vs `count()` soft-delete divergence | [#297](https://github.com/Mikedan37/BlazeDB/issues/297) | Count contract decision |
| D9 | Folded | `QUERY_PERFORMANCE.md` blanket O(log n) for all indexed lookups | [#261](https://github.com/Mikedan37/BlazeDB/issues/261) | Qualify hash vs B-tree |

---

## Not-yet-filed contributor candidates

Promote when backlog has capacity. Ordered by decreasing accessibility.

| ID | Status | Title | Severity | Suitability | Notes |
|----|--------|-------|----------|-------------|-------|
| A15 | Ready for promotion | C ABI: document handle thread-safety + embedded-NUL key truncation | Medium | good first issue | `blazedb.h` + `C_ABI_BYTE_KV.md` only |
| B24 | Ready for promotion | Sort ties have no stable secondary key (id tiebreak) | Low | good first issue | `applySorts` returns `false` on full tie; pagination non-deterministic |
| A12 | Ready for promotion | LiveQuery typed decode silently drops rows (`try?`) | High | intermediate | Distinct from #282 |
| V3 | Ready for promotion | tests: upsert TOCTOU `recordExists` → retry-as-update | Medium | intermediate | Continuous verification |
| B26 | Ready for promotion | `upsert` TOCTOU return value / docs ambiguity | Low | good first issue | Docs-only or enum; low risk |
| B27 | Ready for promotion | `page(_:size:)` mutates shared builder under `@unchecked Sendable` | Medium | intermediate | Clone state instead of mutate+defer |
| B28 | Ready for promotion | VACUUM leaves stale `fetchAllCache` entry for old `instanceID` | Low | good first issue | Call `clearFetchAllCache()` before replacing collection |
| B21 | Held | `performSafeWrite` restores `indexMap` but not `secondaryIndexes` | High | intermediate | Bundle with B23 when maintainer ready to review |
| B23 | Held | `performSafeWrite` does not restore `btreeIndexManager` on failure | High | intermediate | Bundle with B21; derived-structure rollback needs careful review |
| A11 | Held | `createIndex(on:)` always rebuilds; indexes soft-deleted rows | Medium | intermediate | Wait on #297 product decision |
| A13 | Held | `deleteMany(where:)` per-id loop; predicate re-entrancy | Medium | intermediate | Needs harness |
| A16 | Held | Android bridge collapses errors to sentinels | Medium | intermediate | Experimental surface |
| A17 | Held | 18 Tier2 suites excluded from Package.swift target | High | needs design | CI governance |
| B20 | Held | `deleteMany(ids:)` RLS check outside write lock (TOCTOU) | High | intermediate | Security-ish; needs careful review |

---

## Maintainer-only (do not promote without maintainer review)

| ID | Status | Title | Severity | Confidence |
|----|--------|-------|----------|------------|
| M2 | Planned | `checkpoint()` clears WAL without `wal.sync()` first | High | Confirmed |
| M1 | Planned | Overflow pages bypass WAL entirely | Critical | Confirmed |
| M3 | Planned | Vacuum / backup-restore drop `kdfSalt` | High | Confirmed |
| M5 | Planned | Legacy v1 meta accepted despite HMAC mismatch | Medium | Confirmed |
| M6 | Planned | Non-constant-time `Data.==` for key-byte compares | Medium | Confirmed |
| M9 | Planned | `beginTransaction` backup/state written before snapshot; partial failure orphans artifacts | High | Strong evidence |
| M10 | Planned | `rollbackTransaction` `saveLayout()` failure leaves memory≠disk | High | Confirmed |
| M11 | Planned | `close()` → `rollbackTransaction()` re-enters `writeLock` (ordering risk) | Medium | Confirmed |
| M4 | Held | Key material never zeroized; process-wide key cache | High | Confirmed |
| M7 | Needs investigation | Vacuum non-atomic remove+move; collection swap concurrency | High | Strong evidence |
| M8 | Held | Unified-mode buffered writes cleared before main fsync succeeds | Medium | Confirmed |
| M12 | Held | `beginTransaction` backup vs snapshot ordering under concurrent writers | Medium | Strong evidence |
| SYNC-AUTH | Held | `BlazeSyncEngine` logs auth failures then still applies ops | Critical | Confirmed — Distributed experimental; promote only if sync is a product path |
| SYNC-RLS | Held | `SyncPolicy.respectRLS` never read by engine | High | Confirmed — same gate as SYNC-AUTH |
| RLS-CTX | Ready for promotion | `setRLSContext` ignores `AccessManager` / inactive users | Medium | Document caller-trusted context **or** bind to AccessManager — product decision |

### Issue quality bar (when promoting)

Write issues as mini design docs that remove accidental difficulty, not as patch scripts:

1. Why it matters
2. Current behavior (with symbols/files)
3. Expected behavior
4. Constraints (what not to do)
5. Acceptance criteria
6. Related issues

Do **not** prescribe exact line edits or a single implementation. Leave real engineering decisions to the contributor (see #302 as a model). Exemplars from this RLS pass: #334–#337.

### Details (selected)

**M2 — `checkpoint()` missing `wal.sync()`** — highest-priority one-line maintainer fix.
**M1 — Overflow WAL** — file after M2.
**M3 — kdfSalt** — vacuum/restore omit salt; compaction already correct.
**M9 / M10** — transaction lifecycle partial-failure windows; need maintainer-owned crash injection.
**M11** — lock ordering; document or inline rollback inside `close()`.

---

## Needs further investigation

| ID | Status | Hypothesis | Missing step |
|----|--------|-----------|--------------|
| U1 | Needs investigation | `deletePage` without WAL — replay resurrection after checkpoint? | Trace write-ordering across checkpoint |
| U2 | Needs investigation | LiveQuery `observerToken` unlocked race | Confirm `handlerLock` coverage |
| U3 | Folded | `updateMany` RLS on delta-only fields / missing WITH CHECK | [#335](https://github.com/Mikedan37/BlazeDB/issues/335) | Promoted 2026-07-27 |
| U4 | Needs investigation | `_updateNoSync` ghost secondary-index key | Confirm survives reopen |
| U5 | Needs investigation | Vacuum `collection` swap vs active readers | Inspect lock vs `performSafeWrite` callers |
| U6 | Needs investigation | Nested `queue.sync` inside barrier via `filterOptimized` | Trace call graph from barrier paths |
| U7 | Needs investigation | Savepoint API docs vs `BlazeDBClient` surface | Confirm forwarding methods exist |

---

## Closed

| ID | Status | Finding | Reason |
|----|--------|---------|--------|
| C1 | Closed | Nested `beginTransaction` partial state | `expected behavior` — throws clearly; check under `writeLock`; no partial state |
| C2 | Closed | `count()` blocking behind `insertBatch` barrier | `acceptable tradeoff` — normal GCD semantics; needs SLA before treating as bug |
| C3 | Closed | Soft-delete-only count divergence as separate issue | `superseded by #297` — tracked as D8 |

---

## Recommended next actions

### Just promoted (2026-07-27 RLS follow-up)

1. [#334](https://github.com/Mikedan37/BlazeDB/issues/334) — public GraphQuery RLS bypass
2. [#335](https://github.com/Mikedan37/BlazeDB/issues/335) — update WITH CHECK
3. [#336](https://github.com/Mikedan37/BlazeDB/issues/336) — count/stats RLS side channel
4. [#337](https://github.com/Mikedan37/BlazeDB/issues/337) — filtered observe delete leak

Earlier same day: #325–#333 (see Contributor-facing table).

**Held for maintainer review:** B21+B23 (`performSafeWrite` derived-structure restore); SYNC-AUTH / SYNC-RLS until Distributed is a product path.

### Promote later (pacing)

**From history harvest:** ~~H1–H3~~ → #329–#331; ~~F1–F3 / F6~~ → #332–#333.

**From follow-up audits:** A15 (C ABI docs), B24, B26, B27, B28, A12, V3.

**Held for maintainer:** B21+B23; H4 (async vacuum vs #295).

### Maintainer queue

**M2 → M1 → M3 → M9/M10 → M5/M6 → B21/B23**

### Continuous verification focus

Wire [#322](https://github.com/Mikedan37/BlazeDB/issues/322); land [#326](https://github.com/Mikedan37/BlazeDB/issues/326)/[#328](https://github.com/Mikedan37/BlazeDB/issues/328); then V3 (upsert TOCTOU).

---

## History harvest (2026-07-27)

Mined from prior agent transcripts + `Docs/Product/NEXT_ENGINEERING_AUDIT.md` / `ISSUE_TRACKER_AUDIT.md` — **noticed once, never promoted**, not a fresh audit.

### Forgotten (never in POST_AUDIT / never a GitHub issue)

| ID | Status | Category | Finding | Source | Dedup |
|----|--------|----------|---------|--------|-------|
| H1 | Promoted | Docs drift | `close()` silently rolls back open transactions; public docs omit this | [#329](https://github.com/Mikedan37/BlazeDB/issues/329) | Docs-only GFI |
| H2 | Promoted | Tooling | Crypto-change checklist + PR checkbox (S3) | [#330](https://github.com/Mikedan37/BlazeDB/issues/330) | Safe GFI |
| H3 | Promoted | Verification | Overflow orphan reclaim regression | [#331](https://github.com/Mikedan37/BlazeDB/issues/331) | Distinct from #328 |
| H4 | Held | Partial | Async `VacuumOperations.vacuum()` still lacks `writeLock` / txn guard; sync `VacuumCompaction.vacuum()` was fixed in #295 | NEXT_ENGINEERING C-NEW-1 disposition vs live `VacuumOperations.swift` L102–110 | Partial of #295 — verify which API is the supported public path before filing. |
| H5 | Held | Partial | `fetchAllCachePerformance` static OID map never cleared on close | M-NEW-3; `DynamicCollection+Performance.swift` | Sibling of #308 / B28 — fold into #308 comment or promote after #308 scope check. |
| H6 | Closed | Rejected | CLI 12+ vs engine password policy split as a “bug” | A-NEW-7 | `intentional / design` per NEXT_ENGINEERING disposition. Reopen only with product decision. |
| H7 | Held | Verification | Short CI bench smoke regression (P1) | N11 | Needs design of what “smoke” measures; near #291. |
| H8 | Held | Partial | `updateMany` / `deleteMany(where:)` per-record durable loops | P-NEW-5 | Overlaps A13 / #284 cluster — do not file separately until scope is clear. |

### Already known from history (do not re-file)

C-NEW-1/2 → #295/#296 (closed). Soft-delete/count → #297. BlazeDBC UAF → #298. rawDump → #299. Upsert resurrection → #304. Meta fsync → #305. QueryCache → #306. RecordCache → #307. OID maps → #308. put([T]) → #309. CLI argv → #310. deletePage fsync → #311. Linux insertMany → #312. beginTxn O(N) → #291/#276. N1–N3 → #292–#294. H1–H3 → #329–#331.

### Additional leftovers (transcript mine — not yet filed)

| ID | Status | Finding | Notes |
|----|--------|---------|-------|
| F1–F3 | Promoted | Distributed docs honesty cluster: invents `BlazeDBDistributed` target; “Fully Implemented” / production-ready sync & UDS docs while `Distributed/` excluded from core | [#332](https://github.com/Mikedan37/BlazeDB/issues/332) |
| F4 | Held | Linux audit archives still advertise BlazeTransport sync | Archive cleanup; low urgency |
| F6 | Promoted | ROADMAP S2 benchmark-change checklist (sibling of #330 crypto checklist) | [#333](https://github.com/Mikedan37/BlazeDB/issues/333) |
| F8 | Held | Orphan `BlazeDBTests/Indexes/SearchPerformanceBenchmarks` still force-unwraps; Tier1Perf copy fixed | Delete dead tree or confirm unused |
| F9 | Needs investigation | Android CI docs once claimed BlazeDBCore when only hello-world ran | Re-verify honesty on current `main` |
| F10 | Folded | `AsyncQueryCache` static map never cleared | Comment candidate for #308 / H5 |

### Noise discarded

Style cleanup, “could be faster” without measurement, Android experimental races, Linux `.so` packaging goals, durability-commit-boundary epic refactors, InfraPanel/Fyne UX, phone-home product design.

---

## Related docs

- [`ROADMAP.md`](../../ROADMAP.md) — navigation (themes + issue links; does not mirror audit IDs)
- `Docs/Status/DURABILITY_MODE_SUPPORT.md`
- `Docs/Guarantees/SAFETY_MODEL.md`
- `Docs/Architecture/TOURS/02_WRITE_PATH.md`
- `Docs/Product/ISSUE_TRACKER_AUDIT.md`
- `Docs/Product/NEXT_ENGINEERING_AUDIT.md`
