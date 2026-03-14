# BlazeDB Open-Source Cleanup & Correctness Spec

## Overview

A 10-phase plan to take BlazeDB from "interesting storage engine with feature theater" to "database other software can trust." Every phase produces a self-contained, reviewable unit of work. Phases are ordered by dependency and risk.

## Decisions

All decisions were made during brainstorming and are locked in:

- **Scope:** Fix everything. No features removed, no corners cut.
- **Priority:** Correctness first. Silent bugs before stubs before docs before perf.
- **God object strategy:** Incremental decomposition of `DynamicCollection` — extract each subsystem as we fix the feature that lives in it.
- **Transaction architecture:** Consolidate to one WAL, one transaction model. Delete `TransactionLog`. Delete file-copy transactions.
- **Performance target:** Correct algorithms now, benchmark later. Ship correct, optimize in public.

## Phase Classification

### By risk level

| Risk | Phases |
|------|--------|
| High | 1 (WAL/Transaction), 6 (MVCC/Savepoints) |
| Medium | 2 (Constraints), 3 (Storage), 4 (Query), 5A (Spatial), 5B (Vector), 7 (Concurrency) |
| Low | 8 (API Surface), 9 (Repo/Docs/CI) |

### By work type

| Type | Phases |
|------|--------|
| Core durability/isolation redesign | 1, 6 |
| Correctness / honesty / cleanup | 2, 3, 4, 7, 8, 9 |
| Index subsystem build | 5A, 5B |

---

## Phase 1: Transaction & WAL Consolidation

**Risk: HIGH**
**Type: Core durability redesign**
**Goal:** One WAL, one transaction model. Single authoritative durability path.

### Architecture

```
BlazeTransaction
      |
TransactionContext (in-memory staged write set)
      |
DurabilityManager
  +-- WAL append (with LSN, txID, op, pageID, payload)
  +-- fsync
  +-- page mutation (only after fsync)
      |
RecoveryManager (on open)
  +-- WAL scan from lastCheckpointLSN
  +-- skip torn/partial trailing entries
  +-- fail loudly on mid-log corruption
  +-- redo committed entries only
```

### WAL entry schema

```swift
struct WALEntry {
    let lsn: UInt64
    let transactionID: UUID
    let operation: WALOperation
    let pageIndex: UInt32
    let payload: Data
    let crc32: UInt32
}

enum WALOperation {
    case begin
    case write
    case delete
    case commit
    case abort
    case checkpoint
}
```

Recovery depends on explicit transaction boundaries. A transaction is committed if and only if a `.commit` record with matching `transactionID` exists in the WAL. Entries without a corresponding `.commit` are discarded during recovery.

Explicit rollback during normal operation writes an `.abort` record. This is not required for correctness (absence of `.commit` is sufficient) but provides an unambiguous signal for debugging and auditing. Recovery treats `.abort` the same as missing `.commit`: discard all entries for that `transactionID`.

### Ordering invariant

The following order is mandatory and must be enforced in code:

1. WAL append
2. fsync (or buffered flush)
3. Page mutation

Never: mutate page then write WAL. This is the single most important invariant in the storage engine.

### Batch commit optimization

Transaction commit cost is dominated by WAL flush. The batch commit path must group multiple writes behind a single fsync where possible.

### Checkpoint semantics

- Checkpoint only after all pages up to LSN X are durable on disk
- Record `checkpoint(X)` in WAL
- WAL entries before X are reclaimable after checkpoint record is durable
- `lastCheckpointLSN` replaces the current `lastCheckpoint: Date()` which always returns current time
- Checkpoint is full (not fuzzy) for simplicity

### Checkpoint trigger policy

Checkpoint fires when either condition is met:
- WAL exceeds N entries (default: 10,000)
- WAL file exceeds M bytes (default: 64 MB)

These are configurable. Checkpointing too rarely means long recovery times; too frequently means unnecessary I/O. The defaults balance recovery speed against write amplification for typical embedded workloads.

### Torn-write behavior

- Invalid/partial trailing record: truncate tail, continue recovery from valid prefix
- Corruption in the middle of the WAL (valid records on both sides of an invalid one): fail recovery loudly — this indicates deeper corruption, not a torn write

### Page index stability

