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

Snapshot isolation via MVCC:
- Readers see consistent snapshot
- Writers create new versions
- No read-write blocking

### Durability

Committed transactions survive crashes:
- Write-ahead logging (WAL)
- fsync before commit acknowledgment
- Automatic recovery on startup

---

## Write-Ahead Logging (WAL)

### WAL Flow

```
1. BEGIN
 > Create transaction context
 > Initialize WAL entry
 > Save baseline state for rollback

2. WRITE(pageID, data)
 > Check transaction state (must be OPEN)
 > Save baseline if first write to this page
 > Stage write in memory
 > Record in WAL

3. COMMIT
 > Flush staged writes to PageStore
 > Update indexes
 > Persist layout to.meta
 > Write COMMIT to WAL
 > fsync WAL (durability guarantee)
 > Clear WAL
 > Clear baselines
 > Mark transaction COMMITTED

4. ROLLBACK (if error)
 > Restore baseline for each page
 > Delete new pages
 > Clear staged writes
 > Write ABORT to WAL
 > Mark transaction ROLLED_BACK
```

### WAL Structure

The WAL file (`txn_log.json`) uses newline-delimited JSON format. Each entry is a JSON object:

```json
{"type":"begin","txID":"550e8400-e29b-41d4-a716-446655440000"}
{"type":"write","pageID":0,"data":"<base64-encoded-data>"}
{"type":"commit","txID":"550e8400-e29b-41d4-a716-446655440000"}
```

**Entry Types:**
- `begin(txID: String)` - Transaction start
- `write(pageID: Int, data: Data)` - Page write operation
- `delete(pageID: Int)` - Page deletion
- `commit(txID: String)` - Transaction commit
- `abort(txID: String)` - Transaction rollback

### Durability Guarantee

WAL entries are fsync'd before commit acknowledgment. This ensures:
- Committed transactions survive process crashes
- Uncommitted transactions are discarded
- No data loss on power failure

---

## Crash Recovery

### Recovery Process

On startup:

```
1. Check for WAL file
2. If exists:
 > Parse all operations
 > Group by transaction ID
 > Find COMMITTED transactions
 > Replay committed writes
 > Discard uncommitted writes
 > Clear WAL
3. Load.meta file
4. Rebuild indexes if needed
```

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

### Snapshot Isolation (Default)

- Readers see consistent snapshot
- Writers create new versions
- No read-write blocking
- Serializable for most workloads

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

- **Multiple readers**: No blocking
- **Readers + writers**: No blocking (MVCC)
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

