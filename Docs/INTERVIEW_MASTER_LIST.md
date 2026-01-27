# BlazeDB Interview Question Master List - Complete Answers

**Purpose:** Exhaustive, no-BS answers to every question an ASE hiring manager could ask about BlazeDB.

**How to Use:**
- You are NOT expected to answer all of these in an interview
- You ARE expected to know they exist and answer one layer deep
- Stop early, go deeper only if pulled
- This list is for confidence, not memorization

**If you can comfortably reason through 60-70% of this list, you are operating at the level they're interviewing for.**

---

**Note:** This is a comprehensive document. Each section provides detailed answers with code references. For quick reference, see:
- [Walkthrough Checklist](WALKTHROUGH_CHECKLIST.md) - Code walkthrough
- [Interview Preparation](INTERVIEW_PREPARATION.md) - High-level overview
- [Why Each Part Exists](WHY_EACH_PART_EXISTS.md) - Deep rationale

---

## Table of Contents

1. [Motivation & Scope](#1-motivation--scope)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Storage Engine / Page Store](#3-storage-engine--page-store)
4. [WAL (Write-Ahead Log)](#4-wal-write-ahead-log)
5. [Transactions & ACID](#5-transactions--acid)
6. [Concurrency Model](#6-concurrency-model)
7. [Encryption & Security](#7-encryption--security)
8. [Serialization / BlazeBinary Format](#8-serialization--blazebinary-format)
9. [TCP Protocol (BlazeBinary over TCP)](#9-tcp-protocol-blazebinary-over-tcp)
10. [File I/O & OS Interaction](#10-file-io--os-interaction)
11. [Performance & Measurement](#11-performance--measurement)
12. [Testing Strategy](#12-testing-strategy)
13. [Failure Modes](#13-failure-modes)
14. [Tradeoffs & Regrets](#14-tradeoffs--regrets)
15. [Comparison Questions](#15-comparison-questions)
16. [Operational & Real-World Use](#16-operational--real-world-use)
17. [Scaling & Future Work](#17-scaling--future-work)
18. [Meta / Judgment Questions](#18-meta--judgment-questions)

---


## 1. Motivation & Scope

### Why did BlazeDB exist?

**Answer:** BlazeDB exists to fill a gap in the Swift ecosystem: a local-first database that combines ACID transactions, encryption by default, schema-less storage, and distributed sync in a single vertically-integrated system.

**The Problem:**
- SQLite: C library, not Swift-native, no built-in encryption, requires migrations
- Realm: Proprietary, requires cloud service, vendor lock-in  
- CoreData: Complex, Apple-only, no sync mechanism
- None provide operation-log-based synchronization with cryptographic handshakes

**The Insight:** When storage engine, sync layer, and binary protocol are designed together, you eliminate impedance mismatches. Separate components create overhead—JSON serialization, encryption applied as afterthought, sync protocols that don't understand storage model.

**Code Reference:** `Docs/GettingStarted/WHY_BLAZEDB_EXISTS.md:1-11`

---

### What problem were you trying to understand, not solve?

**Answer:** I was trying to understand how to build a database system where correctness, performance, and security are first-class concerns from day one, not bolted on later. The question was: "Can you build a database that's both simple to use and production-ready?"

**What I learned:**
- Correctness requires explicit guarantees (WAL, MVCC, encryption)
- Performance requires careful I/O design (mmap, batched fsync)
- Security requires integration with storage (per-page encryption, not file-level)

**The understanding:** Most databases optimize for one dimension (speed OR safety OR simplicity). BlazeDB optimizes for all three by making them foundational, not optional.

---

### Why build instead of using SQLite/RocksDB/etc.?

**Answer:** Each existing solution had fundamental limitations:

**SQLite:** C library (not Swift-native), schema-based (migrations required), no built-in encryption, no distributed sync

**RocksDB:** Key-value only (no query DSL), C++ library (Swift interop overhead), no transactions, no encryption

**Realm:** Proprietary (vendor lock-in), requires cloud service (not local-first), closed source (can't audit)

**BlazeDB's advantage:** Vertical integration means storage, sync, and encoding are designed together. No impedance mismatches, no performance penalties from conversions.

**Code Reference:** `Docs/GettingStarted/WHY_NOT_SQLITE.md`

---

### What was explicitly out of scope?

**Answer:**

1. **Multi-process concurrent access** - Single-writer only (file-level locking via `flock()`)
   - Code: `BlazeDB/Storage/PageStore.swift:138` - `LOCK_EX | LOCK_NB`
   - Rationale: Simplifies concurrency model, prevents corruption

2. **SQL compatibility** - No SQL parser, no joins, no complex queries
   - Rationale: Focus on schema-less document store with simple query DSL

3. **Distributed consensus** - No Raft/Paxos, no automatic leader election
   - Rationale: Hub-and-spoke or P2P sync, not distributed database

4. **Automatic migrations** - Schema-less means no migrations needed
   - Rationale: Dynamic fields eliminate migration complexity

5. **Background workers** - No async background compaction, no background indexing
   - Rationale: Keep system simple, explicit operations

**Code Reference:** `README.md:211-216`

---

### Who is this system not for?

**Answer:**

1. **Multi-process applications** - Single-writer only
2. **SQL-dependent applications** - No SQL parser
3. **Non-Swift applications** - Swift-native, no C/C++ bindings
4. **Battle-tested stability seekers** - New project (2025), not 20+ years like SQLite
5. **Maximum raw performance seekers** - Optimized for correctness + performance, not raw speed

---

### What assumptions did you make up front?

**Answer:**

1. **Single-writer assumption** - Only one process can write at a time
   - Enforced via `flock()` with `LOCK_EX | LOCK_NB`
   - Code: `BlazeDB/Storage/PageStore.swift:138`

2. **Local-first assumption** - Database is primarily local, sync is secondary

3. **Swift-only assumption** - No C/C++ bindings, Swift-native API

4. **Encryption-by-default assumption** - All data encrypted at rest

5. **Schema-less assumption** - No fixed schema, dynamic fields

---

### Which assumptions changed over time?

**Answer:**

1. **MVCC concurrency** - Initially planned simple locking, switched to MVCC for non-blocking reads
   - Code: `BlazeDB/Core/MVCC/MVCCTransaction.swift:22-72`
   - Reason: 50-100x faster concurrent reads

2. **WAL batching** - Initially planned immediate fsync, switched to batched checkpoints
   - Code: `BlazeDB/Storage/WriteAheadLog.swift:25-26` - `checkpointThreshold = 100`, `checkpointInterval = 1.0s`
   - Reason: 10-100x fewer fsync calls

3. **BlazeBinary format** - Initially considered JSON, switched to custom binary format
   - Reason: 53% smaller, 48% faster, deterministic encoding

4. **Per-page encryption** - Initially considered file-level, switched to per-page
   - Reason: Selective decryption, parallel encryption, efficient GC

---

## 2. High-Level Architecture

**Note:** For comprehensive architecture details, see [Interview Preparation - High-Level Architecture](INTERVIEW_PREPARATION.md:28-73) and [Walkthrough Checklist](WALKTHROUGH_CHECKLIST.md:48-210).

### Walk me through the architecture end-to-end.

**Answer:** BlazeDB uses a 7-layer architecture with clear separation of concerns:

```
Application Layer → Query & Index → MVCC & Concurrency → Transaction & WAL → Storage Engine → Encoding & Serialization → Security & Encryption
```

**Data Flow (Insert):**
1. User calls `db.insert(record)`
2. BlazeBinaryEncoder encodes record → bytes
3. PageStore allocates page index
4. AES-GCM encrypts page (unique nonce)
5. WriteAheadLog appends to WAL
6. PageStore writes encrypted page to disk
7. Update indexMap[recordID] = [pageIndex]

**Data Flow (Query):**
1. User calls `db.query().where(...).execute()`
2. QueryBuilder builds filter predicate
3. DynamicCollection fetches records (or uses index)
4. For each record: PageStore reads encrypted page
5. AES-GCM decrypts and verifies tag
6. BlazeBinaryDecoder decodes → Swift object
7. Apply filter, sort, limit → return results

**Code Reference:** `Docs/WHY_EACH_PART_EXISTS.md:700-800` - Complete flow diagrams

---

### Where does data flow start and end?

**Answer:** See [Why Each Part Exists - Complete Flow](WHY_EACH_PART_EXISTS.md:700-800) for detailed step-by-step flows with code references.

**Start:** User API call (`db.insert()` or `db.query()`)
**End:** Disk I/O (encrypted pages) or User (decoded Swift objects)

---

### What are the major layers and why do they exist?

**Answer:** Each layer has single responsibility:

1. **Application Layer** - User-facing API, SwiftUI integration
2. **Query & Index Layer** - Query DSL, index selection, optimization
3. **MVCC & Concurrency Layer** - Snapshot isolation, version management
4. **Transaction & WAL Layer** - ACID guarantees, crash recovery
5. **Storage Engine Layer** - Page-based storage, record mapping
6. **Encoding & Serialization Layer** - BlazeBinary format
7. **Security & Encryption Layer** - Per-page encryption, key management

**Why:** Clear separation enables predictable performance, efficient GC, and clear debugging boundaries.

**Code Reference:** `Docs/INTERVIEW_PREPARATION.md:28-73`

---

### Which layer owns correctness?

**Answer:** **Transaction & WAL Layer** owns correctness:
- Atomicity: All-or-nothing transactions
- Consistency: Valid state invariants
- Isolation: MVCC snapshot isolation
- Durability: WAL replay on crash

**Code:** `BlazeDB/Transactions/TransactionLog.swift:178-253` - `recover()` method

---

### Which layer owns performance?

**Answer:** **Storage Engine Layer** owns performance:
- Fixed-size pages → predictable I/O
- Page cache → fast repeated reads
- Memory-mapped I/O → 10-100x faster reads
- Batched writes → 10-100x fewer fsync calls

**Code:** `BlazeDB/Storage/PageStore+Async.swift:69-120` - `MemoryMappedFile`

---

### Which layer owns durability?

**Answer:** **Transaction & WAL Layer** owns durability:
- WAL records all writes before applying
- fsync at commit boundary
- WAL replay on startup

**Code:** `BlazeDB/Storage/WriteAheadLog.swift:114-155` - `checkpoint()` method

---

### Where are the hard boundaries?

**Answer:**
1. **File-level locking** - Single-writer (enforced by `flock()`)
   - Code: `BlazeDB/Storage/PageStore.swift:138`
2. **Page boundaries** - 4KB fixed-size pages
   - Code: `BlazeDB/Storage/PageStore.swift:88` - `pageSize = 4096`
3. **Transaction boundaries** - begin/commit/rollback
   - Code: `BlazeDB/Exports/BlazeDBClient.swift:1370-1588`
4. **Encryption boundaries** - Per-page encryption
   - Code: `BlazeDB/Storage/PageStore.swift:266` - `let nonce = try AES.GCM.Nonce()`

---

## 3. Storage Engine / Page Store

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 1](WALKTHROUGH_CHECKLIST.md#1-page-store-disk-layout) which covers all page store questions with code references.

### Why fixed-size pages?

**Answer:** Fixed-size pages provide:
1. **Predictable I/O** - Every read/write is exactly 4KB
2. **OS/hardware alignment** - Matches file system blocks, memory pages, disk sectors
3. **Encryption efficiency** - AES-GCM works optimally with fixed-size blocks
4. **Cache simplicity** - LRU cache with fixed-size entries

**Code:** `BlazeDB/Storage/PageStore.swift:88` - `pageSize = 4096`

**Detailed rationale:** `Docs/WHY_EACH_PART_EXISTS.md:31-95`

---

### Why 4KB specifically?

**Answer:** 4KB aligns with:
- **File system block size:** macOS APFS (4KB), Linux ext4 (4KB), Windows NTFS (4KB)
- **Memory pages:** 4KB on most systems
- **Disk sectors:** 4KB on modern SSDs

**Benefits:** No read-modify-write cycles, efficient I/O, optimal encryption

**Trade-off:** Space waste for small records, mitigated by page reuse and overflow chains

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:90-118`

---

### How do you map page IDs to file offsets?

**Answer:** Simple multiplication: `offset = pageIndex × 4096`

**Code:** `BlazeDB/Storage/PageStore.swift:309` - `let offset = UInt64(index * pageSize)`

**Example:** Page 5 = byte offset 20,480 (5 × 4096)

**Invariant:** Page ID × 4096 = byte offset (always true)

---

### How do you detect corruption?

**Answer:** Multiple layers of detection:
1. **Magic bytes** - "BZDB" header (4 bytes) validates page format
2. **AES-GCM authentication tag** - Detects tampering (16-byte tag)
3. **Version byte** - Prevents reading wrong format (0x02 = encrypted)
4. **CRC32 checksum** - Optional corruption detection (99.9% detection)

**Code:** `BlazeDB/Storage/PageStore.swift:392-396` - Magic byte validation
**Code:** `BlazeDB/Storage/PageStore.swift:436-456` - Tag verification

**Tests:** `Tests/BlazeDBTests/Security/EncryptionRoundTripVerificationTests.swift` - Corruption detection

---

### What happens if a page write is torn?

**Answer:** Page writes are atomic (4KB write is single operation). If torn:
- Magic bytes won't match → page read returns `nil`
- AES-GCM tag won't verify → decryption fails with error
- **Recovery:** WAL replay restores correct page

**Code:** `BlazeDB/Storage/PageStore.swift:286-313` - Page format with magic bytes

**Invariant:** Page writes are atomic (OS guarantees 4KB write is atomic)

---

### How do you validate page integrity?

**Answer:** 
1. Check magic bytes "BZDB" (4 bytes)
2. Check version byte (0x02 = encrypted)
3. Verify AES-GCM authentication tag on decryption
4. Validate plaintext length matches stored length

**Code:** `BlazeDB/Storage/PageStore.swift:392-456` - Page validation and decryption

**Tests:** `Tests/BlazeDBTests/Persistence/BlazeCorruptionRecoveryTests.swift` - Header validation

---

### How do pages interact with encryption?

**Answer:** Each page is encrypted independently:
- **Unique nonce per page** (12 bytes, cryptographically random)
- **AES-256-GCM encryption** with authentication tag
- **Page format:** `[Magic][Version][Length][Nonce][Tag][Ciphertext][Padding]`

**Code:** `BlazeDB/Storage/PageStore.swift:264-313` - Encryption flow

**Benefits:** Selective decryption, parallel encryption, efficient GC

**Tests:** `Tests/BlazeDBTests/Security/EncryptionSecurityFullTests.swift:108-147` - Unique nonce per page

---

### What invariants must always hold for a page?

**Answer:**
1. Page ID × 4096 = byte offset in file
2. Every page is exactly 4096 bytes (padded with zeros)
3. Magic bytes "BZDB" must be present for valid page
4. AES-GCM authentication tag must verify for decryption to succeed
5. Each page has unique nonce (prevents replay attacks)

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:184-195`

---

## 4. WAL (Write-Ahead Log)

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 2](WALKTHROUGH_CHECKLIST.md#2-wal-write-ahead-log)

### Why WAL instead of direct writes?

**Answer:** WAL provides crash recovery and atomic commits without killing performance:
- **Crash recovery:** WAL is source of truth during failure
- **Atomic commits:** Commit marker = all-or-nothing boundary
- **Performance:** 10-100x fewer fsync calls (batched checkpoints vs. immediate writes)

**Code:** `BlazeDB/Storage/WriteAheadLog.swift:114-155` - `checkpoint()` method

**Detailed rationale:** `Docs/WHY_EACH_PART_EXISTS.md:98-144`

---

### What does the WAL record?

**Answer:** WAL records page writes before applying to main file:
- **Format:** Page index (4 bytes) + Data length (4 bytes) + Data (variable)
- **Entry types:** `write`, `delete`, `begin`, `commit`, `abort`

**Code:** `BlazeDB/Transactions/TransactionLog.swift:11-16` - Operation enum
**Code:** `BlazeDB/Storage/WriteAheadLog.swift:14-18` - WALEntry structure

---

### How do you mark transaction boundaries?

**Answer:** Transaction boundaries marked by `begin(txID)` and `commit(txID)` / `abort(txID)` entries in WAL.

**Recovery:** Groups operations by transaction ID, applies only committed transactions.

**Code:** `BlazeDB/Transactions/TransactionLog.swift:178-220` - `recover()` method groups by transaction ID

---

### When is fsync called and why?

**Answer:** fsync called at checkpoint boundary:
- **Threshold:** 100 writes OR 1.0 second (whichever comes first)
- **Process:** Batch write all pages, single fsync for entire batch
- **Why:** Durability guarantee - ensures committed writes survive crashes

**Code:** `BlazeDB/Storage/WriteAheadLog.swift:25-26` - `checkpointThreshold = 100`, `checkpointInterval = 1.0s`
**Code:** `BlazeDB/Storage/WriteAheadLog.swift:114-155` - `checkpoint()` method

**Performance:** 10-100x fewer fsync calls vs. immediate writes

---

### What happens if the process crashes mid-write?

**Answer:** 
- **Before commit:** WAL shows no commit → recovery discards changes
- **After commit:** WAL shows commit → recovery replays changes
- **No ambiguity:** Commit marker is the boundary

**Code:** `BlazeDB/Transactions/TransactionLog.swift:178-253` - Recovery logic

**Tests:** `Tests/BlazeDBTests/Transactions/TransactionDurabilityTests.swift` - Crash recovery tests

---

### How does recovery work step-by-step?

**Answer:**
1. Read all WAL entries from `txn_log.json` or `txlog.blz`
2. Group by transaction ID
3. Identify committed transactions (have `commit` marker)
4. Apply only committed transactions to main file
5. Discard uncommitted transactions (no commit marker)
6. Truncate WAL after successful recovery

**Code:** `BlazeDB/Transactions/TransactionLog.swift:178-253` - `recover()` method

**Invariant:** Same WAL → same state (deterministic recovery)

---

### What guarantees does WAL give you?

**Answer:**
1. **Crash recovery:** Committed writes survive crashes
2. **Atomic commits:** All-or-nothing guarantee
3. **Durability:** fsync at checkpoint ensures persistence
4. **Deterministic recovery:** Same WAL → same state

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:344-358`

---

### What does WAL not protect against?

**Answer:**
- **Disk corruption:** Hardware failures can corrupt WAL itself
- **Concurrent writers:** File-level lock prevents, but WAL doesn't handle multi-process
- **Network filesystems:** File locking doesn't work on NFS/SMB
- **Metadata corruption:** WAL protects data pages, but metadata corruption requires rebuild

**Code Reference:** `Docs/Guarantees/SAFETY_MODEL.md:128-163`

---

## 5. Transactions & ACID

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 3](WALKTHROUGH_CHECKLIST.md#3-transactions-acid)

### How do you define a transaction?

**Answer:** A transaction groups operations and produces an atomic commit:
- `beginTransaction()` - Starts transaction, creates backup
- Operations - Logged to WAL, buffered in memory
- `commitTransaction()` - Flush WAL, apply to main file, delete backup
- `rollbackTransaction()` - Restore from backup, discard changes

**Code:** `BlazeDB/Exports/BlazeDBClient.swift:1370-1588` - Transaction API

---

### What does "atomic" mean in your system?

**Answer:** All operations in a transaction succeed or fail together. Implemented via:
- **Backup/restore mechanism:** Backup created on begin, deleted on commit
- **WAL logging:** All operations logged before applying
- **Rollback:** Restore from backup if transaction fails

**Code:** `BlazeDB/Exports/BlazeDBClient.swift:1370-1588` - Transaction implementation

**Tests:** `Tests/BlazeDBIntegrationTests/DataConsistencyACIDTests.swift` - Atomicity tests

---

### How do you guarantee consistency?

**Answer:** 
- **Index updates atomic with data writes** - Indexes updated in same transaction
- **Schema validation prevents invalid states** - Constraints checked before commit
- **Metadata rebuild on corruption** - Can rebuild from data pages

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:488-492`

---

### What isolation level do you provide?

**Answer:** **Snapshot isolation** via MVCC:
- Each transaction sees consistent snapshot from transaction start
- Non-blocking reads (readers never block writers)
- Write-write conflicts detected via version comparison

**Code:** `BlazeDB/Core/MVCC/MVCCTransaction.swift:22-72` - Snapshot isolation

**Tests:** `Tests/BlazeDBTests/MVCC/MVCCIntegrationTests.swift` - Isolation tests

---

### Why MVCC instead of locks?

**Answer:** MVCC provides:
- **50-100x faster concurrent reads** vs. serial execution
- **Non-blocking reads** - readers never block writers
- **No deadlocks** - optimistic concurrency control
- **High throughput** - concurrent access scales with CPU cores

**Trade-off:** +50-100% memory overhead for storing multiple versions

**Code Reference:** `Docs/INTERVIEW_PREPARATION.md:123-154`

---

### How do readers and writers interact?

**Answer:**
- **Readers:** See consistent snapshot (non-blocking)
- **Writers:** Create new versions, detect conflicts on commit
- **No blocking:** Readers never block writers, writers never block readers
- **Conflict detection:** Optimistic - check versions on commit

**Code:** `BlazeDB/Core/MVCC/MVCCTransaction.swift:22-72`

**Tests:** `Tests/BlazeDBTests/MVCC/MVCCIntegrationTests.swift:161-214` - Read-while-write tests

---

### What happens under write contention?

**Answer:** Write-write conflicts detected via version comparison:
- Transaction A reads version 100, writes version 101
- Transaction B reads version 100, writes version 101
- On commit: If current version > snapshot version → conflict error
- **Resolution:** Application retries with latest version

**Code:** `BlazeDB/Core/MVCC/MVCCTransaction.swift` - Conflict detection

---

### How do you roll back a transaction?

**Answer:**
1. Restore database files from backup (created on `beginTransaction()`)
2. Reload in-memory state
3. Discard all pending writes
4. Release file lock

**Code:** `BlazeDB/Exports/BlazeDBClient.swift:1452-1588` - `rollbackTransaction()`

---

## 6. Concurrency Model

### How do you handle concurrent reads?

**Answer:** MVCC snapshot isolation enables non-blocking concurrent reads:
- Each read transaction gets snapshot version
- Reads see consistent state from snapshot
- Multiple readers can read simultaneously
- **50-100x faster** than serial execution

**Code:** `BlazeDB/Core/MVCC/MVCCTransaction.swift:22-72`

**Tests:** `Tests/BlazeDBTests/MVCC/MVCCIntegrationTests.swift:161-214`

---

### How do you handle concurrent writes?

**Answer:** File-level locking prevents concurrent writers:
- `flock()` with `LOCK_EX | LOCK_NB` enforces single-writer
- Concurrent write attempts throw `databaseLocked` error
- **Rationale:** Prevents corruption, simplifies concurrency model

**Code:** `BlazeDB/Storage/PageStore.swift:138` - `flock(fd, LOCK_EX | LOCK_NB)`

---

### Where are locks used, if at all?

**Answer:**
1. **File-level lock** - `flock()` prevents multi-process access
2. **Dispatch queue** - Serializes writes within single process
3. **Actor isolation** - WAL is an actor (Swift 6 concurrency)
4. **No read locks** - MVCC enables lock-free reads

**Code:** `BlazeDB/Storage/PageStore.swift:95` - `queue = DispatchQueue(...)`
**Code:** `BlazeDB/Storage/WriteAheadLog.swift:21` - `actor WriteAheadLog`

---

### What are the biggest concurrency risks?

**Answer:**
1. **Write-write conflicts** - Detected via version comparison
2. **Version GC** - Must not delete versions needed by active snapshots
3. **Index consistency** - Indexes must update atomically with data
4. **Memory pressure** - Multiple versions consume memory

**Mitigation:** Optimistic conflict detection, GC tracks active snapshots, atomic index updates

---

### How do you test concurrency bugs?

**Answer:**
- **Concurrency torture tests** - 50-200 concurrent writers
- **MVCC integration tests** - Concurrent reads and writes
- **Stress tests** - Thousands of random operations
- **Property-based tests** - Model-based validation

**Tests:** `Tests/BlazeDBTests/MVCC/MVCCIntegrationTests.swift`, `Tests/BlazeDBTests/Concurrency/ConcurrencyTortureTests.swift`

---

### What race conditions worried you most?

**Answer:**
1. **Version GC race** - Deleting versions needed by active snapshots
2. **Index update race** - Indexes out of sync with data
3. **WAL checkpoint race** - Checkpointing while writes in progress
4. **Snapshot version race** - Snapshot version changing during read

**Mitigation:** GC tracks active snapshots, atomic index updates, actor isolation for WAL

---

### What did you simplify to keep concurrency sane?

**Answer:**
1. **Single-writer** - File-level lock prevents multi-process (simplifies greatly)
2. **No distributed consensus** - Hub-and-spoke sync, not distributed database
3. **Optimistic concurrency** - Detect conflicts, don't prevent them
4. **Snapshot isolation** - Simpler than serializable isolation

**Trade-off:** Less concurrency, but simpler and correct

---

## 7. Encryption & Security

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 4](WALKTHROUGH_CHECKLIST.md#4-encryption-aes-gcm)

### Why encrypt at the page level?

**Answer:** Per-page encryption enables:
- **Selective decryption** - Only decrypt pages you read
- **Parallel encryption** - Encrypt pages independently
- **Efficient GC** - Delete encrypted pages without decryption
- **Granular access** - Read one record without decrypting entire file

**Code:** `BlazeDB/Storage/PageStore.swift:264-313` - Per-page encryption

---

### Why AES-GCM?

**Answer:** AES-256-GCM provides:
- **Confidentiality** - Data encrypted (can't read without key)
- **Integrity** - Authentication tag detects tampering
- **Authenticity** - Tag proves data came from someone with key
- **Industry standard** - Widely used, well-tested

**Code:** `BlazeDB/Storage/PageStore.swift:269` - `AES.GCM.seal()`

---

### How are nonces generated?

**Answer:** Cryptographically random nonces via `AES.GCM.Nonce()`:
- 12 bytes (96 bits)
- Unique per page
- Prevents replay attacks
- Stored in page header

**Code:** `BlazeDB/Storage/PageStore.swift:266` - `let nonce = try AES.GCM.Nonce()`

**Tests:** `Tests/BlazeDBTests/Security/EncryptionSecurityFullTests.swift:108-147` - Unique nonce test

---

### What happens if a page is tampered with?

**Answer:** AES-GCM authentication tag verification fails:
- Decryption throws error
- Page read returns error (not silent failure)
- Corruption detected immediately

**Code:** `BlazeDB/Storage/PageStore.swift:436-456` - Tag verification

**Tests:** `Tests/BlazeDBTests/Security/EncryptionRoundTripVerificationTests.swift` - Tampering detection

---

### How do you detect wrong keys?

**Answer:** AES-GCM authentication tag verification fails with wrong key:
- Tag computed with correct key, verified with wrong key → fails
- Decryption throws error immediately
- No silent failures

**Code:** `BlazeDB/Storage/PageStore.swift:436-456` - Decryption with tag verification

**Tests:** `Tests/BlazeDBTests/Security/EncryptionRoundTripVerificationTests.swift:595-604` - Wrong key test

---

### What security guarantees do you provide?

**Answer:**
1. **Confidentiality** - Encrypted data unreadable without key
2. **Integrity** - Authentication tag detects tampering
3. **Authenticity** - Tag proves data source
4. **Replay protection** - Unique nonces prevent replay attacks

**Code Reference:** `Docs/Security/SECURITY.md:1-67`

---

### What security guarantees do you not provide?

**Answer:**
1. **Key management** - Keys stored in memory (not hardware-backed by default)
2. **Side-channel attacks** - No protection against timing attacks
3. **Physical access** - If device compromised, keys in memory are vulnerable
4. **Network security** - Encryption is at-rest only (network encryption separate)

**Note:** Secure Enclave integration available on iOS/macOS for hardware-backed keys

---

### How does encryption affect performance?

**Answer:**
- **Encryption overhead:** ~0.1-0.2ms per page (AES-GCM is fast)
- **Decryption overhead:** ~0.1-0.2ms per page
- **Total impact:** ~20-30% overhead vs. unencrypted
- **Acceptable trade-off:** Security worth the performance cost

**Code Reference:** `Docs/Performance/PERFORMANCE.md`

---

## 8. Serialization / BlazeBinary Format

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 5](WALKTHROUGH_CHECKLIST.md#5-serialization--record-format)

### Why a custom binary format?

**Answer:** BlazeBinary provides:
- **53% smaller** than JSON (no string overhead)
- **48% faster** encode/decode (no string parsing)
- **Deterministic encoding** (sorted fields, same data → same encoding)
- **Type safety** (type tags prevent ambiguity)

**Code:** `BlazeDB/Utils/BlazeBinaryEncoder.swift:55-94` - `encode()` method

---

### Why not JSON / CBOR / Protobuf?

**Answer:**
- **JSON:** 53% larger, 48% slower, non-deterministic
- **CBOR:** 17% larger, slower, less type safety
- **Protobuf:** Requires schema, not schema-less friendly

**BlazeBinary advantage:** Designed for schema-less document store with deterministic encoding

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:715-828`

---

### How is the record layout defined?

**Answer:** BlazeBinary format:
```
Header (8 bytes):
├── Magic: "BLAZE" (5 bytes)
├── Version: 0x01 (no CRC) or 0x02 (with CRC)
└── Field Count: UInt16 (2 bytes, big-endian)

Fields (variable):
├── Field 1: [Key][Type][Value]
├── Field 2: [Key][Type][Value]
└── ...

Optional CRC32 (4 bytes):
└── Checksum (if version 0x02)
```

**Code:** `BlazeDB/Utils/BlazeBinaryEncoder.swift:55-94`

---

### How do you handle versioning?

**Answer:** Version byte in header:
- `0x01` - v1 (no CRC)
- `0x02` - v2 (with CRC32)
- Decoder auto-detects version
- Backward compatible: v2 decoder can read v1 data

**Code:** `BlazeDB/Utils/BlazeBinaryEncoder.swift:62-66` - Version byte

---

### How do you detect corrupted records?

**Answer:**
1. **Magic bytes** - "BLAZE" must be present
2. **Version byte** - Must be 0x01 or 0x02
3. **CRC32 checksum** - Optional (99.9% detection if enabled)
4. **Type tags** - Invalid type tags detected
5. **Bounds checking** - All reads check bounds

**Code:** `BlazeDB/Utils/BlazeBinaryDecoder.swift:105-170` - Decoding with validation

**Tests:** `Tests/BlazeDBTests/Codec/BlazeBinaryReliabilityTests.swift` - Corruption detection

---

### How do you ensure deterministic decoding?

**Answer:** Fields are sorted by key before encoding:
- Same data → same encoding (deterministic)
- Required for distributed sync (deterministic hashing)
- No ambiguity in encoding

**Code:** `BlazeDB/Utils/BlazeBinaryEncoder.swift:76` - Field sorting

---

### What tradeoffs did you accept?

**Answer:**
1. **No human readability** - Binary format, not text
2. **Version evolution** - Must handle version compatibility
3. **Type tags overhead** - 1 byte per field
4. **No compression** - Raw binary (compression separate layer)

**Trade-off:** Performance and determinism worth the complexity

---

### How much smaller/faster is it and why?

**Answer:**
- **53% smaller** than JSON (measured)
- **48% faster** encode/decode (measured)
- **Why:** No string overhead, direct binary encoding, no parsing

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:717-764`

---

## 9. TCP Protocol (BlazeBinary over TCP)

**Note:** For comprehensive answers, see [Walkthrough Checklist Section 6](WALKTHROUGH_CHECKLIST.md#6-blazebinary-tcp-protocol)

### Why TCP?

**Answer:** TCP provides:
- **Reliable delivery** - Guaranteed message delivery
- **Ordered delivery** - Messages arrive in order
- **Stream protocol** - Handles fragmentation automatically
- **Universal support** - Works everywhere

**Alternative considered:** HTTP/gRPC, but TCP is simpler for custom protocol

---

### Why not HTTP or gRPC?

**Answer:**
- **HTTP:** Overhead (headers, status codes), not needed for internal protocol
- **gRPC:** Requires Protobuf schemas, not schema-less friendly
- **TCP:** Lower overhead, full control over protocol

**Trade-off:** Must implement framing ourselves, but worth it for performance

---

### How do you frame messages?

**Answer:** Length-prefixed frames:
```
Frame Structure:
├── Type (1 byte): FrameType enum
├── Length (4 bytes, big-endian): Payload size
└── Payload (variable): BlazeBinary-encoded operations
```

**Code:** `BlazeDB/Distributed/SecureConnection.swift:330-338` - `sendFrame()`

---

### How do you handle partial reads?

**Answer:** Buffering via `receiveBuffer`:
- Accumulates data until full message received
- `readExactly()` blocks until all bytes received
- Handles TCP stream nature (packets may be split)

**Code:** `BlazeDB/Distributed/SecureConnection.swift:359-376` - `readExactly()`

---

### Why a length-prefixed format?

**Answer:** 
- **Message boundaries** - Know where one message ends, next begins
- **Exact reads** - Read exactly `length` bytes
- **Buffer overflow prevention** - Validate length before reading

**Code:** `BlazeDB/Distributed/SecureConnection.swift:340-355` - `receiveFrame()`

---

### How does the decoder work?

**Answer:**
1. Read type (1 byte)
2. Read length (4 bytes, big-endian)
3. Validate length (prevent buffer overflow)
4. Read payload (exactly `length` bytes)
5. Decode payload as BlazeBinary operations

**Code:** `BlazeDB/Distributed/SecureConnection.swift:340-355` - `receiveFrame()`

---

### Why an FSM?

**Answer:** Frame-based protocol requires state machine:
- **States:** Waiting for type, waiting for length, waiting for payload
- **Transitions:** Type → Length → Payload → Complete
- **Error handling:** Invalid state transitions → error

**Note:** Current implementation uses buffering, not explicit FSM (simpler)

---

### How do you prevent invalid lengths?

**Answer:**
- Length read as `UInt32` (max 4GB)
- Validate against available memory
- Reject obviously invalid lengths (e.g., > file size)
- **Note:** No explicit max length check (relies on available memory)

**Code:** `BlazeDB/Distributed/SecureConnection.swift:333` - Length read

---

### What are the protocol's limitations?

**Answer:**
1. **Single connection** - No connection pooling
2. **No flow control** - Relies on TCP flow control
3. **No compression** - Compression separate layer
4. **No multiplexing** - One request/response per connection

**Future work:** Connection pooling, flow control, compression

---

### How would you evolve it safely?

**Answer:**
1. **Version negotiation** - Handshake includes protocol version
2. **Backward compatibility** - Old clients can connect to new servers
3. **Feature flags** - Negotiate capabilities during handshake
4. **Graceful degradation** - Fall back to older protocol if needed

**Code Reference:** `BlazeDB/Distributed/SecureConnection.swift:356-393` - Handshake

---

## 10. File I/O & OS Interaction

### Why use mmap?

**Answer:** Memory-mapped I/O provides:
- **10-100x faster reads** - No syscall overhead
- **No copy overhead** - OS handles paging
- **Automatic cache management** - OS page cache
- **Efficient for sequential reads** - Prefetching works

**Code:** `BlazeDB/Storage/PageStore+Async.swift:69-120` - `MemoryMappedFile`

---

### What are the risks of mmap?

**Answer:**
1. **Durability** - Must explicitly fsync for durability
2. **Memory pressure** - OS may evict pages under memory pressure
3. **Platform support** - Not available on all platforms (Linux fallback)
4. **File size changes** - Must remap if file grows

**Mitigation:** Explicit fsync at commit, fallback to buffered reads

---

### When do you use mmap vs read/write?

**Answer:**
- **mmap:** Reads (when available), sequential access
- **read/write:** Writes (mmap writes are complex), fallback on unsupported platforms

**Code:** `BlazeDB/Storage/PageStore+Async.swift:201-220` - Auto-enable mmap on first read

---

### Why batch fsync calls?

**Answer:** fsync is expensive (0.5-2ms each):
- **Batching:** 1 fsync for 100 writes = 10-100x fewer calls
- **Performance:** 2-10ms for 100 pages vs. 50-500ms for individual fsyncs
- **Trade-off:** Slight latency increase (1.0s max) for massive throughput gain

**Code:** `BlazeDB/Storage/WriteAheadLog.swift:114-155` - Batched checkpoint

---

### What does fsync actually guarantee?

**Answer:** fsync guarantees:
- **Durability** - Data written to disk (not just OS buffer)
- **Ordering** - Writes complete in order
- **Crash safety** - Data survives power loss

**Does NOT guarantee:**
- **Hardware durability** - Disk may fail
- **File system durability** - FS may corrupt
- **Immediate write** - May be buffered by disk controller

---

### How does the OS page cache factor in?

**Answer:**
- **Reads:** OS page cache speeds up repeated reads
- **Writes:** OS buffers writes until fsync
- **mmap:** Uses OS page cache automatically
- **Trade-off:** Faster reads, but must fsync for durability

**Code Reference:** `Docs/WALKTHROUGH_CHECKLIST.md:1171-1223`

---

### What assumptions do you make about the filesystem?

**Answer:**
1. **Atomic page writes** - 4KB write is atomic
2. **File locking works** - `flock()` available and reliable
3. **Sequential writes** - WAL benefits from sequential writes
4. **No network filesystems** - File locking doesn't work on NFS/SMB

**Code Reference:** `Docs/Guarantees/SAFETY_MODEL.md:128-163`

---

### What happens on different filesystems?

**Answer:**
- **APFS (macOS):** Full support, optimal performance
- **ext4 (Linux):** Full support, good performance
- **NFS/SMB:** File locking doesn't work, not recommended
- **FAT32:** No file locking, not supported

**Code:** `BlazeDB/Storage/PageStore.swift:136-177` - Platform-specific locking

---

## 11. Performance & Measurement

### What were your performance goals?

**Answer:**
- **Sub-millisecond latency** - Most operations < 1ms
- **Linear scaling** - Throughput scales with CPU cores
- **Predictable performance** - No unpredictable spikes
- **Memory efficiency** - Bounded memory usage

**Code Reference:** `Docs/Performance/PERFORMANCE.md:1-70`

---

### What were your bottlenecks?

**Answer:**
1. **Disk I/O** - Slowest operation (0.2-0.5ms per page)
2. **fsync calls** - Expensive (0.5-2ms each)
3. **Encryption** - Overhead (~0.1-0.2ms per page)
4. **Serialization** - Encoding/decoding overhead

**Mitigation:** mmap reads, batched fsync, efficient encryption, optimized encoding

---

### How did you measure throughput?

**Answer:**
- **Benchmarks** - Measure operations per second
- **Stress tests** - Thousands of operations
- **Multi-core tests** - Measure scaling with cores
- **Real workloads** - Measure actual application performance

**Code:** `Tests/BlazeDBTests/Performance/BlazeDBEngineBenchmarks.swift`

---

### How did you measure latency?

**Answer:**
- **Micro-benchmarks** - Single operation timing
- **Percentile measurements** - p50, p95, p99 latencies
- **Real-world scenarios** - Actual query latencies
- **Comparison** - vs. SQLite, JSON encoding

**Code Reference:** `Docs/Performance/PERFORMANCE_METRICS.md`

---

### How did concurrency affect results?

**Answer:**
- **Concurrent reads:** 50-100x faster than serial
- **Concurrent writes:** Limited by file lock (single-writer)
- **Read-while-write:** 2-5x faster than blocking
- **Scaling:** Linear with CPU cores up to 8 cores

**Code Reference:** `Docs/Architecture/ARCHITECTURE_DETAILED.md:454-525`

---

### What do the numbers actually mean?

**Answer:**
- **Insert:** 0.4-0.8ms = 1,200-2,500 ops/sec (single core)
- **Fetch:** 0.2-0.5ms = 2,500-5,000 ops/sec (single core)
- **Query:** 0.1-0.5ms (indexed), 5-20ms (full scan)
- **Cache hit:** 80-90% hit rate for repeated reads

**Code Reference:** `Docs/Performance/PERFORMANCE_METRICS.md:1-30`

---

### What could make the measurements wrong?

**Answer:**
1. **Warm cache** - First read slower than cached reads
2. **Disk speed** - SSD vs. HDD makes huge difference
3. **System load** - Other processes affect measurements
4. **Measurement overhead** - Timing code adds overhead
5. **Platform differences** - macOS vs. Linux performance varies

**Mitigation:** Multiple runs, cold cache tests, controlled environment

---

### How would you measure this in production?

**Answer:**
1. **Instrumentation** - Add timing to all operations
2. **Metrics collection** - Export to metrics system (Prometheus, etc.)
3. **Percentile tracking** - Track p50, p95, p99
4. **Alerting** - Alert on performance regressions
5. **Profiling** - Use Instruments/DTrace for deep profiling

**Code Reference:** `Docs/Performance/PERFORMANCE.md:56-70`

---

## 12. Testing Strategy

### What kinds of tests did you write?

**Answer:**
1. **Unit tests** - Individual component testing
2. **Integration tests** - End-to-end scenarios
3. **Property-based tests** - Model-based validation
4. **Chaos tests** - Random operations, crash simulation
5. **Concurrency tests** - Concurrent access patterns
6. **Performance tests** - Latency and throughput benchmarks

**Total:** 2,167+ test methods across 170+ test files

**Code Reference:** `Docs/Testing/PRODUCTION_READINESS_ASSESSMENT.md`

---

### How do you test crash recovery?

**Answer:**
1. **Crash simulation** - Kill process mid-operation
2. **WAL replay** - Verify committed transactions restored
3. **Uncommitted rollback** - Verify uncommitted transactions discarded
4. **Corruption scenarios** - Test recovery from corrupted state

**Tests:** `Tests/BlazeDBTests/Transactions/TransactionDurabilityTests.swift`

---

### How do you test durability?

**Answer:**
1. **Crash tests** - Power loss simulation
2. **fsync verification** - Verify data on disk after fsync
3. **WAL replay** - Verify committed data survives crash
4. **Recovery tests** - Verify database opens after crash

**Tests:** `Tests/BlazeDBIntegrationTests/DataConsistencyACIDTests.swift`

---

### How do you test corruption?

**Answer:**
1. **Corruption injection** - Corrupt magic bytes, ciphertext, tags
2. **Detection tests** - Verify corruption detected
3. **Recovery tests** - Verify recovery from corruption
4. **Metadata rebuild** - Test rebuilding from data pages

**Tests:** `Tests/BlazeDBTests/Security/EncryptionRoundTripVerificationTests.swift`

---

### How do you test concurrency?

**Answer:**
1. **Concurrent reads** - Multiple readers simultaneously
2. **Concurrent writes** - Multiple writers (should fail with lock)
3. **Read-while-write** - Readers during write operations
4. **Stress tests** - Thousands of concurrent operations

**Tests:** `Tests/BlazeDBTests/MVCC/MVCCIntegrationTests.swift`

---

### What can tests not prove?

**Answer:**
1. **All possible inputs** - Infinite input space
2. **Hardware failures** - Disk corruption, RAM errors
3. **Platform-specific bugs** - macOS vs. Linux differences
4. **Real-world data patterns** - Production data shapes
5. **Extreme scale** - Very large databases (>1GB)

**Mitigation:** Property-based tests, chaos engineering, real-world testing

---

### What bugs escaped tests?

**Answer:** Known bugs that were caught and fixed:
1. **AES-GCM ciphertext padding** - Fixed in v0.1.0
2. **10,000× fsync bug** - Fixed with batched fsync
3. **Auto-migration corruption** - Fixed with validation
4. **Excessive metadata I/O** - Fixed with batching

**Code Reference:** `Docs/Archive/CRITICAL_BUGS_FIXED_2025-11-12.md`

---

### How did tests influence design?

**Answer:**
1. **Testability** - Designed for easy testing (dependency injection)
2. **Observability** - Added metrics for testability
3. **Determinism** - Made operations deterministic for testing
4. **Isolation** - Clear boundaries for unit testing

**Example:** WAL separated from PageStore for independent testing

---

## 13. Failure Modes

**Note:** For comprehensive answers, see [Safety Model](Guarantees/SAFETY_MODEL.md)

### What happens if the disk fills up?

**Answer:**
- Write operations fail with `BlazeDBError.ioFailure`
- Database remains in consistent state
- No corruption occurs
- **Recovery:** Free disk space, retry operation

**Code Reference:** `Docs/Guarantees/SAFETY_MODEL.md:130-141`

---

### What happens if fsync fails?

**Answer:**
- fsync failure throws error
- Durability not guaranteed
- Transaction may be rolled back
- **Recovery:** Check disk health, retry operation

**Code:** `BlazeDB/Storage/WriteAheadLog.swift:114-155` - Error handling

---

### What happens if the WAL is corrupted?

**Answer:**
- WAL corruption detected on read
- Recovery attempts to read valid entries
- Invalid entries skipped
- **Recovery:** Restore from backup, or rebuild from data pages

**Code:** `BlazeDB/Transactions/TransactionLog.swift:178-253` - Recovery with error handling

---

### What happens if encryption fails?

**Answer:**
- Decryption failure throws error
- Page read returns error (not silent)
- Corruption detected immediately
- **Recovery:** Check key, restore from backup

**Code:** `BlazeDB/Storage/PageStore.swift:436-456` - Decryption error handling

---

### What happens if the process crashes repeatedly?

**Answer:**
- Each crash triggers WAL replay
- Committed data restored each time
- Uncommitted data discarded each time
- **Risk:** If WAL itself corrupted, recovery may fail
- **Mitigation:** Backup before major operations

---

### What happens under partial writes?

**Answer:**
- Page writes are atomic (4KB single operation)
- Partial page writes detected via magic bytes
- WAL replay restores correct page
- **Mitigation:** Page-level atomicity prevents partial records

**Code:** `BlazeDB/Storage/PageStore.swift:286-313` - Page format validation

---

### How does the system fail?

**Answer:**
1. **Gracefully** - Errors thrown, no silent failures
2. **Consistently** - Database remains in valid state
3. **Detectably** - Errors are clear and actionable
4. **Recoverably** - Can recover from most failures

**Code Reference:** `Docs/Guarantees/SAFETY_MODEL.md:128-163`

---

### How does it recover?

**Answer:**
1. **WAL replay** - Restore committed transactions
2. **Metadata rebuild** - Rebuild from data pages if needed
3. **Corruption detection** - Detect and report corruption
4. **Backup restore** - Restore from backup if available

**Code:** `BlazeDB/Exports/BlazeDBClient.swift:350-360` - Recovery on startup

---

## 14. Tradeoffs & Regrets

### What decision was the hardest?

**Answer:** **Single-writer vs. multi-writer:**
- **Decision:** Single-writer (file-level lock)
- **Why:** Simplifies concurrency model, prevents corruption
- **Trade-off:** Cannot share database across processes
- **Regret level:** Low - correct trade-off for use case

---

### What tradeoff do you still think about?

**Answer:** **MVCC memory overhead:**
- **Trade-off:** +50-100% memory for multiple versions
- **Benefit:** 50-100x faster concurrent reads
- **Still thinking:** Could GC be more aggressive? Could versions be compressed?

**Code Reference:** `Docs/Architecture/ARCHITECTURE_DETAILED.md:454-525`

---

### What would you change if you rewrote it?

**Answer:**
1. **Start with MVCC** - Don't add it later (architectural change)
2. **Better observability** - More metrics from day one
3. **Property-based tests earlier** - Catch bugs sooner
4. **Documentation-driven** - Write docs before code

**But:** Overall architecture is sound, changes would be incremental

---

### What did you intentionally not optimize?

**Answer:**
1. **Compression** - Separate layer, not in core
2. **Background workers** - Keep system simple
3. **Distributed consensus** - Out of scope
4. **SQL compatibility** - Not the goal

**Rationale:** Focus on core correctness and performance, not features

---

### Where did you choose simplicity over power?

**Answer:**
1. **Single-writer** - Simpler than multi-writer coordination
2. **Schema-less** - Simpler than migrations
3. **In-memory queries** - Simpler than query planner
4. **Explicit transactions** - Simpler than auto-commit

**Trade-off:** Less powerful, but easier to understand and maintain

---

### What technical debt exists?

**Answer:**
1. **Distributed modules** - Not Swift 6 compliant, experimental
2. **Test execution** - Blocked by distributed module errors
3. **Documentation** - Some areas need more detail
4. **Performance profiling** - Need more production metrics

**Priority:** Fix distributed modules, improve test execution

---

## 15. Comparison Questions

### How is BlazeDB similar to SQLite?

**Answer:**
- **Embedded database** - Runs in-process
- **ACID transactions** - Full ACID guarantees
- **File-based** - Single file database
- **Local-first** - No external server

**Code Reference:** `Docs/GettingStarted/WHY_NOT_SQLITE.md`

---

### How is it different?

**Answer:**
- **Encryption** - BlazeDB default, SQLite optional
- **Schema** - BlazeDB schema-less, SQLite schema-based
- **Concurrency** - BlazeDB MVCC, SQLite file-level locking
- **API** - BlazeDB Swift-native, SQLite SQL/C API
- **Sync** - BlazeDB built-in (experimental), SQLite none

---

### What does SQLite do better?

**Answer:**
1. **SQL compatibility** - Full SQL support
2. **Platform support** - Universal (C API)
3. **Battle-tested** - 20+ years of production use
4. **Community** - Large community, many resources
5. **Performance** - Highly optimized C code

**Code Reference:** `Docs/GettingStarted/WHY_NOT_SQLITE.md`

---

### What does BlazeDB do better?

**Answer:**
1. **Encryption by default** - Security built-in
2. **Schema flexibility** - No migrations needed
3. **Swift-native** - Idiomatic Swift APIs
4. **MVCC concurrency** - Non-blocking reads
5. **Distributed sync** - Built-in (experimental)

---

### When would you choose one over the other?

**Answer:**
- **Choose BlazeDB:** Swift apps, encryption required, schema flexibility, SwiftUI integration
- **Choose SQLite:** SQL compatibility, maximum platform support, battle-tested stability, C API needed

**Code Reference:** `README.md:203-217`

---

### Why Swift-native?

**Answer:**
- **Type safety** - Swift's type system prevents errors
- **Async/await** - Modern concurrency model
- **SwiftUI integration** - `@BlazeQuery` property wrapper
- **Memory safety** - ARC, no manual memory management
- **Developer experience** - Idiomatic Swift APIs

**Trade-off:** Swift-only, not suitable for non-Swift applications

---

### What does Swift make harder?

**Answer:**
1. **C interop** - Cannot easily call C libraries
2. **Platform support** - Swift not available everywhere
3. **Performance** - Slightly slower than C (acceptable trade-off)
4. **Binary size** - Swift runtime adds overhead

**But:** Benefits (type safety, memory safety) outweigh costs

---

## 16. Operational & Real-World Use

### How would you monitor this in production?

**Answer:**
1. **Health checks** - `db.health()` returns status
2. **Metrics** - Operation counts, latencies, errors
3. **Logging** - Structured logging for debugging
4. **Alerting** - Alert on errors, performance regressions

**Code:** `BlazeDB/Exports/BlazeDBClient.swift` - `health()`, `stats()` methods

---

### What metrics would matter?

**Answer:**
1. **Latency** - p50, p95, p99 operation latencies
2. **Throughput** - Operations per second
3. **Error rate** - Errors per operation
4. **Cache hit rate** - Page cache effectiveness
5. **WAL size** - Pending writes before checkpoint

**Code Reference:** `Docs/Performance/PERFORMANCE_METRICS.md`

---

### How would you debug corruption reports?

**Answer:**
1. **Health check** - `db.health()` identifies issues
2. **Export/verify** - Export database, verify integrity
3. **WAL inspection** - Check WAL for corruption
4. **Metadata rebuild** - Rebuild from data pages
5. **Backup restore** - Restore from backup if available

**Code:** `BlazeDB/Exports/BlazeDBClient.swift` - `export()`, `health()` methods

---

### How would you add observability?

**Answer:**
1. **Structured logging** - Use `BlazeLogger` for all operations
2. **Metrics export** - Export to Prometheus/StatsD
3. **Tracing** - Add operation tracing
4. **Profiling** - Use Instruments for performance profiling

**Code:** `BlazeDB/Utils/BlazeLogger.swift` - Logging infrastructure

---

### How would you expose diagnostics?

**Answer:**
1. **Health endpoint** - `db.health()` returns status
2. **Stats endpoint** - `db.stats()` returns metrics
3. **CLI tools** - `blazedb doctor`, `blazedb info`
4. **Export/import** - Export for analysis

**Code:** `BlazeDB/Exports/BlazeDBClient.swift` - Diagnostic methods

---

### How would you handle upgrades?

**Answer:**
1. **Format versioning** - Version byte in metadata
2. **Migration path** - Automatic migration if possible
3. **Backup first** - Always backup before upgrade
4. **Rollback plan** - Can restore from backup if needed

**Code:** `BlazeDB/Storage/StorageLayout.swift` - Format version management

---

## 17. Scaling & Future Work (Optional)

### What breaks first as data grows?

**Answer:**
1. **Memory usage** - Index map grows with record count
2. **Query performance** - Full scans slow down
3. **WAL size** - WAL grows until checkpoint
4. **Cache effectiveness** - Cache hit rate decreases

**Mitigation:** Indexes, batched operations, larger cache

---

### How would you shard or partition?

**Answer:**
1. **Collection-level sharding** - Different collections in different files
2. **Range partitioning** - Partition by record ID ranges
3. **Hash partitioning** - Partition by hash of record ID
4. **Application-level** - Application manages sharding

**Note:** Not currently implemented, would require architectural changes

---

### How would you add replication?

**Answer:**
1. **Operation log** - Already have operation log for sync
2. **Conflict resolution** - Last-write-wins or CRDT merge
3. **Consistency model** - Eventually consistent
4. **Network protocol** - TCP protocol already exists

**Note:** Distributed sync is experimental, not production-ready

---

### What would distribution require?

**Answer:**
1. **Consensus protocol** - Raft/Paxos for consistency
2. **Network layer** - Reliable message delivery
3. **Conflict resolution** - Handle concurrent writes
4. **Partition tolerance** - Handle network partitions

**Current state:** Hub-and-spoke sync exists, but not distributed consensus

---

### What would you not do first?

**Answer:**
1. **Distributed consensus** - Too complex, not needed for use case
2. **SQL compatibility** - Out of scope
3. **Multi-process access** - Would require major rewrite
4. **Background workers** - Keep system simple

**Rationale:** Focus on core correctness and performance first

---

### What problems get much harder?

**Answer:**
1. **Consistency** - Distributed consistency is hard
2. **Conflict resolution** - Concurrent writes need resolution
3. **Network partitions** - Handle split-brain scenarios
4. **Performance** - Network latency dominates
5. **Debugging** - Distributed systems are hard to debug

**That's why:** BlazeDB is local-first, not distributed-first

---

## 18. Meta / Judgment Questions

### What does BlazeDB teach you about systems?

**Answer:**
1. **Vertical integration matters** - Designing components together eliminates impedance mismatches
2. **Correctness first** - Performance optimizations must not sacrifice correctness
3. **Explicit guarantees** - Document what you guarantee and what you don't
4. **Simplicity wins** - Simple designs are easier to understand and maintain

**Code Reference:** `Docs/WHY_EACH_PART_EXISTS.md` - Complete rationale

---

### What mental model changed after building it?

**Answer:**
1. **I/O is the bottleneck** - Not CPU, not memory, but disk I/O
2. **Encryption can be fast** - AES-GCM is fast enough for real-time
3. **MVCC is worth it** - Memory overhead worth 50-100x speedup
4. **Tests drive design** - Writing tests reveals design flaws early

---

### How did it change how you read other systems?

**Answer:**
1. **Look for invariants** - What must always be true?
2. **Understand trade-offs** - What did they sacrifice?
3. **Check failure modes** - How does it fail?
4. **Validate guarantees** - What do they actually guarantee?

**Example:** Reading SQLite docs, I now understand why they made certain choices

---

### What surprised you the most?

**Answer:**
1. **How fast encryption is** - AES-GCM adds only 20-30% overhead
2. **How effective MVCC is** - 50-100x speedup for concurrent reads
3. **How important batching is** - 10-100x fewer fsync calls
4. **How hard testing is** - 2,167+ tests and still finding edge cases

---

### How did it influence how you approach App Attest / CI / tooling?

**Answer:**
1. **Explicit guarantees** - Document what tools guarantee
2. **Test everything** - Comprehensive test coverage
3. **Measure performance** - Benchmark everything
4. **Fail fast** - Detect errors early, not in production

**Application:** Same principles apply to CI/CD, tooling, security

---

## Summary

This document provides exhaustive answers to interview questions about BlazeDB. Remember:

- **You don't need to memorize this** - Understand the concepts
- **Answer one layer deep** - Stop early, go deeper if asked
- **Reference code** - Point to specific files and line numbers
- **Acknowledge trade-offs** - Show you understand the design decisions

**If you can comfortably reason through 60-70% of this list, you are operating at the level they're interviewing for.**

---

**For more details, see:**
- [Walkthrough Checklist](WALKTHROUGH_CHECKLIST.md) - Code walkthrough with file references
- [Interview Preparation](INTERVIEW_PREPARATION.md) - High-level overview
- [Why Each Part Exists](WHY_EACH_PART_EXISTS.md) - Deep rationale for each component
- [Developer Guide](DEVELOPER_GUIDE.md) - Complete API reference

---

**End of Interview Master List**