`pageIndex: UInt32` is the identifier. If pages can move, split, compact, or be recycled in future work, this becomes a problem. For now, page index is stable in `PageStore` and this is acceptable. Document this assumption.

### Deletes

- `TransactionLog.swift` — delete after confirming it is not used for logical rollback (audit shows it is durability scaffolding only)
- File-copy backup/swap transaction model in `BlazeDBClient` — delete

### Extractions from DynamicCollection

- Recovery logic -> `RecoveryManager`
- Durability logic -> `DurabilityManager`

### Tests

1. begin -> write -> crash -> reopen -> WAL replay restores data
2. Crash mid-WAL-write -> reopen -> partial trailing record ignored, no corruption
3. WAL write completes, crash before page flush -> replay -> page reconstructed correctly
4. Transaction without `.commit` record -> recovery discards its writes

---

## Phase 2: Constraints & Integrity

**Risk: MEDIUM**
**Type: Correctness**
**Goal:** Foreign keys, unique constraints, and check constraints actually enforce and persist across database reopens.

### Foreign keys

`ForeignKeys.swift` currently validates nothing. `handleCascadeDeletes` logs "Would delete related records" for every case.

Fix:
- `validateForeignKeys(for:operation:)` queries the referenced collection and rejects if the referenced key does not exist
- `handleCascadeDeletes` performs the actual operation:
  - `.cascade` -> delete related records
  - `.restrict` -> throw error if children exist
  - `.setNull` -> null the FK field (only if field is nullable and null is representable in the type)
- FK checks must use PK lookup on the referenced side, not full collection scan
- Cascade deletes on the child side must use indexed lookup if available
- All cascade/restrict/setNull operations must occur within the same transaction boundary as the triggering operation. The constraint engine produces a deterministic write set that becomes part of one atomic commit

### Constraint persistence

Persist in `StorageLayout` metadata:
- Constraint definitions (type, fields, referenced collection/field)
- Action policies (cascade, restrict, setNull)
- Uniqueness target fields
- Check constraint predicate specifications

Do NOT persist:
- Ephemeral validation caches
- Runtime indexes that can be rebuilt

Schema definitions are durable. Runtime helpers are reconstructable.

### Check constraints — durable representation

Current check constraints are closure-based, which is not persistable. Implement a durable constraint representation:
- Expression tree or predicate DSL
- Constrained field + operator + literal value
- Persistable as part of `StorageLayout` metadata
- Reconstructed into runtime validators on database open

### Unique constraints

Replace `objc_setAssociatedObject` storage (constraints vanish on deallocation) with:
- Persistent definition in `StorageLayout` metadata
- On insert/update: validate uniqueness against both durable state AND the current transaction's staged writes (catches intra-transaction duplicates)
- Enforcement via unique index or deterministic rebuild of validation index on open

### Constraint evaluation order

When an operation triggers multiple constraints, evaluation order is:
1. Check constraints (cheapest, fail fast on invalid data)
2. Unique constraints (index lookup)
3. Foreign key constraints (may require cross-collection lookup)

This order is deterministic and documented. The first failing constraint produces the error. This matters for error messages and avoids expensive FK lookups when a cheap check constraint would have rejected the operation.

### Extraction from DynamicCollection

- Constraint logic -> `ConstraintEngine`
- `DynamicCollection` delegates to `ConstraintEngine` on insert/update/delete

### Tests

1. Insert violating a foreign key -> error thrown
2. Delete with cascade -> related records actually deleted in same transaction
3. Delete with restrict -> error thrown if children exist
4. setNull with non-nullable field -> error (not silent null injection)
5. Create unique constraint -> close DB -> reopen -> insert duplicate -> error
6. Check constraint rejects invalid value on insert and update
7. Reopen + cascade integrity: create FK with cascade -> close -> reopen -> delete parent -> verify children deleted
8. Intra-transaction uniqueness: insert two rows with same unique key in one transaction -> commit fails atomically

---

## Phase 3: Storage & Encoding

**Risk: MEDIUM**
**Type: Correctness**
**Goal:** Lazy records actually lazy-decode. Fix storage-level correctness bugs.

### Lazy decoding — binary format v3

Current state: `LazyFieldRecord` and `LazyBlazeRecord` decode the entire record on every field access. The "lazy" label is a lie.

