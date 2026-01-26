# BlazeDB Interview Preparation Guide

**Complete guide to explaining BlazeDB's architecture, components, and trade-offs in technical interviews.**

---

## Table of Contents

1. [30-Second Elevator Pitch](#30-second-elevator-pitch)
2. [High-Level Architecture](#high-level-architecture)
3. [Core Components Deep Dive](#core-components-deep-dive)
4. [Key Design Decisions & Trade-offs](#key-design-decisions--trade-offs)
5. [Strengths & Weaknesses](#strengths--weaknesses)
6. [When to Use vs. Not Use](#when-to-use-vs-not-use)
7. [Common Interview Questions](#common-interview-questions)
8. [Technical Deep Dives](#technical-deep-dives)

---

## 30-Second Elevator Pitch

**"BlazeDB is a Swift-native, embedded database designed for local-first applications. It combines MVCC concurrency control, write-ahead logging, per-page encryption, and a custom binary protocol in a vertically integrated system. Unlike SQLite, it's schema-less with encryption by default. Unlike Realm, it's open-source with built-in distributed sync. The key insight is that when storage, sync, and encoding are designed together, you eliminate impedance mismatches and get predictable performance."**

---

## High-Level Architecture

### The Layered Design

BlazeDB uses a **7-layer architecture** with clear separation of concerns:

```
┌─────────────────────────────────────────┐
│ APPLICATION LAYER                        │
│ BlazeDBClient, SwiftUI (@BlazeQuery)     │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ QUERY & INDEX LAYER                      │
│ QueryBuilder, Optimizer, Planner         │
│ Secondary, Full-Text, Spatial, Vector   │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ MVCC & CONCURRENCY LAYER                 │
│ VersionManager, MVCCTransaction          │
│ Snapshot Isolation, Non-blocking Reads  │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ TRANSACTION & WAL LAYER                  │
│ WriteAheadLog, TransactionLog            │
│ Crash Recovery, Durability              │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ STORAGE ENGINE LAYER                     │
│ PageStore (4KB pages), DynamicCollection │
│ Overflow Pages, Page Reuse               │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ ENCODING & SERIALIZATION                 │
│ BlazeBinary (53% smaller than JSON)      │
│ Type-safe field encoding                 │
└─────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────┐
│ SECURITY & ENCRYPTION                    │
│ AES-256-GCM per-page, ECDH key exchange │
│ Row-Level Security (RLS)                 │
└─────────────────────────────────────────┘
```

**Key Principle:** Each layer has a single responsibility and communicates only with adjacent layers. This enables:
- **Predictable performance** (fixed-size I/O at storage layer)
- **Efficient garbage collection** (page-level granularity)
- **Clear debugging boundaries** (issues isolated to specific layers)

---

## Core Components Deep Dive

### 1. Storage Engine (PageStore + DynamicCollection)

**What it does:**
- Manages schema-less document storage
- Fixed 4KB page-based storage with overflow chains
- Tracks record-to-page mapping via `indexMap: [UUID: [Int]]`

**Why 4KB pages:**
- **OS alignment:** Matches file system block size (macOS, Linux, Windows)
- **Hardware alignment:** Aligns with memory pages and disk sectors
- **Predictable I/O:** Fixed-size operations = consistent performance
- **Encryption efficiency:** AES-GCM works optimally with fixed-size blocks
- **Cache efficiency:** Simple LRU cache with predictable memory usage

**How it works:**
```
Record Insert Flow:
1. Encode record → BlazeBinary (e.g., 500 bytes)
2. Allocate page index (reuse deleted pages if available)
3. Encrypt page (AES-256-GCM with unique nonce)
4. Write to disk at offset = pageIndex × 4096
5. Update indexMap[recordID] = [pageIndex]
6. Update secondary indexes
7. Flush metadata (batched every 100 operations)
```

**Overflow handling:**
- Records >4KB use page chains
- Main page stores first ~4046 bytes + overflow pointer
- Overflow pages linked via headers
- Max record size: 100MB (25,000 pages)

**Performance:**
- Insert: 0.4-0.8ms per record
- Fetch: 0.2-0.5ms per record (0.05-0.15ms with cache hit)
- Cache hit rate: 80-90% for repeated reads

---

### 2. MVCC (Multi-Version Concurrency Control)

**What it does:**
- Provides snapshot isolation for concurrent transactions
- Enables non-blocking reads (readers never block writers)
- Tracks multiple versions per record for conflict detection

**How it works:**
```swift
// Version tracking
versions: [UUID: [RecordVersion]]  // All versions of all records
currentVersion: UInt64              // Global version counter
activeSnapshots: [UInt64: Int]      // Active transaction snapshots

// Transaction flow
1. Begin transaction → capture snapshot version
2. Read operations → read from snapshot (consistent view)
3. Write operations → create new version with incremented version number
4. Commit → check for conflicts (if currentVersion > snapshotVersion, conflict!)
5. GC → removes versions older than oldest active snapshot
```

**Benefits:**
- **50-100x faster** concurrent reads vs. serial
- **2-5x faster** read-while-write vs. blocking
- **No read locks** (writers don't block readers)
- **Automatic conflict detection** (optimistic concurrency)

**Trade-offs:**
- **Memory overhead:** +50-100% vs. single-version (stores multiple versions)
- **GC overhead:** <1ms per 10K versions (acceptable)

---

### 3. Write-Ahead Log (WAL)

**What it does:**
- Provides crash recovery via write-ahead logging
- Batches writes to reduce fsync calls (100 writes or 1.0s threshold)
- Checkpoints pending writes to main file periodically

**How it works:**
```
Write Flow:
1. Write operation → append to WAL (sequential, no fsync)
2. Buffer in memory (pendingWrites array)
3. When threshold reached (100 writes or 1.0s):
   - Batch write all pages to main file
   - Single fsync for entire batch
   - Truncate WAL

Recovery Flow (on startup):
1. Read WAL file
2. Replay committed transactions
3. Discard uncommitted transactions
4. Restore database to consistent state
```

**Benefits:**
- **10-100x fewer fsync calls** vs. immediate writes
- **Crash safety:** All committed writes survive
- **Performance:** WAL append ~0.01ms (no fsync), checkpoint 2-10ms for 100 pages

**Trade-offs:**
- **Recovery time:** 50-200ms for 10K operations (acceptable for startup)
- **WAL file size:** Grows until checkpoint (truncates after)

---

### 4. Query Engine

**What it does:**
- Fluent Swift API (`.where().orderBy().limit()`)
- Cost-based optimization (chooses index if 20% better than sequential scan)
- Supports filters, sorting, pagination, aggregations, joins, subqueries, CTEs

**How it works:**
```
Query Execution:
1. Build query → QueryBuilder (chainable API)
2. Optimize → QueryOptimizer (index selection)
3. Execute → Load records, apply filters, sort, limit
4. Return → QueryResult (records, aggregations, or joined data)
```

**Index types:**
- **Secondary indexes:** Hash-based, compound keys
- **Full-text search:** Inverted index
- **Spatial index:** R-tree for geospatial queries
- **Vector index:** Cosine similarity for semantic search
- **Ordering index:** Sorted index for range queries

**Performance:**
- Indexed queries: 0.1-0.5ms
- Full scans: 5-20ms for 10K records
- Optimization threshold: Uses index if 20% better than sequential scan

---

### 5. Encryption & Security

**What it does:**
- Per-page AES-256-GCM encryption (default)
- Unique nonce per page (prevents replay attacks)
- Authentication tag per page (detects tampering)
- ECDH P-256 key exchange for distributed sync

**How it works:**
```
Encryption Flow:
1. Derive key from password (Argon2id + HKDF)
2. Generate unique nonce per page (12 bytes)
3. Encrypt page data (AES-256-GCM)
4. Append authentication tag (16 bytes)
5. Store: [Header][Nonce][Tag][Ciphertext][Padding]

Decryption Flow:
1. Read encrypted page
2. Extract nonce and tag
3. Decrypt and verify tag
4. Return plaintext (or error if tampered)
```

**Benefits:**
- **Encryption by default** (no configuration needed)
- **Per-page granularity** (selective decryption)
- **Tamper detection** (authentication tags)
- **Secure Enclave integration** (iOS/macOS)

**Trade-offs:**
- **Overhead:** ~37 bytes per page (nonce + tag)
- **Performance:** 0.1ms encryption, 0.05ms decryption per page

---

### 6. BlazeBinary Encoding

**What it does:**
- Custom binary format optimized for Swift types
- 53% smaller than JSON, 17% smaller than CBOR
- Type-safe field encoding

**Why custom format:**
- **Size efficiency:** 53% smaller than JSON
- **Speed:** 48% faster encode/decode than JSON
- **Type safety:** Native Swift type support
- **Deterministic:** Same data → same encoding (for sync)

**Performance:**
- Encoding: 0.03-0.08ms per field
- Decoding: 0.02-0.05ms per field
- Size reduction: 53% vs. JSON

---

## Key Design Decisions & Trade-offs

### 1. Fixed 4KB Pages vs. Variable-Size

**Decision:** Fixed 4KB pages

**Trade-offs:**
- ✅ **Predictable I/O:** Fixed-size operations = consistent performance
- ✅ **OS alignment:** Matches file system block size
- ✅ **Encryption efficiency:** AES-GCM works optimally with fixed blocks
- ✅ **Simple allocation:** Sequential with page reuse
- ❌ **Space waste:** Small records waste padding (mitigated by page reuse)
- ❌ **Overflow overhead:** Large records need multiple I/O operations

**Why not variable-size:**
- Complex allocation algorithms
- Fragmentation management
- Unpredictable I/O patterns
- Harder cache management

---

### 2. MVCC vs. Lock-Based Concurrency

**Decision:** MVCC with snapshot isolation

**Trade-offs:**
- ✅ **Non-blocking reads:** Readers never block writers
- ✅ **High concurrency:** 50-100x faster concurrent reads
- ✅ **Conflict detection:** Automatic optimistic conflict detection
- ❌ **Memory overhead:** +50-100% (stores multiple versions)
- ❌ **GC complexity:** Must track active snapshots

**Why not lock-based:**
- Read-write blocking (poor concurrency)
- Deadlock risk
- Lower throughput

---

### 3. Schema-Less vs. Schema-First

**Decision:** Schema-less with optional type safety

**Trade-offs:**
- ✅ **Zero migrations:** Add fields without schema changes
- ✅ **Flexibility:** Rapid iteration, no downtime
- ✅ **Type safety:** Optional `BlazeDocument` protocol for compile-time safety
- ❌ **Runtime errors:** Type mismatches caught at runtime (unless using `BlazeDocument`)
- ❌ **No foreign keys:** Must enforce relationships in application code

**Why not schema-first:**
- Migration complexity
- Downtime for schema changes
- Less flexibility for rapid iteration

---

### 4. WAL vs. Direct Writes

**Decision:** Write-ahead logging with batched checkpoints

**Trade-offs:**
- ✅ **Crash safety:** All committed writes survive
- ✅ **Performance:** 10-100x fewer fsync calls
- ✅ **Durability:** WAL replay restores state
- ❌ **Recovery time:** 50-200ms for 10K operations on startup
- ❌ **WAL file growth:** Grows until checkpoint

**Why not direct writes:**
- Too many fsync calls (slow)
- No crash recovery
- Poor performance under load

---

### 5. Per-Page Encryption vs. File-Level

**Decision:** Per-page AES-256-GCM encryption

**Trade-offs:**
- ✅ **Selective decryption:** Only decrypt pages you read
- ✅ **Parallel encryption:** Pages encrypted independently
- ✅ **Tamper detection:** Authentication tag per page
- ❌ **Overhead:** ~37 bytes per page (nonce + tag)
- ❌ **Key management:** Must derive key from password

**Why not file-level:**
- Must decrypt entire file to read one record
- No selective access
- Less granular security

---

### 6. Custom Binary Format vs. JSON/CBOR

**Decision:** BlazeBinary custom format

**Trade-offs:**
- ✅ **Size efficiency:** 53% smaller than JSON
- ✅ **Speed:** 48% faster encode/decode
- ✅ **Type safety:** Native Swift type support
- ❌ **Not human-readable:** Requires tools to inspect
- ❌ **Platform-specific:** Swift-only (though format is documented)

**Why not JSON:**
- Too large (53% overhead)
- Too slow (string parsing)
- No type safety

**Why not CBOR:**
- Still 17% larger than BlazeBinary
- Less optimized for Swift types

---

## Strengths & Weaknesses

### Strengths

1. **Encryption by Default**
   - AES-256-GCM per-page encryption
   - Zero configuration required
   - Secure Enclave integration (iOS/macOS)

2. **Schema Flexibility**
   - No migrations needed
   - Add fields without downtime
   - Optional type safety via `BlazeDocument`

3. **Predictable Performance**
   - Fixed-size I/O (4KB pages)
   - Sub-millisecond latency
   - Linear scaling with CPU cores

4. **Swift-Native**
   - Idiomatic Swift APIs
   - Type-safe query builder
   - SwiftUI integration (`@BlazeQuery`)

5. **MVCC Concurrency**
   - Non-blocking reads
   - Snapshot isolation
   - High concurrent throughput

6. **Crash Safety**
   - WAL-based recovery
   - Atomic operations
   - No partial records

---

### Weaknesses

1. **Single-Process Only**
   - Cannot share database across processes
   - File-level locking prevents multi-process access
   - Not suitable for multi-process applications

2. **No SQL Compatibility**
   - Fluent Swift API only
   - No SQL queries
   - Learning curve for SQL users

3. **Newer Technology**
   - Less battle-tested than SQLite (20+ years)
   - Smaller community
   - Fewer Stack Overflow answers

4. **Swift-Only**
   - Requires Swift runtime
   - Not suitable for non-Swift applications
   - Platform-specific (macOS/iOS/Linux)

5. **Network Filesystem Limitations**
   - File locking doesn't work on NFS/SMB
   - Performance degrades on network mounts
   - Not recommended for cloud storage mounts

6. **Limited Distributed Sync**
   - Distributed modules are experimental
   - Not production-ready for multi-node sync
   - Single-writer authority model

---

## When to Use vs. Not Use

### ✅ Use BlazeDB When:

1. **Building Swift Applications**
   - macOS, iOS, Linux Swift apps
   - Want idiomatic Swift APIs
   - Need type-safe query builder

2. **Encryption Required**
   - Sensitive data storage
   - Compliance requirements (HIPAA, GDPR)
   - User privacy concerns

3. **Schema Flexibility Needed**
   - Rapid iteration
   - No downtime for schema changes
   - Dynamic field requirements

4. **Predictable Performance**
   - Sub-millisecond latency requirements
   - Consistent performance under load
   - Real-time applications

5. **Single-Process Applications**
   - Desktop apps
   - Mobile apps
   - CLI tools
   - Single-process server applications

6. **Local-First Architecture**
   - Offline-first apps
   - Multi-device sync (experimental)
   - No external database server

---

### ❌ Don't Use BlazeDB When:

1. **Multi-Process Applications**
   - Multiple processes accessing same database
   - Shared database across services
   - Use PostgreSQL, MySQL instead

2. **SQL Compatibility Required**
   - Need SQL queries
   - Complex joins and subqueries
   - Team familiar with SQL
   - Use SQLite, PostgreSQL instead

3. **Network Filesystems**
   - NFS, SMB, cloud storage mounts
   - File locking doesn't work
   - Use network databases instead

4. **Maximum Compatibility**
   - Need C API
   - Cross-platform (non-Swift)
   - Universal platform support
   - Use SQLite instead

5. **Battle-Tested Stability**
   - Critical production systems
   - Need 20+ years of validation
   - Large community support
   - Use SQLite, PostgreSQL instead

6. **Distributed Workloads**
   - Multi-node distributed systems
   - Need distributed consensus
   - Use distributed databases instead

---

## Common Interview Questions

### Q1: "What is BlazeDB and why does it exist?"

**Answer:**
"BlazeDB is a Swift-native, embedded database designed for local-first applications. It exists because existing solutions like SQLite lack encryption by default and distributed sync, while Realm requires proprietary cloud services. BlazeDB combines MVCC concurrency, write-ahead logging, per-page encryption, and operation-log sync in a vertically integrated system. The key insight is that when storage, sync, and encoding are designed together, you eliminate impedance mismatches and get predictable performance."

**Key points:**
- Swift-native embedded database
- Encryption by default
- Built-in distributed sync (experimental)
- Vertically integrated design

---

### Q2: "How does BlazeDB handle concurrency?"

**Answer:**
"BlazeDB uses MVCC (Multi-Version Concurrency Control) with snapshot isolation. Each transaction reads from a consistent snapshot version, while writers create new versions. This enables non-blocking reads—readers never block writers. The system tracks all versions of records and automatically garbage collects versions older than the oldest active snapshot. This provides 50-100x faster concurrent reads compared to serial execution, with the trade-off of 50-100% memory overhead for storing multiple versions."

**Key points:**
- MVCC with snapshot isolation
- Non-blocking reads
- Version tracking and GC
- Performance vs. memory trade-off

---

### Q3: "Why 4KB pages?"

**Answer:**
"4KB pages align with OS file system block sizes, memory pages, and disk sectors, enabling efficient I/O without read-modify-write cycles. Fixed-size pages provide predictable performance—every read/write is exactly 4KB, making latency consistent. AES-GCM encryption works optimally with fixed-size blocks, and it simplifies cache management with a straightforward LRU cache. The trade-off is space waste for small records, but this is mitigated by page reuse and overflow chains for large records."

**Key points:**
- OS/hardware alignment
- Predictable I/O performance
- Encryption efficiency
- Cache simplicity
- Trade-off: space waste vs. performance

---

### Q4: "How does BlazeDB ensure crash safety?"

**Answer:**
"BlazeDB uses write-ahead logging (WAL) for crash recovery. Writes are first appended to a WAL file sequentially without fsync, then batched and checkpointed to the main file when a threshold is reached (100 writes or 1.0s). On startup, the WAL is replayed to restore committed transactions and discard uncommitted ones. This provides crash safety with 10-100x fewer fsync calls compared to immediate writes. All operations are atomic at the page level, ensuring no partial records."

**Key points:**
- Write-ahead logging
- Batched checkpoints
- WAL replay on startup
- Page-level atomicity
- Performance vs. durability trade-off

---

### Q5: "What are BlazeDB's main limitations?"

**Answer:**
"BlazeDB is single-process only—file-level locking prevents multi-process access. It's not SQL-compatible, using a fluent Swift API instead. It's newer and less battle-tested than SQLite. It's Swift-only, requiring the Swift runtime. Network filesystems aren't supported due to file locking issues. Distributed sync is experimental and not production-ready. However, for single-process Swift applications requiring encryption and schema flexibility, these limitations are acceptable trade-offs for the benefits."

**Key points:**
- Single-process limitation
- No SQL compatibility
- Newer technology
- Swift-only
- Network filesystem issues
- Experimental distributed sync

---

### Q6: "How does BlazeDB compare to SQLite?"

**Answer:**
"BlazeDB has encryption by default, schema-less storage, MVCC concurrency, and Swift-native APIs. SQLite has SQL compatibility, universal platform support, and 20+ years of battle-testing. BlazeDB is better for Swift apps needing encryption and schema flexibility. SQLite is better for SQL compatibility and maximum platform support. Both are excellent embedded databases—the choice depends on requirements."

**Key points:**
- Encryption: BlazeDB default, SQLite optional
- Schema: BlazeDB dynamic, SQLite static
- Concurrency: BlazeDB MVCC, SQLite file-level locking
- API: BlazeDB Swift-native, SQLite SQL/C API
- Maturity: BlazeDB newer, SQLite battle-tested

---

## Technical Deep Dives

### Storage Engine Internals

**Page Allocation:**
```swift
// Sequential allocation with reuse
func allocatePage() -> Int {
    if let reused = deletedPages.popFirst() {
        return reused  // Reuse deleted page
    }
    let page = nextPageIndex
    nextPageIndex += 1
    return page  // Allocate new page
}
```

**Overflow Chain:**
```swift
// Records >4KB use page chains
Main Page: [Data (4042 bytes)][Overflow Pointer (4 bytes)]
Overflow Page 1: [Header (16)][Data (4052 bytes)][Next Pointer (4)]
Overflow Page 2: [Header (16)][Data (remaining)][Next Pointer = 0]
```

**Index Map:**
```swift
// Tracks record → pages mapping
indexMap: [UUID: [Int]]  // Record ID → array of page indices
// Example: [recordID: [5, 6, 7]]  // Main page + 2 overflow pages
```

---

### MVCC Implementation

**Version Tracking:**
```swift
struct RecordVersion {
    let recordID: UUID
    let version: UInt64  // Global version counter
    let pageNumber: Int
    let createdByTransaction: UInt64
    let deletedByTransaction: UInt64
}

// All versions of all records
versions: [UUID: [RecordVersion]]  // Sorted by version number
```

**Snapshot Isolation:**
```swift
// Transaction captures snapshot version
let snapshotVersion = currentVersion

// Reads see consistent snapshot
func read(recordID: UUID) -> Record? {
    let recordVersions = versions[recordID]
    // Find version <= snapshotVersion
    return recordVersions.last { $0.version <= snapshotVersion }
}

// Writes create new version
func write(recordID: UUID, data: Data) {
    currentVersion += 1
    let newVersion = RecordVersion(
        recordID: recordID,
        version: currentVersion,
        pageNumber: allocatePage(),
        createdByTransaction: transactionID
    )
    versions[recordID].append(newVersion)
}
```

**Conflict Detection:**
```swift
// On commit, check for conflicts
func commit() throws {
    for modifiedRecord in modifiedRecords {
        let currentVersion = versions[modifiedRecord.id].last?.version ?? 0
        if currentVersion > snapshotVersion {
            throw ConflictError()  // Someone else modified it!
        }
    }
    // No conflicts, commit succeeds
}
```

---

### Encryption Details

**Key Derivation:**
```swift
// Argon2id + HKDF for key derivation
let salt = generateSalt()
let derivedKey = Argon2id.derive(
    password: password,
    salt: salt,
    iterations: 100_000
)
let encryptionKey = HKDF.derive(
    inputKeyMaterial: derivedKey,
    info: "BlazeDB Encryption Key"
)
```

**Per-Page Encryption:**
```swift
// Each page encrypted independently
func encryptPage(data: Data) -> EncryptedPage {
    let nonce = AES.GCM.Nonce()  // Unique per page
    let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
    return EncryptedPage(
        header: "BZDB",
        version: 0x02,
        nonce: nonce,
        tag: sealedBox.tag,
        ciphertext: sealedBox.ciphertext,
        padding: zerosTo4KB()
    )
}
```

---

## Interview Tips

### Structure Your Answers

1. **Start with the "what"** (what is it?)
2. **Explain the "why"** (why this design?)
3. **Describe the "how"** (how does it work?)
4. **Acknowledge trade-offs** (what are the limitations?)

### Use Concrete Examples

Instead of: "It's fast"
Say: "Insert operations take 0.4-0.8ms, with 80-90% cache hit rate for reads"

Instead of: "It's secure"
Say: "AES-256-GCM encryption per page with unique nonces and authentication tags"

### Show Understanding of Trade-offs

Always mention:
- What you gain
- What you sacrifice
- Why the trade-off is acceptable for the use case

### Be Honest About Limitations

Don't oversell. Acknowledge:
- Single-process limitation
- Newer technology
- Experimental features
- When SQLite might be better

---

## Quick Reference

### Performance Numbers

- **Insert:** 0.4-0.8ms per record
- **Fetch:** 0.2-0.5ms (0.05-0.15ms with cache)
- **Query:** 0.1-0.5ms (indexed), 5-20ms (full scan)
- **Cache hit rate:** 80-90%
- **Concurrent reads:** 50-100x faster than serial

### Limits

- **Max record size:** 100MB
- **Max database size:** ~8.6 TB theoretical, ~1-2 GB practical
- **Page size:** 4096 bytes
- **Cache size:** 1000 pages (~4MB)
- **Max concurrent operations:** 100

### File Structure

- `.blaze` - Main data file (4KB pages)
- `.meta` - Metadata (index map, schema)
- `.meta.indexes` - Secondary indexes
- `txn_log.json` - Write-ahead log

---

**End of Interview Preparation Guide**

For more details, see:
- [Architecture Documentation](Architecture/BLAZEDB_ARCHITECTURE_AND_LIMITS.md)
- [Developer Guide](DEVELOPER_GUIDE.md)
- [Safety Model](Guarantees/SAFETY_MODEL.md)
- [Why Not SQLite](GettingStarted/WHY_NOT_SQLITE.md)
