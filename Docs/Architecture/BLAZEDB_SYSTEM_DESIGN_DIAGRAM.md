# BlazeDB System Design Diagram

**Complete system architecture with all components, data flows, and interactions.**

---

## 1. Complete System Architecture

```

 APPLICATION LAYER 
    
  BlazeDBClient   BlazeShell   BlazeStudio  
  (Public API)   (CLI Tool)   (GUI Tool)  
    
    
  
  
  
  DynamicCollection  
  (Schema-less Store)  
  - insert/update/delete  
  - fetch/query  
  - MVCC (opt-in)  
  

 

 QUERY & INDEX LAYER 
  
  QueryBuilder  
  - Fluent DSL (.where().orderBy().limit())  
  - Filters, Sorting, Pagination, Aggregations  
  - Joins, Subqueries, CTEs, UNION/INTERSECT/EXCEPT  
  
  
  
  QueryOptimizer  
  - Cost-based optimization  
  - Index selection (20% better threshold)  
  - Selectivity estimation  
  
  
  
  QueryPlanner  
  - Execution plan generation  
  - Join ordering  
  - Filter pushdown  
  
  
  
  INDEX SUBSYSTEM  
      
   Secondary   Full-Text   Spatial   
   Indexes   Search   Index   
   (Hash-based)  (Inverted)   (R-tree)   
      
     
   Vector   Ordering   
   Index   Index   
   (Cosine)   (Sorted)   
     
  

 

 MVCC & CONCURRENCY LAYER 
  
  VersionManager  
  - Tracks all versions: [UUID: [RecordVersion]]  
  - Global version counter (UInt64, wraparound handling)  
  - Active snapshot tracking  
  - Automatic GC (removes versions older than oldest snapshot)  
  
  
  
  MVCCTransaction  
  - Snapshot isolation (sees consistent state)  
  - Non-blocking reads  
  - Conflict detection (optimistic)  
  - Rollback support  
  
  
  
  OperationPool (Actor)  
  - Max 100 concurrent operations (configurable)  
  - Async/await support  
  - Resource management  
  
  
  
  AsyncQueryCache (Actor)  
  - Max 1000 entries (60s TTL)  
  - Query result caching  
  

 

 TRANSACTION & WAL LAYER 
  
  BlazeTransaction  
  - beginTransaction() / commit() / rollback()  
  - ACID guarantees  
  
  
  
  TransactionLog  
  - Newline-delimited JSON entries  
  - Operations: write, delete, begin, commit, abort  
  - Persistent storage (operation_log.json)  
  
  
  
  WriteAheadLog (Actor)  
  - Batched writes (100 writes or 1.0s threshold)  
  - Checkpoint to main file  
  - Crash recovery (replay on startup)  
  - 10-100x fewer fsync calls  
  

 

 STORAGE ENGINE LAYER 
  
  DynamicCollection  
  - indexMap: [UUID: [Int]] (record → page indices, overflow support) 
  - secondaryIndexes: [String: [CompoundIndexKey: Set<UUID>]]  
  - Metadata batching (flush every 100 operations)  
  - Page reuse (deletedPages tracking)  
  
  
  
  StorageLayout  
  - Persistent metadata (.meta file)  
  - indexMap, secondaryIndexes, searchIndex  
  - Signature verification (HMAC-SHA256)  
  - Secure storage (password-protected)  
  
  
  
  PageStore  
  - 4KB page-aligned storage  
  - AES-256-GCM encryption (per page, unique nonce)  
  - Page cache (LRU, 1000 pages = ~4MB)  
  - Thread-safe (concurrent queue with barriers)  
  - Overflow support (page chains for records >4KB)  
  
  
  
  File System  
  -.blazedb (data)  
  -.meta (metadata)  
  -.meta.indexes  
  

 

 ENCODING & SERIALIZATION LAYER 
  
  BlazeBinaryEncoder/Decoder  
  - Custom binary format (53% smaller than JSON)  
  - Variable-length encoding with bit-packing  
  - Optional CRC32 checksums (99.9% corruption detection)  
  - Common fields optimization (127 fields → 1 byte)  
  - ARM-optimized codec (byte-perfect compatibility)  
  
  
  
  BlazeRecordEncoder/Decoder  
  - Codable integration  
  - Custom KeyedEncodingContainer  
  - Type-safe encoding/decoding  
  

 

 DISTRIBUTED SYNC LAYER 
  
  BlazeSyncEngine (Actor)  
  - Operation log-based sync (incremental only)  
  - Adaptive batching (10K-50K ops per batch)  
  - Pipelining (200 batches in flight)  
  - Operation merging (Insert+Update → Update)  
  - Predictive prefetching  
  - Delta encoding (only changed fields)  
  
  
  
  OperationLog (Actor)  
  - Persistent operation history (operation_log.json)  
  - Lamport timestamps (causal ordering)  
  - GC with configurable retention (default: 10K ops)  
  - currentClock: UInt64 (wraparound handling)  
  
  
  
  SYNC RELAYS (All Actors)  
      
   TCPRelay   UnixDomainSocket   InMemoryRelay   
   (Remote)   Relay   (Testing)   
   - Raw TCP   (Same Device)   - No network   
   - SecureConnection  - High-perf IPC   - Direct calls   
   - E2E encryption   - Server: TODO     
      
  
  
  
  BlazeTopology  
  - Node and connection tracking  
  - Role management (server/client)  
  - Connection modes (local/remote/read-only)  
  
  
  
  BlazeDiscovery  
  - mDNS/Bonjour service discovery  
  - Automatic device discovery on local network  
  - Service: _blazedb._tcp.  
  

 

 SECURITY & ENCRYPTION LAYER 
  
  SecureConnection  
  - ECDH P-256 key exchange (ephemeral keys, Perfect Forward Secrecy)  
  - HKDF-SHA256 key derivation (32-byte AES-256 key)  
  - HMAC-SHA256 challenge-response authentication  
  - AES-256-GCM encryption (E2E, server blind)  
  - Frame protocol (type + length + payload + HMAC)  
  
  
  
  PolicyEngine  
  - Row-Level Security (RLS)  
  - Policy evaluation on every operation  
  - Permissive/Restrictive policy types  
  - User context (userID, teamID, roles)  
  
  
  
  PageStore Encryption  
  - AES-256-GCM per page (at rest)  
  - Unique 12-byte nonce per page  
  - 16-byte authentication tag  
  - Key derivation: Argon2 → HKDF  
  

```