#### Migration strategy (v2 -> v3)

- The v3 encoder always writes v3 format
- The v3 decoder reads both v2 and v3: it checks the version byte and falls back to full decode for v2 records
- Migration is lazy: v2 records are rewritten to v3 on next update (not on open, not in bulk)
- A database may contain mixed v2/v3 records indefinitely — this is an acceptable steady state
- There is no downgrade path: a database written with v3 records is not readable by older BlazeDB versions. This is acceptable for a pre-1.0 engine. Document this as a breaking change in release notes.
- No bulk migration tool is provided in this phase. If needed later, it is a separate utility.

New binary layout (format version bump v2 -> v3):

```
[RecordHeader]
  version: UInt8
  fieldCount: UInt16
  offsetTableOffset: UInt32

[FieldData...]
  raw field bytes, packed sequentially

[OffsetTable]
  for each field:
    fieldNameLength: UInt16
    fieldName: UTF8 bytes
    offset: UInt32
    length: UInt32
    type: UInt8
```

Design decisions:
- Field names (not numeric IDs) — maintains human-debuggability and schema flexibility
- Offset table at footer — one seek to locate, then direct seeks per field
- Backward-compatible: v3 decoder can read v2 records (falls back to full decode)

`LazyFieldRecord` reads only the offset table on init, then seeks to specific field bytes on access.

### Lazy decode verification

Instrument the byte reader to track decode calls per field. Test asserts only the requested field was decoded, not full record. Do not rely on timing — use call counts.

### BlazeBinaryFieldView

Currently returns `""` for unhandled paths. Fix using the new offset table for actual field extraction, or delete the type if zero-copy cannot be delivered honestly.

### Orphan detection

`PageStore.getStorageStats()` only recognizes `0x01` (unencrypted) headers. Add `0x02` (encrypted format) recognition. Encrypted pages must not be classified as orphans.

### Salt handling

Extract `"AshPileSalt"` (18 occurrences, 6 files) into a single constant. But more importantly, persist salt in database metadata:

```
DB metadata:
  salt (generated on creation or user-provided)
  KDF parameters
```

User provides password -> engine derives key using stored salt. Salt must not need to be manually provided on reopen.

### getStorageStats() locking

Current: O(n) page scan inside `queue.sync` barrier. This is a pause-the-world operation.

Fix: snapshot metadata, release lock, scan asynchronously. The lock protects the metadata snapshot, not the entire scan.

### Extraction from DynamicCollection

- Encoding/format-migration logic -> `EncodingManager`

### Tests

1. Lazy decode: access one field, verify only that field's bytes were decoded (instrumented reader)
2. Binary format v3 round-trip: encode with offset table, decode lazily, verify all field types
3. v2 backward compat: read a v2-encoded record with v3 decoder
4. Orphan detection: create encrypted DB, run `getStorageStats()`, verify zero orphans
5. Salt persistence: create DB with default salt -> reopen -> verify HMAC validates without user providing salt
6. Custom salt: create DB with explicit salt -> reopen -> verify key derivation uses stored salt

---

## Phase 4: Query Engine

**Risk: MEDIUM**
**Type: Correctness**
**Goal:** Query planner executes its chosen plan. CTEs wire output to main query. Window functions O(n). Conflict resolution uses handler result.

### Planner/Executor separation

Current: `QueryPlanner.executeWithPlanner()` is a monolith that plans and then ignores the plan.

Split into:
- `QueryPlanner` -> builds plan (cost analysis, strategy selection)
- `QueryExecutor` -> runs plan (dispatches to the correct execution path)

Each plan type (spatial, vector, fullText, hybrid, regularIndex) has a corresponding execution path in `QueryExecutor`. No more falling through to `execute()`.

Remove `_ = false` dead code suppressing vector path.

### CTEs

Current: each CTE runs independently, output discarded. Main query runs against raw collection.

Fix — simple materialized CTE model:
- CTEs evaluated in declaration order
- Later CTEs may reference earlier ones
- CTE names shadow collection names in scope
- Results materialized into temporary in-memory collections
- Main query resolves CTE references against materialized results

No lazy/recursive CTEs needed yet. Materialized is correct and simple.

### Window functions

Current: O(n^2) — re-scans partition for every record.

