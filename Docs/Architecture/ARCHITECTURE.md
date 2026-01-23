# BlazeDB Architecture

**System layers, storage engine, MVCC, and query execution.**

---

## Design Intent

BlazeDB uses a layered architecture to separate storage, concurrency, query execution, and encryption concerns. The system assumes page-based storage with fixed-size I/O, MVCC for concurrency, and per-page encryption granularity. This design enables predictable performance, efficient garbage collection, and clear debugging boundaries.

---

## System Layers

BlazeDB implements a layered architecture that enforces clear separation of concerns. Each layer has a well-defined responsibility and communicates only with adjacent layers.

| Layer | Components | Responsibility |
|-------|------------|----------------|
| **Application** | BlazeDBClient, SwiftUI Integration, CLI Tools | Public API and user-facing interfaces |
| **Query** | Query Builder, Optimizer, Planner, Indexes | Query parsing, optimization, and execution planning |
| **MVCC** | Version Manager, Transactions, Garbage Collection | Concurrency control and transaction isolation |
| **Storage** | PageStore, WriteAheadLog, StorageLayout, Overflow Pages | Page-based I/O and metadata management |
| **Encryption** | AES-256-GCM, KeyManager, Secure Enclave | Per-page encryption and key management |

The storage layer handles all I/O operations. Encryption is applied at the page level, enabling efficient garbage collection. MVCC provides concurrency control above the storage layer, allowing concurrent readers and writers without blocking.

**Multi-Process Safety:** BlazeDB enforces exclusive file locking at the OS level using POSIX `flock()` with `LOCK_EX | LOCK_NB` (exclusive, non-blocking). The lock is acquired during `PageStore` initialization, before any writes are possible. Only one process can open a database file for writing at a time. Attempting to open the same database from multiple processes (or multiple times in the same process) will fail immediately with `BlazeDBError.databaseLocked`. The lock is automatically released when the file descriptor is closed (process exit or instance deallocation). This prevents data corruption from concurrent file-level writes. **Crash Safety:** If a process terminates unexpectedly, the OS automatically releases the lock, allowing a new process to open the database immediately without manual cleanup.

---

## Storage Engine

### Page Structure

BlazeDB uses 4KB fixed-size pages for predictable I/O performance. Each page follows a consistent layout:

| Offset | Size | Content | Description |
|--------|------|---------|-------------|
| 0-3 | 4 bytes | `"BZDB"` | Magic header for format identification |
| 4 | 1 byte | `0x01` | Page format version |
| 5-8 | 4 bytes | `UInt32` | Payload length (big-endian) |
| 9-N | variable | BlazeBinary | Encoded record data |
| N+1-4095 | remainder | `0x00` | Zero padding to page boundary |

**Maximum payload size:** ~4046 bytes (4096 - 50 bytes overhead: 9-byte header + 12-byte nonce + 16-byte auth tag + padding)

### File Layout

Each database collection is stored as a set of files in the database directory:

| File | Format | Purpose |
|------|--------|---------|
| `<collection>.blaze` | BlazeBinary | Main data file containing 4KB pages with BlazeBinary-encoded records |
| `<collection>.meta` | JSON | Layout metadata and page index mappings |
| `<collection>.meta.indexes` | JSON | Secondary index definitions and data |
| `txn_log.json` | JSON | Write-ahead log for transaction durability |

### Metadata Format

The `<collection>.meta` file contains JSON-encoded metadata:

- **Index Map**: UUID to page index mappings for record lookup
- **Secondary Indexes**: Index definitions and key-to-UUID mappings
- **Schema Version**: Version number for migration compatibility
- **Field Types**: Type information for schema validation

---

## MVCC (Multi-Version Concurrency Control)

### Architecture

MVCC enables snapshot isolation: readers see a consistent snapshot while writers create new versions without blocking.

```swift
struct RecordVersion {
 let recordID: UUID
 let version: UInt64
 let pageNumber: Int
 let createdByTransaction: UInt64
 let deletedByTransaction: UInt64
}

// Readers see snapshot
func read(id: UUID, snapshotVersion: UInt64) -> Data? {
 return versions[id]?
.filter { $0.isVisibleTo(snapshotVersion: snapshotVersion) }
.last
.flatMap { pageStore.read(pageNumber: $0.pageNumber) }
}

// Writers create new version (don't block)
func write(id: UUID, data: Data, txID: UInt64) {
 let pageNumber = pageStore.write(data)
 let newVersion = RecordVersion(
 recordID: id,
 version: nextVersion(),
 pageNumber: pageNumber,
 createdByTransaction: txID,
 deletedByTransaction: 0
 )
 versions[id]?.append(newVersion)
}
```