---

## 2. Data Flow Diagrams

### 2.1 Insert Operation Flow

```

 Application 
 (insert) 

 
 

 DynamicCollection 
 - Validate record 
 - Check max size 
 (100MB limit) 

 
 

 BlazeBinaryEncoder 
 - Encode record 
 - Optional CRC32 
 - 53% vs JSON 

 
 

 PageStore 
 - Allocate page 
 - Encrypt (AES) 
 - Write + fsync 

 
 

 WAL (WriteAheadLog) 
 - Append entry 
 - Batch (100 ops) 
 - Checkpoint 

 
 

 Index Updates 
 - Secondary 
 - Full-text 
 - Spatial/Vector 

 
 

 Metadata Update 
 - indexMap 
 - Flush (100 ops) 

 
 

 MVCC (if enabled) 
 - Create version 
 - Register snapshot

 
 

 Sync Engine 
 - Create operation 
 - Add to queue 
 - Batch (10K ops) 

```

### 2.2 Query Operation Flow

```

 Application 
 (query) 

 
 

 QueryBuilder 
 - Build query 
 - Chain filters 

 
 

 QueryOptimizer 
 - Cost estimation 
 - Index selection 
 - Plan generation 

 
 
  
  
 
 Index Scan   Full Scan 
 (if indexed)  (if not) 
 
  
 
 
 

 PageStore 
 - Read pages 
 - Decrypt (AES) 
 - Cache (LRU) 

 
 

 BlazeBinaryDecoder 
 - Decode record 
 - Validate CRC32 

 
 

 Filter Application 
 - Apply predicates 
 - Early exit 

 
 

 Sort & Limit 
 - Sort results 
 - Apply limit 

 
 

 RLS Filtering 
 - Policy check 
 - Filter records 

 
 

 Return Results 

```