Fix:
1. Group records by partition key
2. Sort each partition once
3. Single-pass evaluation with running state per partition
4. Emit window values in one iteration

Test correctness via relative growth, not absolute timing. Double input size, verify time grows linearly (not quadratically).

### Conflict resolution

`ConflictResolution.swift` line 131 discards the custom handler's return value with `_`.

Fix: use the handler's returned `RecordVersion` as the write. Ensure conflict handlers execute inside the same transaction boundary — WAL order must be deterministic.

Note: this Phase 4 fix operates on the pre-MVCC conflict model (record-level last-write-wins vs custom handler). Phase 6 introduces version chains and snapshot isolation, which changes the conflict surface. The Phase 4 fix must be correct for the current model. Phase 6 may extend or replace the conflict resolution mechanism, but the handler-return-value fix is correct regardless — a handler whose result is discarded is broken in any model.

### Hybrid full-text

`QueryBuilder+Hybrid.swift` accepts `fullTextField`/`fullTextQuery` parameters and ignores them.

Rule: if a parameter does nothing, delete it. Remove the silent-swallow methods. If full-text filtering is implemented later, add the parameters back with real behavior.

### RLS integration into read pipeline

The RLS `PolicyEngine` is correctly implemented but disconnected from every public read path. `fetchWithRLS`/`fetchAllWithRLS` exist as `internal` methods but are never called from `BlazeDBClient.fetch`, `fetchAll`, `QueryBuilder`, or any other public API. The only enforcement point is `GraphQuery.injectRLSFilter`.

Fix — integrate RLS into `QueryExecutor`:
- `QueryExecutor` applies RLS policies as a filter stage after data retrieval and before returning results
- `BlazeDBClient.fetch(id:)` and `fetchAll()` route through `QueryExecutor` when a security context is set
- All read paths (`distinct`, `fetchPage`, batch reads, export, backup) go through the same filtered pipeline
- Remove `BlazeRLSRegistry` (System B) entirely — it registers policies that nothing reads. One enforcement mechanism, no duplicates.
- Add configurable fail-closed mode: `rlsFailClosed: Bool` on `BlazeDBClient` init. When `true` and no security context is set, reads return empty results. Default: `false` (fail-open, matching current embedded DB expectations). Document the security implications of each mode.
- Write-side enforcement (INSERT/UPDATE/DELETE policy checks) is deferred — read enforcement first, write enforcement in a future iteration.

### Extraction from DynamicCollection

- Query execution dispatch -> `QueryExecutor`

### Tests

1. Planner selects spatial plan -> spatial index is actually queried (verify via instrumentation, not just result correctness)
2. CTE: define CTE that filters to 3 records -> main query aggregates CTE output -> count is 3
3. CTE chaining: CTE B references CTE A -> verify B sees A's output
4. Window function: 10K records, 100 partitions -> double to 20K -> verify linear growth
5. Conflict resolution with custom handler -> handler's returned version is the one persisted
6. Hybrid full-text: method with fullTextField parameter either filters or does not compile
7. RLS enforcement: set context as user A with policy restricting to own records -> `fetchAll()` returns only user A's records
8. RLS bypass without context: no context set, `rlsFailClosed: false` -> all records returned
9. RLS fail-closed: no context set, `rlsFailClosed: true` -> empty results
10. RLS via QueryBuilder: query with active context -> results filtered by policy

---

## Phase 5A: Spatial Index

**Risk: MEDIUM**
**Type: Index subsystem build**
**Goal:** R-tree persists to disk, has working node splits, doesn't degenerate.

### Persistence

`saveSpatialIndexToLayout()` currently does nothing. The spatial index rebuilds from scratch on every database open.

Fix: serialize R-tree structure to dedicated index pages (not metadata — the index can grow beyond tiny size). On open, deserialize from pages instead of rebuilding.

### splitInternal

Currently a stub that logs and does nothing. An R-tree with no internal node split degenerates to a linear scan.

Implement linear split heuristic:
- Pick the two entries with the greatest separation along any axis
- Assign remaining entries to the group that requires least bounding box expansion

### splitLeaf

Currently splits by array position (arbitrary). Implement proximity-based split:
- Find axis with greatest spread
- Sort entries along that axis
- Split at median

### Extraction from DynamicCollection

