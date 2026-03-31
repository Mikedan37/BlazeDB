# BlazeDB Transactions

**WAL, ACID guarantees, and crash recovery.**

---

## ACID Guarantees

### Atomicity

All operations in a transaction succeed or fail together. Partial failures trigger automatic rollback.

```swift
try db.beginTransaction()
try db.insert(record1)
try db.insert(record2)
try db.commitTransaction() // Both succeed or both fail
```

### Consistency

Database never enters invalid state:
- Index updates are atomic with data writes
- Schema validation prevents invalid states
- Foreign key constraints enforced

### Isolation

**Default:** MVCC is **off**; readers and writers follow the engine’s current single-version behavior.

**When MVCC is enabled (opt-in / experimental):** snapshot-style isolation becomes available — readers can see a consistent view while writers create new versions (see MVCC documentation).

### Durability

**Default `BlazeDBClient` path:** Durability is **page-level** via the binary `WriteAheadLog` (typically `<collection>.wal`, `WALMode.legacy` by default) plus encrypted `.blazedb` pages and signed `.meta` persistence. Normal insert/update/delete does **not** use NDJSON transaction logging as the primary mechanism.

**Explicit client transactions** (when used) add their own backup/rollback behavior on top of the same storage stack; see implementation and `Docs/Status/DURABILITY_MODE_SUPPORT.md`.

> For the exact durability contract (including WAL ordering, overflow-chain behavior, metadata visibility, and orphan-page caveats), see `Docs/Status/DURABILITY_MODE_SUPPORT.md`. The short version: binary page-level WAL protects the main page write path, and large records use a publish-last overflow scheme that prevents catalog-visible torn records while allowing unused overflow pages to be reclaimed over time.

---

## Write-Ahead Logging (WAL)

### Default binary WAL (normal CRUD)

For the default `BlazeDBClient` → `PageStore` → `DynamicCollection` spine:

- `PageStore` enables the binary WAL by default (`enableWAL: true`).
- Committed page writes are recorded in the **binary** WAL file (alongside encrypted main-file pages).
- On database open, `PageStore` replays the binary WAL as needed so committed encrypted pages are consistent after a crash.
- Layout and indexes are persisted via `.meta` (signed metadata), not via NDJSON `txn_log.json`.

This is the mechanism that should be understood as “WAL-backed durability” for typical app usage.

### Legacy / alternate NDJSON artifacts

Older or alternate code paths may have created newline-delimited JSON files (e.g. `txn_log*.json`). These are **not** the default write path for current client CRUD. `BlazeDBClient.removeLegacyNDJSONTransactionLogFilesIfPresent()` performs **cleanup** of obsolete NDJSON sidecars when present — it does **not** define default document durability. (`replayTransactionLogIfNeeded()` is deprecated but equivalent.) Do not describe `txn_log.json` as the primary WAL for the OSS default runtime. The remaining NDJSON producers/consumers live in advanced/legacy tooling paths such as `BlazeTransaction` (page-level transactions in legacy mode) and `BlazeDBManager` migration/recovery helpers; normal `BlazeDBClient` usage does not rely on NDJSON logs at all.

### Conceptual commit flow (high level)

```
1. Record encoded → page encrypt → append to binary WAL → write main file
2. Index / layout updates → persist .meta
3. fsync / durability as implemented in PageStore + WAL
```

### Durability Guarantee (default path)

For the binary WAL + encrypted pages path: committed work is designed to survive process crashes to the extent implemented by `PageStore` / `WriteAheadLog` and metadata persistence. Uncommitted or partial work is discarded or rolled back per engine rules. See `Docs/Status/DURABILITY_MODE_SUPPORT.md` and `Docs/Status/CRASH_SURVIVAL.md` for precise semantics.

---

## Crash Recovery

### Recovery Process

On startup (default path):

1. Open `PageStore` — **binary** WAL replay runs as implemented in initialization (restore committed encrypted pages).
2. Load and validate `.meta` (signed layout / indexes).
3. **Legacy NDJSON:** If obsolete `txn_log*.json` sidecars exist, client cleanup may remove them; they are not the primary replay source for default CRUD.
4. Rebuild or repair indexes if metadata or implementation requires it.

### Recovery Guarantees

- **Committed transactions**: Fully recovered
- **Uncommitted transactions**: Automatically rolled back
- **Partial writes**: Discarded and rolled back
- **Index consistency**: Rebuilt if corrupted

### Corruption Detection

Automatic detection and recovery:
- CRC32 checksums on pages
- WAL integrity verification
- Metadata validation
- Automatic rebuild from data pages

---

## Transaction Isolation Levels

### Snapshot Isolation (when MVCC is enabled)

- Opt-in / experimental MVCC path only
- When enabled: readers can use snapshot semantics; writers create new versions
- Not the default for a plain `BlazeDBClient` open

### Read Committed (Future)

- Readers see latest committed data
- Lower isolation, better performance
- Suitable for read-heavy workloads

---

## Transaction Performance

### Single Transaction

- **Begin**: <0.1ms
- **Write**: 0.4-0.8ms per operation
- **Commit**: 0.5-1.0ms (includes fsync)
- **Rollback**: <0.1ms

### Batch Transactions

- **100 operations**: 15-30ms (amortized fsync)
- **1,000 operations**: 150-300ms
- **10,000 operations**: 1.5-3.0s

### Concurrency

- **Multiple readers**: As implemented for the default engine
- **Readers + writers**: Without MVCC, behavior follows single-version rules; with MVCC (opt-in), snapshot isolation applies
- **Multiple writers**: Serialized (future: concurrent writes)

---

## Savepoints

Nested transactions via savepoints:

```swift
try db.beginTransaction()
try db.insert(record1)

try db.savepoint("sp1")
try db.insert(record2)
try db.rollbackToSavepoint("sp1") // Only record2 rolled back

try db.commitTransaction() // record1 committed
```

---

## Best Practices

1. **Keep transactions short**: Minimize lock duration
2. **Use batch operations**: Amortize fsync costs
3. **Handle errors**: Always rollback on failure
4. **Monitor WAL size**: Large WALs indicate long transactions
5. **Use savepoints**: For nested transaction logic

---

For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).
For performance characteristics, see [PERFORMANCE.md](PERFORMANCE.md).