### 2.3 Sync Operation Flow

```
 
 Client Node   Server Node 
 (BlazeDB)   (BlazeDB) 
 
  
  [1] Local Change 
  
 
 BlazeSyncEngine  
 - Create operation  
 - Add to queue  
 
  
  [2] Batch (10K ops) 
  
 
 OperationLog  
 - Record operation  
 - Increment clock  
 - Persist to disk  
 
  
  [3] Encode Operations 
  
 
 TCPRelay  
 - BlazeBinary  
 - Smart caching  
 - Parallel encode  
 
  
  [4] Compress (STUBBED) 
  
 
 SecureConnection  
 - AES-256-GCM  
 - Frame protocol  
 
  
  [5] Network (TCP) 
 
  
  
  
   SecureConnection 
   - Decrypt 
   - Frame parse 
  
  
   [6] Decompress (STUBBED)
  
  
   TCPRelay 
   - Decode ops 
  
  
   [7] Security Validation
  
  
   SecurityValidator 
   - Validate batch 
  
  
   [8] Apply Operations
  
  
   BlazeSyncEngine 
   - Sort by timestamp
   - Conflict resolve 
   - Apply to DB 
  
  
   [9] Update OperationLog
  
  
   OperationLog 
   - Record ops 
   - Update clock 
  
 
  [10] Sync State Exchange (bidirectional)
 
 
```

### 2.4 Handshake Flow (Secure Connection)

```
 
 Client   Server 
 
  
  [1] Generate clientPrivateKey (P-256) 
  
  [2] Hello (clientPublicKey) 
 
  
   [3] Authenticate (verify token)
  
   [4] Generate serverPrivateKey (P-256)
  
   [5] Generate challenge (16 bytes)
  
  [6] Welcome (serverPublicKey + challenge) 
 
  
  [7] ECDH: sharedSecret 
  = ECDH(clientPrivateKey, serverPublicKey) 
   [8] ECDH: sharedSecret
   = ECDH(serverPrivateKey, clientPublicKey)
   (Same result!)
 
  [9] HKDF: groupKey (AES-256)  [10] HKDF: groupKey (AES-256)
  = HKDF(sharedSecret, salt, info)  = HKDF(sharedSecret, salt, info)
   (Same result!)
 
  [11] HMAC(challenge, groupKey) 
 
  
   [12] Verify HMAC response
  
  [13] handshakeComplete 
 
  
  [14] All future data encrypted (AES-256-GCM)  [15] All future data encrypted (AES-256-GCM)
  
```

---

## 3. Storage Structure

### 3.1 File Layout

```
Database Directory:
 database.blazedb (Main data file, encrypted pages)
 database.meta (Metadata: indexMap, indexes, schema)
 database.meta.indexes (Optional: separate index file)
 operation_log.json (Operation log for sync, BlazeBinary)
 txlog.blz (WAL file, newline-delimited JSON)
```

### 3.2 Page Structure

```

 Page (4096 bytes) 

 Header (9 bytes) 
 - Magic: "BLAZE" (5 bytes) 
 - Version: 0x01 or 0x02 (1 byte) 
 - Flags: CRC32 enabled? (1 byte) 
 - Reserved: (2 bytes) 

 Nonce (12 bytes) 
 - Unique per page 
 - AES-GCM requirement 

 Encrypted Data (up to ~4046 bytes) 
 - BlazeBinary encoded record 
 - Optional CRC32 (4 bytes) 

 Authentication Tag (16 bytes) 
 - AES-GCM tag 
 - Prevents tampering 

```

### 3.3 Overflow Page Structure

```

 Overflow Page (4096 bytes) 

 Header (16 bytes) 
 - Magic: 0x4F564552 ("OVER") (4 bytes) 
 - Version: 0x03 (1 byte) 
 - Reserved: (3 bytes) 
 - nextPageIndex: UInt32 (0 = end of chain) (4 bytes) 
 - dataLength: UInt32 (4 bytes) 

 Nonce (12 bytes) 

 Encrypted Data (up to ~4046 bytes) 

 Authentication Tag (16 bytes) 

```