- Spatial index management -> `SpatialIndexManager`

### Tests

1. Insert 1000 points -> close DB -> reopen -> radius query returns same results (no rebuild)
2. Insert enough points to trigger internal split -> verify tree depth increases -> queries still correct
3. Bounding box query after many inserts -> verify result correctness against brute-force scan
4. Persistence round-trip: serialize R-tree -> deserialize -> tree structure matches

---

## Phase 5B: Vector Index (HNSW)

**Risk: MEDIUM**
**Type: Index subsystem build**
**Goal:** Replace flat O(n) scan with basic HNSW graph structure.

### HNSW implementation

Current: `VectorIndex.swift` is a `[UUID: VectorEmbedding]` dictionary with O(n) cosine similarity scan.

Replace with basic HNSW:
- Navigable small-world graph with configurable `M` (max connections per node) and `efConstruction` (construction beam width)
- Layered structure: each node exists at layer 0, probabilistically assigned to higher layers
- Insert: find entry point at top layer, greedily descend, connect to nearest neighbors at each layer
- Query: beam search from entry point, return top-K by cosine similarity
- Reasonable defaults (M=16, efConstruction=200)

This does not need to be state-of-the-art. It needs to be correct and better than O(n).

### Persistence

Persist the graph structure to storage:
- Adjacency lists per node
- Layer assignments
- Entry point node ID

On open, deserialize from storage. No full rebuild.

### Deletion semantics

When a record with a vector embedding is deleted:
- Mark the HNSW node as deleted (tombstone flag)
- Deleted nodes are skipped during search but their edges remain intact
- Periodic graph maintenance (during GC or rebuild) reconnects neighbors of deleted nodes and removes tombstones
- If the entry point node is deleted, promote the nearest non-deleted neighbor at the top layer

Full graph compaction (removing all tombstones and rebuilding edges) is deferred to vacuum or explicit rebuild. This is the standard lazy-deletion approach for HNSW and avoids expensive graph surgery on every delete.

### ANN testing

HNSW produces approximate nearest neighbors. Tests must account for this:
- Recall@K against flat scan (expect >95% recall with reasonable parameters)
- Exact correctness on small datasets (< 100 vectors, HNSW should be exact)
- Deterministic graph persistence: insert -> close -> reopen -> same query returns same results

### Extraction from DynamicCollection

- Vector index management -> `VectorIndexManager`

### Tests

1. Insert 5000 random 128-dim vectors -> query nearest 10 -> verify cosine similarity ordering
2. Recall@10 against flat scan on 5000 vectors -> expect >95%
3. Small dataset (50 vectors): HNSW results match flat scan exactly
4. Persistence: insert vectors -> close -> reopen -> query returns same results
5. Insert + query interleaving: insert batch, query, insert more, query again -> results reflect new data

---

## Phase 6: MVCC & Savepoints

**Risk: HIGH**
**Type: Core isolation redesign**
**Goal:** Real snapshot isolation on reads. Savepoints that don't copy the database file.

### Snapshot isolation

Each transaction gets a snapshot LSN at begin time (from `DurabilityManager`).

Visibility rules (explicit and non-negotiable):
- Record version visible if `commitLSN <= snapshotLSN`
- Versions created by the current transaction are visible to itself (read-your-own-writes)
- Uncommitted versions from other transactions are invisible

### Version chain

Concrete version record structure:

```swift
struct RecordVersion {
    let recordKey: UUID
    let createLSN: UInt64
    let commitLSN: UInt64?      // nil if uncommitted
    let tombstone: Bool
    let previousVersion: UUID?  // pointer to prior version
    let data: Data
}
```

### Version storage

Versions are stored in a separate version store (dedicated page range), not inline with the current record's page. Rationale:
- Inline storage would require variable-length pages or complex page splitting as version chains grow
- A separate version store allows the current-record page to remain fixed-size and cache-friendly
- GC of old versions does not fragment the primary data pages
- The current (latest committed) version is stored in the primary data page as today. The version store holds previous versions only.

The `previousVersion` pointer in `RecordVersion` is a version-store page reference, not a UUID lookup. Version chain traversal follows page pointers, not hash lookups.

### Write-write conflict detection