### Performance Characteristics

| Metric | Value |
|--------|-------|
| Concurrent readers | Unlimited |
| Concurrent writers | Unlimited |
| Write throughput | 10,000-50,000 ops/sec |
| Read throughput | 50,000+ ops/sec |
| Read-write blocking | None |

### Garbage Collection

Obsolete page versions are automatically collected to reclaim storage:

- **Automatic Collection**: Runs periodically based on version age and transaction visibility
- **Long-Running Transactions**: Read transactions delay GC of versions they may access
- **Manual Triggers**: Applications can trigger collection when needed

---

## Query Execution

### Query Planner

The query planner uses rule-based heuristics to optimize query execution. A cost-based optimizer is planned for future releases.

**Optimization Steps:**

1. **Index Selection**: Analyzes WHERE clauses to identify and select the most efficient index
2. **Join Planning**: Determines optimal join order and algorithm (nested loop, hash join)
3. **Filter Pushdown**: Applies filters as early as possible to reduce data movement
4. **Projection**: Selects only required fields to minimize memory usage

### Index Types

BlazeDB supports multiple index types optimized for different query patterns:

| Index Type | Structure | Use Case |
|------------|-----------|----------|
| **Secondary** | Hash table | Equality lookups (`WHERE field = value`) |
| **Compound** | Multi-field hash | Complex equality queries on multiple fields |
| **Full-Text** | Inverted index | Text search with relevance scoring |
| **Spatial** | R-tree | Geospatial queries (distance, containment) |
| **Vector** | Approximate nearest neighbor | Similarity search for embeddings |

### Execution Flow

Query execution follows a five-stage pipeline:

1. **Parser**: Converts the fluent query DSL into an abstract syntax tree (AST)
2. **Optimizer**: Analyzes the AST, selects optimal indexes, and determines join order
3. **Planner**: Creates an execution plan with filter pushdown and field projection
4. **Executor**: Executes the plan by accessing pages through the storage layer
5. **Results**: Returns filtered and projected records to the application

The optimizer uses rule-based heuristics to select the most efficient index for WHERE clauses. The planner applies filters as early as possible in the pipeline to minimize data movement between stages.

---

## Concurrency Model

### GCD-Based Implementation

The current implementation uses Grand Central Dispatch (GCD) concurrent queues with barriers:

| Aspect | Behavior |
|--------|----------|
| Readers | Multiple concurrent readers supported |
| Writers | Single writer at a time (serialized) |
| Write throughput | 2,000-5,000 operations/second |
| Read throughput | 10,000+ operations/second |
| Blocking | Writers block other writers; readers never block |

### MVCC Implementation

The MVCC implementation provides true concurrent access:

| Aspect | Behavior |
|--------|----------|
| Readers | Unlimited concurrent readers |
| Writers | Unlimited concurrent writers |
| Isolation | Snapshot isolation per transaction |
| Blocking | No read-write blocking |
| Write throughput | 10,000-50,000 operations/second |

---

## Design Decisions

### Page-Based Storage

**Rationale:** Fixed-size 4KB pages provide predictable I/O performance and simplify implementation.

**Benefits:**
- Predictable performance characteristics (fixed-size I/O operations)
- Simple implementation and debugging
- Easy to reason about memory layout and access patterns

**Tradeoffs:**
- Internal fragmentation when records don't fill pages completely
- Large records require overflow pages (implemented)

### BlazeBinary Format

**Rationale:** Custom binary format optimized for Swift types and BlazeDB's use cases.

**Benefits:**
- 53% smaller than JSON (reduced storage and network overhead)
- 48% faster encode/decode operations
- Deterministic encoding (identical records produce identical binary)
- Field name compression (unique optimization)

**Tradeoffs:**
- Less human-readable than JSON for debugging
- Requires custom tooling for inspection

### MVCC over Locking

**Rationale:** Multi-version concurrency control eliminates read-write contention.

**Benefits:**
- No read-write blocking (readers never wait for writers)
- Superior concurrency characteristics
- Snapshot isolation provides consistent views

**Tradeoffs:**
- Storage overhead for maintaining multiple versions
- Garbage collection required to reclaim obsolete versions

---

For detailed protocol specifications, see [PROTOCOL.md](PROTOCOL.md).
For transaction details, see [TRANSACTIONS.md](TRANSACTIONS.md).
For security architecture, see [SECURITY.md](SECURITY.md).