### 3.4 Metadata Structure (StorageLayout)

```
StorageLayout {
 indexMap: [UUID: Int] // Record ID → first page index
 nextPageIndex: Int // Next available page
 secondaryIndexes: [String: [CompoundIndexKey: [UUID]]] // Field → key → record IDs
 version: Int // Schema version
 encodingFormat: String // "blazeBinary" or "json"
 metaData: [String: BlazeDocumentField] // Collection metadata
 fieldTypes: [String: String] // Field name → type name
 secondaryIndexDefinitions: [String: [String]] // Index name → field names
 searchIndex: InvertedIndex? // Full-text search index
 searchIndexedFields: [String] // Fields indexed for search
 deletedPages: [Int] // Pages available for reuse
 signature: Data? // HMAC-SHA256 signature
}
```

---

## 4. Network Protocol

### 4.1 Frame Format

```

 Frame Structure 

 Type (1 byte) 
 - 0x01: handshake 
 - 0x02: handshakeAck 
 - 0x03: verify 
 - 0x04: handshakeComplete 
 - 0x05: encryptedData 
 - 0x06: operation (reserved) 

 Length (4 bytes, big-endian) 
 - Payload size 

 Payload (N bytes) 
 - Encrypted with AES-256-GCM (after handshake) 
 - Contains: nonce (12 bytes) + ciphertext + tag (16) 

```

### 4.2 Operation Encoding Format

```

 BlazeBinary Operation Format 

 Operation ID (16 bytes, UUID) 

 Timestamp Counter (1-9 bytes, variable-length) 
 - 0x00 + 1 byte: counter < 256 
 - 0x01 + 2 bytes: counter < 65536 
 - 0x02 + 8 bytes: counter >= 65536 

 Node ID (16 bytes, UUID) 

 Operation Type + Collection Name (variable) 
 - Packed: type (3 bits) + name length (5 bits) + name 
 - Or: type (1 byte) + name length (1-3 bytes) + name 

 Record ID (16 bytes, UUID) 

 Changes (BlazeBinary encoded record) 
 - Variable length 

```

### 4.3 Batch Encoding Format

```

 Batch of Operations 

 Count (1-5 bytes, variable-length) 
 - < 256: 1 byte 
 - >= 256: 0xFF + 4 bytes (UInt32) 

 Operations (repeated) 
  
  Length (1-5 bytes, variable-length)  
  - < 128: 1 byte  
  - < 32768: 0x80 + 2 bytes  
  - >= 32768: 0xFF + 4 bytes  
  
  Operation Data (BlazeBinary)  
  

```

---

## 5. Component Interactions

### 5.1 MVCC Transaction Flow

```

 Transaction Start

 
 

 VersionManager 
 - Get snapshot 
 - Register active 

 
 

 Read Operations 
 - Get version 
 - Read from page 
 - Non-blocking 

 
 

 Write Operations 
 - Create new ver. 
 - Track pending 

 
 

 Commit 
 - Check conflicts 
 - Apply writes 
 - Unregister 

 
 

 GC (if needed) 
 - Remove old ver. 
 - Free pages 

```

### 5.2 Index Update Flow

```

 Record Insert 

 
 

 Extract Index Keys 
 - Single field 
 - Compound fields 

 
 
  
  
 
 Secondary   Full-Text 
 Index Update   Index Update 
 (Hash-based)   (Inverted) 
 
  
 
 
 

 Atomic with Write 
 - Same transaction 
 - All-or-nothing 

```

### 5.3 Sync Conflict Resolution Flow

```

 Receive Operation

 
 

 Check Timestamp 
 - Sort by Lamport 
 - Causal order 

 
 

 Conflict Detection 
 - Same record? 
 - Same timestamp? 

 
  Yes  
   Check Roles 
   - Server > Client 
   - Timestamp tiebreak
  
  
  
  
   mergeWithCRDT() 
   - Server wins 
   - Last-Write-Wins 
  
  
  No 
 
 

 Apply Operation 
 - Update record 
 - Update indexes 

```