When two concurrent transactions write to the same record, BlazeDB uses first-committer-wins:
- At commit time, check whether the record's `commitLSN` has advanced since the transaction's `snapshotLSN`
- If yes: the record was modified by another committed transaction. Abort the current transaction with a conflict error.
- If no: commit proceeds.

This is standard snapshot isolation behavior. Last-writer-wins is not acceptable for a database making isolation guarantees. The caller can retry the transaction.

### Wiring into read path

`DynamicCollection.fetchAll()` and single-record reads must filter by snapshot LSN. This is the actual isolation guarantee. Without this, MVCC is decorative infrastructure.

### Default behavior and migration

MVCC becomes the default transaction/read model for BlazeDB.

Migration plan for existing databases:
- Databases created before MVCC have no version chain metadata. On first open with the new code, all existing records are assigned a synthetic `commitLSN` of 0 (the "genesis" LSN). This makes them visible to all snapshots.
- No data rewrite is needed — the synthetic LSN is inferred from the absence of version metadata, not stored retroactively.
- Existing callers that use `fetchAll()` without explicit transactions get an implicit auto-transaction with a snapshot at the current LSN. Behavior is identical to pre-MVCC for single-statement reads.
- Callers that depend on seeing uncommitted writes from other contexts (the old "read whatever's on disk" behavior) must be identified during implementation. If any exist, provide a `readUncommitted: true` option on the read path as an escape hatch. Do not make this the default.

### GC safety rules

- Version GC must never reclaim versions newer than the oldest active snapshot
- Version GC must not run on uncommitted versions
- GC runs only after confirming no active transaction references the version range

### Savepoints

Current: copies entire database file with `Thread.sleep` delays (10ms, 10ms, 50ms, 20ms).

Fix — savepoints operate on the transaction-local staged state, NOT the persisted WAL:
- Savepoint captures a marker (position) in the transaction's staged write set (`TransactionContext`)
- Rollback to savepoint rewinds the uncommitted staged mutations to that marker
- Nested savepoints = stack of markers
- No file copies. No sleeps. No WAL mutation.

Important distinction: savepoints rewind the in-memory transaction context. They do not "discard WAL entries" in any persistent sense. WAL is append-only and durable. Savepoints are pre-commit bookkeeping.

### Extraction from DynamicCollection

- Version management -> `VersionManager`
- Savepoint logic -> `SavepointManager`

### Tests

1. Snapshot isolation: txA reads, txB writes + commits, txA reads again -> txA sees original value
2. Read-your-own-writes: within one transaction, write then read -> see own write
3. Savepoint: begin -> write A -> savepoint -> write B -> rollback to savepoint -> commit -> only A persists
4. Nested savepoints: three levels, rollback middle -> inner discarded, outer preserved
5. GC: old versions exist, no active snapshots reference them -> GC reclaims
6. GC safety: active snapshot references version -> GC does not reclaim
7. MVCC + crash recovery: uncommitted transaction in flight -> crash -> recovery does not resurrect uncommitted versions

---

## Phase 7: Concurrency & Error Handling

**Risk: MEDIUM**
**Type: Correctness**
**Goal:** Correct ownership/isolation semantics. Unified error types with cause chains.

### Success criterion

Warning elimination is not the goal. Correct ownership and isolation semantics is the goal. The compiler passing `-strict-concurrency=complete` is a necessary but not sufficient condition.

### nonisolated(unsafe) audit (79 usages, 48 files)

Categorize every usage with a disposition:
- True immutable statics -> keep, document as immutable
- Runtime-mutable globals (e.g., `BlazeBinaryEncoder.crc32Mode`) -> protect with lock or convert to actor-isolated state
- Lazy initialization -> convert to `let` with lazy initializer or equivalent

### @unchecked Sendable audit (17 classes)

Produce a disposition table. For each class, one of:
- **Keep + document invariant** — e.g., `PageStore` with internal queue (legitimate)
- **Add synchronization** — e.g., `AutomaticGCManager` if missing sync
- **Remove Sendable conformance** — e.g., `QueryBuilder` ("designed for sequential access" but marked Sendable is a lie)
- **Convert to actor** — where actor isolation is the right model

### BlazeTransaction.state

Make `state` private. Synchronize mutations with a lock. Remove the redundant `internal var state` / `internal var debugState` split.

### RLS context: replace global with per-query

`RLS.currentContext` is a single global value behind an `NSLock`. Two concurrent callers with different user identities will race — queries can execute under the wrong user context.

Fix: security context flows through `TransactionContext` or `QueryContext`, not a global variable. Each query/transaction carries its own user identity. The `RLS` manager reads the context from the execution context, not from a global.

```
query(context: SecurityContext)
     |
QueryExecutor(context)
     |
PolicyEngine.isAllowed(context, record)
```

This naturally integrates with the Phase 6 MVCC work — transactions already carry a snapshot LSN, adding a security context to the same execution scope is a clean fit.

### WriteBatch keyed by ObjectIdentifier

Switch to `UUID` keys. `ObjectIdentifier` reuse after deallocation causes silent `WriteBatch` sharing between unrelated `PageStore` instances.

### NSError -> BlazeDBError

Replace 61 raw `NSError` throws with `BlazeDBError` cases. Preserve underlying cause chains:

```swift
enum BlazeDBError: Error {
    case storage(StorageError, underlyingError: Error?)
    case transaction(TransactionError, underlyingError: Error?)
    case constraint(ConstraintError)
    // ... domain-specific cases with context
}
```

Do not flatten into `.storageError` / `.unknown`. Preserve diagnostic metadata.

### try? in durability paths

Remove all `try?` in recovery, commit, and checkpoint paths. `try?` is acceptable for optional features (telemetry, stats). Never acceptable for data integrity.

### Tests

1. Compile with `-strict-concurrency=complete` — zero warnings
2. Concurrent commit/rollback: two threads call simultaneously -> one succeeds, one errors, no crash
3. Concurrent read during commit -> no crash, read sees consistent state
4. Concurrent stats/health call during write path -> no crash
5. Error type consistency: catch `BlazeDBError` at `BlazeDBClient` level -> no `NSError` leaks from storage
6. RLS context isolation: two concurrent queries with different security contexts -> each sees only its own policy-filtered results

---

## Phase 8: API Surface

**Risk: LOW**
**Type: Cleanup**
**Goal:** Clean public API for external consumers. Remove application-specific types.

### Removals

- **`BlazeDBClient+AI.swift`**: `AIContinuationSample` and handwriting AI types do not belong in a database engine. Delete.
- **`UserDefaults` in `BlazeDBClient.init`**: The initializer reads `UserDefaults.standard` to potentially override the `project` parameter. Remove. Public API constructors must be deterministic from explicit inputs. No hidden environment reads, no process-global config overrides.
- **Staging products**: Remove `BlazeDBSyncStaging` and `BlazeDBTelemetryStaging` from the `products` array in `Package.swift`. Keep as internal targets if needed.
- **Duplicate Foundation import**: Remove `@preconcurrency import Foundation` duplicate in `QueryPlanner.swift`.

### Extension consolidation

34 extension files is too many. Group by public mental model:

- `BlazeDBClient+Query.swift` (merges Spatial, Vector, Convenience query methods)
- `BlazeDBClient+Transactions.swift` (merges MVCC, Batch)
- `BlazeDBClient+Admin.swift` (merges Stats, HealthCheck, Observability, PrettyPrint, Lifecycle)
- `BlazeDBClient+Schema.swift` (merges Triggers, Workspace)
- `BlazeDBClient+Lazy.swift` (separate — distinct access pattern)

Principle: group by mental model, not by minimizing file count. If a merged file exceeds ~400 lines, split by sub-domain.

Note: merging files will destroy `git blame` history for merged lines. This is acceptable for a pre-OSS cleanup — the public repo starts with clean history. Use a single consolidation commit per domain group to keep the change traceable.

### readPageAsync honesty

Currently wraps sync I/O in an async function. Either implement real async I/O or rename to make the shim nature explicit.

### Tests

1. Public API surface: verify all public symbols compile from an external module
2. `BlazeDBClient.init` determinism: init with `project: "X"` while `UserDefaults` has "Y" -> project is "X"

---

## Phase 9: Repo, Docs, CI

**Risk: LOW**
**Type: Cleanup**
**Goal:** First impression is clean. Docs are accurate. CI tests what it claims.

### Meta-rule for CI

Every CI workflow must reference real targets and fail meaningfully on real regressions. Fake-green CI is worse than no CI.