---

## 6. Security Architecture

### 6.1 Encryption Layers

```

 At Rest Encryption 
  
  PageStore  
  - AES-256-GCM per page  
  - Unique nonce (12 bytes)  
  - Authentication tag (16 bytes)  
  - Key: Argon2(password) → HKDF  
  



 In Transit Encryption 
  
  SecureConnection  
  - ECDH P-256 (ephemeral keys)  
  - HKDF-SHA256 (key derivation)  
  - AES-256-GCM (frame encryption)  
  - Perfect Forward Secrecy  
  - Server blind (E2E)  
  

```

### 6.2 Access Control Flow

```

 Operation Request

 
 

 PolicyEngine 
 - Get policies 
 - Filter by op 

 
 

 Evaluate Policies 
 - Permissive (OR) 
 - Restrictive (AND)
 - Check context 

 
  Allowed  
   Execute Operation 
  
 
  Denied  
  Return Error 
  (Unauthorized) 
 
```

---

## 7. Performance Characteristics

### 7.1 Operation Latency Breakdown

```
Insert Operation (0.4-0.8ms total):
 Validate: 0.01ms (2%)
 Encode: 0.05ms (10%)
 Encrypt: 0.1ms (20%)
 Write: 0.2-0.5ms (50-70%) ← BOTTLENECK
 Index: 0.05ms (10%)
 Metadata: 0.05ms (5%)

Fetch Operation (0.2-0.5ms total):
 Index Lookup: 0.01ms (5%)
 Read: 0.1-0.3ms (50-70%) ← BOTTLENECK
 Decrypt: 0.05ms (20%)
 Decode: 0.05ms (20%)

Query Operation (2-250ms total):
 Load Records: 50-200ms (80-90%) ← BOTTLENECK
 Filter: 1-10ms (5-10%)
 Sort: 5-50ms (5-20%)
 Limit: 0.1ms (<1%)
```

### 7.2 Throughput Scaling

```
Single Core:
 Insert: 1,200-2,500 ops/sec
 Fetch: 2,500-5,000 ops/sec
 Update: 1,000-1,600 ops/sec
 Delete: 3,300-10,000 ops/sec

8 Cores (Parallel):
 Insert: 10,000-20,000 ops/sec (8x)
 Fetch: 20,000-50,000 ops/sec (8-10x)
 Update: 8,000-16,000 ops/sec (8x)
 Delete: 26,000-80,000 ops/sec (8x)

Network Sync (WiFi 100 Mbps):
 Small Ops (200 bytes): 7,800 ops/sec
 Medium Ops (550 bytes): 5,000 ops/sec
 Large Ops (1900 bytes): 3,450 ops/sec
```

---

## 8. Key Design Decisions

### 8.1 Why Page-Based Storage?
- **4KB pages:** Aligns with OS page size, efficient I/O
- **Overflow chains:** Supports large records without fixed limits
- **Page reuse:** Garbage collection marks deleted pages for reuse

### 8.2 Why MVCC?
- **Non-blocking reads:** Concurrent reads never block writes
- **Snapshot isolation:** Each transaction sees consistent state
- **Conflict detection:** Optimistic concurrency control

### 8.3 Why Operation Log Sync?
- **Incremental:** Only changed operations transferred
- **Causal ordering:** Lamport timestamps ensure correct order
- **Conflict resolution:** Server priority + Last-Write-Wins

### 8.4 Why BlazeBinary?
- **Size:** 53% smaller than JSON, 17% smaller than CBOR
- **Speed:** 1.2-1.5x faster encoding/decoding
- **Safety:** Optional CRC32 for corruption detection

### 8.5 Why E2E Encryption?
- **Privacy:** Server cannot read data (server blind)
- **Security:** Perfect Forward Secrecy (ephemeral keys)
- **Authentication:** Challenge-response prevents MITM

---

**Document Version:** 1.0
**Last Updated:** Based on complete system architecture analysis
**Method:** Code-driven design extraction