### Deletions

- **`Docs/Archive/`**: Files named `MY_HONEST_OPINION.md`, `BRUTALLY_HONEST_VALUE.md`, `INSANE_FEATURES.md`. Review each: delete if embarrassing/no value, archive privately if useful engineering context.
- **Root-level marketing**: `blazedb_medium_article.html`, `.md`, orphaned PNG/SVG not referenced by README.
- **Test-internal markdown**: `REORGANIZATION_PLAN.md`, `REORGANIZATION_STATUS.md`, etc. from `BlazeDBTests/`.

### Fixes

- **`CONTRIBUTING.md`**: Replace nonexistent script references (`test-gate.sh`, `test-all.sh`, `check-freeze.sh`) with `swift test --filter` commands. Fix tier names to match `Package.swift` (`BlazeDB_Tier0`, `BlazeDB_Tier1`).
- **`release.yml`**: Change filter from `BlazeDBTests` (matches nothing) to actual target names. Match `swift-actions/setup-swift` version with `ci.yml`.
- **`core-tests.yml`**: Remove `continue-on-error: true` on Tier1 or document why failures are non-blocking.
- **`test.yml`**: Delete the "GitHub Actions is working" placeholder workflow.
- **Dead links**: Create `LINUX_GETTING_STARTED.md` or remove references in README and Getting Started.
- **`CHANGELOG.md`**: Address the 0.1.2 -> 2.7.0 version jump with explanatory note or restructure.
- **Duplicate test files**: Remove flat `BlazeDBTests/` legacy copies that duplicate `Tier1Core/` files.

### Argon2KDF rename

This is a correctness/honesty fix, not just repo polish. Rename `Argon2KDF.swift` to `MemoryHardKDF.swift` or `BlazeKDF.swift`. Update all doc comments to remove Argon2 claims. Document what it actually is (HMAC-SHA256-based memory-hard KDF).

### Hollow tests

Triage the 44+ `XCTAssertTrue(true)` instances:
- Replace with real assertions where the test has meaningful behavior to check
- Move to smoke/integration tier if weak but exercises a real code path that would crash on regression
- Delete if meaningless

Acceptance criterion: zero `XCTAssertTrue(true)` remaining in Tier0 and Tier1. Smoke-tier tests that only verify "no crash" must use `XCTAssertNoThrow` with a comment explaining why crash-freedom is the assertion.

Fix or delete permanently-skipped `GoldenPathIntegrationTests`.

### Documentation

- Add `///` DocC documentation on primary `BlazeDBClient` public entry points
- Ensure README quick-start code matches current API

### Tests

- CI validation: run all workflows, verify they reference real targets and produce real results
- Doc link checker: verify all internal doc references resolve

---

## Phase Dependency Graph

```
Phase 1 (WAL/Transaction) ─── HARD DEPENDENCY for all phases
  |
  +──── Phase 2 (Constraints) ── independent of 3, 4, 5
  |
  +──── Phase 3 (Storage/Encoding) ── independent of 2, 4, 5
  |
  +──── Phase 4 (Query Engine) ── independent of 2, 3
  |       |
  |       +──── Phase 5A (Spatial) ── needs QueryExecutor from Phase 4
  |       +──── Phase 5B (Vector) ── needs QueryExecutor from Phase 4
  |
  +──── Phase 6 (MVCC/Savepoints) ── depends on Phase 1 LSN infrastructure
  |
  +──── Phase 7 (Concurrency) ── best after 2-6, audits final state
  |
  +──── Phase 8 (API Surface) ── after all feature phases
  |
  +──── Phase 9 (Repo/Docs/CI) ── can run in parallel with anything
```

### Parallelization opportunities

For a single engineer, the recommended serial order is: 1 → 2 → 3 → 4 → 5A → 5B → 6 → 7 → 8 → 9.

For multiple engineers or parallel work:
- After Phase 1: Phases 2, 3, and 6 can run in parallel (they touch different subsystems)
- After Phase 4: Phases 5A and 5B can run in parallel
- Phase 9 (docs/CI) can start at any time for non-code fixes

The previous dependency chain (2 → 3 → 4) was a serialization constraint for one engineer, not a code dependency. Phases 2, 3, and 4 touch different subsystems and can be developed independently after Phase 1.
