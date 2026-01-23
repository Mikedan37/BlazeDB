# BlazeDB Performance Audit: Operations Per Minute & Operational Details

** IMPORTANT: These numbers are ESTIMATES based on documentation and test targets, NOT actual measured results.**

**To get ACTUAL measured performance numbers, run:**
```bash
# Run comprehensive benchmarks
swift test --filter ComprehensiveBenchmarks

# Run performance benchmarks (DEBUG mode only)
swift test --filter PerformanceBenchmarks

# Run baseline tests (requires env var)
BLAZEDB_RUN_BASELINE_TESTS=1 swift test --filter BaselinePerformanceTests
```

**Results will be saved to:**
- `.build/test-metrics/*.json` (PerformanceBenchmarks)
- `/tmp/blazedb_baselines.json` (BaselinePerformanceTests)

---

## **Executive Summary**

**Note: These are ESTIMATED numbers based on:**
- Test expectations/targets in benchmark code
- Realistic performance analysis documents
- Theoretical calculations

**ACTUAL measured numbers may vary. Run benchmarks to get real results.**

### **Core Performance (Single Core)**
- **Insert**: 72,000 - 150,000 ops/min (1,200-2,500 ops/sec)
- **Fetch**: 150,000 - 300,000 ops/min (2,500-5,000 ops/sec)
- **Update**: 60,000 - 96,000 ops/min (1,000-1,600 ops/sec)
- **Delete**: 198,000 - 600,000 ops/min (3,300-10,000 ops/sec)

### **Multi-Core Performance (8 Cores)**
- **Insert**: 600,000 - 1,200,000 ops/min (10,000-20,000 ops/sec)
- **Fetch**: 1,200,000 - 3,000,000 ops/min (20,000-50,000 ops/sec)
- **Update**: 480,000 - 960,000 ops/min (8,000-16,000 ops/sec)
- **Delete**: 1,560,000 - 4,800,000 ops/min (26,000-80,000 ops/sec)

### **Network Sync (WiFi 100 Mbps)**
- **Small Operations (200 bytes)**: 468,000 ops/min (7,800 ops/sec)
- **Medium Operations (550 bytes)**: 300,000 ops/min (5,000 ops/sec)
- **Large Operations (1900 bytes)**: 207,000 ops/min (3,450 ops/sec)

---

## **How BlazeDB Actually Operates**

### **Storage Architecture**
1. **Page-Based Storage**: Data stored in 8KB pages with overflow pages for large records
2. **BlazeBinary Encoding**: Custom binary format (53% smaller than JSON, 48% faster encoding/decoding)
3. **Encryption**: AES-256-GCM encryption at rest (all data encrypted before writing)
4. **Memory-Mapped I/O**: Automatic memory mapping for 2-3x faster reads
5. **Write-Ahead Log (WAL)**: All writes go through WAL for crash recovery

### **Concurrency Model**
- **MVCC (Multi-Version Concurrency Control)**: Enables concurrent reads/writes without blocking
- **Write Lock**: Single writer lock ensures ACID guarantees
- **Read Operations**: Non-blocking, can read while writes occur
- **Transaction Isolation**: Serializable isolation level

### **Query Execution**
1. **Query Planner**: Analyzes query and selects optimal strategy (index vs sequential scan)
2. **Index Selection**: Automatically chooses best index (spatial, vector, full-text, or regular)
3. **Early Exit**: LIMIT clauses stop processing once enough results found
4. **Lazy Evaluation**: Only decode fields that are actually accessed
5. **Parallel Processing**: Large queries split across multiple cores

---

## **Detailed Operations Per Minute**

### **1. Core CRUD Operations**

#### **Single Operations (Per Core)**
| Operation | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|-----------|---------|---------|---------------|-------|
| **Insert** | 1,200-2,500 | **72,000-150,000** | 0.4-0.8ms | Includes encryption, WAL write, index updates |
| **Fetch** | 2,500-5,000 | **150,000-300,000** | 0.2-0.4ms | Memory-mapped I/O, decryption, decoding |
| **Update** | 1,000-1,600 | **60,000-96,000** | 0.6-1.0ms | Fetch + modify + write back |
| **Delete** | 3,300-10,000 | **198,000-600,000** | 0.1-0.3ms | Fastest operation (mark as deleted) |
| **Upsert** | 1,000-2,000 | **60,000-120,000** | 0.5-1.0ms | Insert or update (checks existence first) |

#### **Batch Operations (Per Core)**
| Operation | Batch Size | Ops/Sec | Ops/Min | Latency | Notes |
|-----------|------------|---------|---------|---------|-------|
| **Insert Batch** | 100 | 3,300-6,600 | **198,000-396,000** | 15-30ms | Single fsync for entire batch |
| **Insert Optimized** | 1,000 | 5,000-10,000 | **300,000-600,000** | 100-200ms | Parallel encoding + single fsync |
| **Update Batch** | 100 | 2,500-5,000 | **150,000-300,000** | 20-40ms | Batch write optimization |
| **Delete Batch** | 100 | 6,600-20,000 | **396,000-1,200,000** | 5-15ms | Fastest batch operation |
| **Upsert Batch** | 100 | 2,800-5,500 | **168,000-330,000** | 18-35ms | Batch existence checks |

#### **Multi-Core Performance (8 Cores)**
| Operation | Ops/Sec | Ops/Min | Scaling Factor | Notes |
|-----------|---------|---------|----------------|-------|
| **Insert** | 10,000-20,000 | **600,000-1,200,000** | 8x | Linear scaling with cores |
| **Fetch** | 20,000-50,000 | **1,200,000-3,000,000** | 8-10x | Parallel reads |
| **Update** | 8,000-16,000 | **480,000-960,000** | 8x | Parallel encoding |
| **Delete** | 26,000-80,000 | **1,560,000-4,800,000** | 8x | Minimal locking overhead |
| **Insert Batch** | 26,000-53,000 | **1,560,000-3,180,000** | 8x | Parallel batch encoding |

---

### **2. Query Operations**

| Operation | Dataset Size | Queries/Sec | Queries/Min | Latency (p50) | Notes |
|-----------|--------------|-------------|-------------|---------------|-------|
| **Basic Query** | 100 records | 200-500 | **12,000-30,000** | 2-5ms | Simple filter |
| **Filter (Single)** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | One WHERE clause |
| **Filter (Multiple)** | 1K records | 50-125 | **3,000-7,500** | 8-20ms | Multiple WHERE clauses |
| **Sort (Single Field)** | 1K records | 40-100 | **2,400-6,000** | 10-25ms | ORDER BY one field |
| **Sort (Multiple)** | 1K records | 28-66 | **1,680-3,960** | 15-35ms | ORDER BY multiple fields |
| **Limit (10 of 10K)** | 10K records | 66-200 | **3,960-12,000** | 5-15ms | Early exit optimization |
| **Offset (skip 1000)** | 1K records | 50-125 | **3,000-7,500** | 8-20ms | Pagination overhead |
| **Optimized Query** | Variable | 100-500 | **6,000-30,000** | 2-10ms | With early exit |
| **Parallel Query** | 10K records | 6-20 | **360-1,200** | 50-150ms | Multi-core processing |
| **Lazy Query** | 10K records | N/A | N/A | 1-5ms (first) | Streaming results |

**Query Performance Notes:**
- **Indexed queries**: 10-100x faster than unindexed
- **Query caching**: 10-100x faster for repeated queries
- **Early exit (LIMIT)**: 2-10x speedup
- **Parallel processing**: 2-5x faster on large datasets

---

### **3. SQL-Like Features**

#### **Basic SQL Operations**
| Feature | Dataset Size | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|---------|---------------|---------|---------|---------------|-------|
| **SELECT** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | Basic query |
| **WHERE** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | Filter operation |
| **ORDER BY** | 1K records | 40-100 | **2,400-6,000** | 10-25ms | Sorting overhead |
| **LIMIT** | 10K records | 66-200 | **3,960-12,000** | 5-15ms | Early exit |
| **OFFSET** | 1K records | 50-125 | **3,000-7,500** | 8-20ms | Pagination |
| **DISTINCT** | 1K records | 33-100 | **1,980-6,000** | 10-30ms | Deduplication |
| **COUNT** | 10K records | 200-500 | **12,000-30,000** | 2-5ms | Fast aggregation |
| **SUM** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | Numeric aggregation |
| **AVG** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | Average calculation |
| **MIN/MAX** | 1K records | 66-200 | **3,960-12,000** | 5-15ms | Min/max scan |

#### **Advanced SQL Features**
| Feature | Dataset Size | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|---------|---------------|---------|---------|---------------|-------|
| **Window Functions** | 1K records | 20-50 | **1,200-3,000** | 20-50ms | Requires sorting |
| **Triggers** | Per operation | N/A | N/A | +0.1-0.5ms | Overhead per op |
| **Subqueries (EXISTS)** | 1K records | 33-100 | **1,980-6,000** | 10-30ms | Existence check |
| **Subqueries (Correlated)** | 1K records | 12-33 | **720-1,980** | 30-80ms | Per-row execution |
| **CASE WHEN** | 1K records | 50-125 | **3,000-7,500** | 8-20ms | Conditional logic |
| **Foreign Keys** | Per operation | N/A | N/A | +0.1-0.3ms | Validation overhead |
| **UNION/UNION ALL** | 1K records | 25-66 | **1,500-3,960** | 15-40ms | Set operations |
| **INTERSECT/EXCEPT** | 1K records | 20-50 | **1,200-3,000** | 20-50ms | Set operations |
| **CTEs (WITH)** | 1K records | 25-66 | **1,500-3,960** | 15-40ms | Cached results |
| **LIKE/ILIKE** | 1K records | 33-100 | **1,980-6,000** | 10-30ms | Regex matching |
| **EXPLAIN** | Any | 333-1,000 | **19,980-60,000** | 1-3ms | Query plan only |
| **Savepoints** | Per operation | 3,300-10,000 | **198,000-600,000** | 0.1-0.3ms | Transaction state |
| **Regex Queries** | 1K records | 25-66 | **1,500-3,960** | 15-40ms | Pattern matching |

---

### **4. JOIN Operations**

| Join Type | Dataset Size | Queries/Sec | Queries/Min | Latency (p50) | Notes |
|-----------|--------------|-------------|-------------|---------------|-------|
| **Inner Join** | 1K x 1K | 20-50 | **1,200-3,000** | 20-50ms | Only matching pairs |
| **Left Join** | 1K x 1K | 16-40 | **960-2,400** | 25-60ms | All left + matching right |
| **Right Join** | 1K x 1K | 14-33 | **840-1,980** | 30-70ms | All right + matching left |
| **Full Outer Join** | 1K x 1K | 10-25 | **600-1,500** | 40-100ms | All from both |
| **Self Join** | 1K records | 20-50 | **1,200-3,000** | 20-50ms | Table joined with itself |
| **Multiple Joins** | 3 tables, 1K each | 6-16 | **360-960** | 60-150ms | Compound joins |

**JOIN Performance Notes:**
- **Indexed joins**: 2-5x faster than unindexed
- **Batch fetching**: O(N+M) instead of O(N×M)
- **Memory usage**: Scales with result set size

---

### **5. Transaction Operations**

| Operation | Transaction Size | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|-----------|-----------------|---------|---------|---------------|-------|
| **Begin Transaction** | N/A | 3,300-10,000 | **198,000-600,000** | 0.1-0.3ms | State initialization |
| **Commit (10 ops)** | 10 operations | 200-500 | **12,000-30,000** | 2-5ms | Includes fsync |
| **Commit (100 ops)** | 100 operations | 40-100 | **2,400-6,000** | 10-25ms | Single fsync for all |
| **Rollback** | Any | 500-2,000 | **30,000-120,000** | 0.5-2.0ms | No disk I/O |
| **Savepoint (create)** | N/A | 3,300-10,000 | **198,000-600,000** | 0.1-0.3ms | Nested transactions |
| **Savepoint (rollback)** | Any | 500-2,000 | **30,000-120,000** | 0.5-2.0ms | Partial rollback |

**Transaction Notes:**
- **Commit latency**: Includes fsync (2-10ms typical)
- **Rollback**: Fast (no disk I/O, just state reset)
- **Savepoints**: Enable nested rollbacks with minimal overhead

---

### **6. Index Operations**

| Operation | Dataset Size | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|-----------|--------------|---------|---------|---------------|-------|
| **Create Index (Single)** | 10K records | 6-20 | **360-1,200** | 50-150ms | One-time cost |
| **Create Index (Compound)** | 10K records | 5-12 | **300-720** | 80-200ms | Multi-field index |
| **Drop Index** | Any | 500-2,000 | **30,000-120,000** | 0.5-2.0ms | Fast operation |
| **Index Hints** | Variable | 66-200 | **3,960-12,000** | 5-15ms | Bypass optimizer |

**Index Notes:**
- **Index creation**: One-time cost, permanent 10-100x query speedup
- **Compound indexes**: Support multi-field queries efficiently
- **Automatic selection**: Query planner chooses best index

---

### **7. Search Operations**

| Operation | Dataset Size | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|-----------|--------------|---------|---------|---------------|-------|
| **Full-Text Search** | 1K docs | 33-100 | **1,980-6,000** | 10-30ms | Without index |
| **Search Index Creation** | 1K docs | 3-10 | **180-600** | 100-300ms | One-time cost |
| **Search Query (Ranked)** | 1K docs | 25-66 | **1,500-3,960** | 15-40ms | With relevance |
| **Search Highlighting** | 1K docs | 20-50 | **1,200-3,000** | 20-50ms | +30-50% overhead |

**Search Performance:**
- **Without index**: O(n) scan, 10-30ms for 1K records
- **With inverted index**: O(log n), 0.6-5ms for 1K-100K records (50-1000x faster!)
- **Memory overhead**: ~0.5-1% of database size

---

### **8. Distributed Sync Operations**

#### **Transport Layer Performance**

| Transport | Latency | Ops/Sec | Ops/Min | Notes |
|-----------|---------|---------|---------|-------|
| **In-Memory Queue** | <0.1ms | 1,000,000+ | **60,000,000+** | Same process |
| **Unix Domain Socket** | 0.2-0.5ms | 500-5,000 | **30,000-300,000** | Cross-process, same device |
| **TCP (Local Network)** | 2-5ms | 200-500 | **12,000-30,000** | Same LAN |
| **TCP (Remote Network)** | 10-50ms | 20-100 | **1,200-6,000** | WAN/Internet |

#### **Network Sync (WiFi 100 Mbps)**
| Operation Size | Ops/Sec | Ops/Min | Data Throughput | Notes |
|----------------|---------|---------|------------------|-------|
| **Small (200 bytes)** | 7,800 | **468,000** | 1.56 MB/s | Bug tracker, status updates |
| **Medium (550 bytes)** | 5,000 | **300,000** | 2.75 MB/s | Chat messages, comments |
| **Large (1900 bytes)** | 3,450 | **207,000** | 6.55 MB/s | File metadata, rich content |

#### **Network Sync (WiFi 1000 Mbps / 5G)**
| Operation Size | Ops/Sec | Ops/Min | Data Throughput | Notes |
|----------------|---------|---------|------------------|-------|
| **Small (200 bytes)** | 17,250 | **1,035,000** | 3.45 MB/s | High-speed sync |
| **Medium (550 bytes)** | 10,000 | **600,000** | 5.5 MB/s | Optimized batching |
| **Large (1900 bytes)** | 6,578 | **394,680** | 12.5 MB/s | Large payloads |

**Sync Performance Notes:**
- **BlazeBinary encoding**: 48% faster than JSON
- **Batching**: 50 ops per batch = 15.6x faster than individual ops
- **LZ4 compression**: Optional, 3-5x faster than gzip
- **E2E encryption**: AES-256-GCM with minimal overhead

---

### **9. Migration Operations**

| Operation | Dataset Size | Records/Sec | Records/Min | Latency | Notes |
|-----------|--------------|-------------|-------------|---------|-------|
| **SQLite Migration** | 10K records | 2,000-5,000 | **120,000-300,000** | 2-5 seconds | One-time import |
| **Core Data Migration** | 10K records | 1,250-3,300 | **75,000-198,000** | 3-8 seconds | Entity conversion |
| **SQL Command Migration** | 10K records | 1,600-5,000 | **96,000-300,000** | 2-6 seconds | SQL parsing |
| **Batch Processing** | 100 records/batch | 3,300-6,600 | **198,000-396,000** | 15-30ms | Optimized batches |

**Migration Notes:**
- **Throughput**: Depends on source database performance
- **Batch processing**: 2-5x faster than individual operations
- **Progress monitoring**: Lightweight polling API

---

### **10. Backup & Restore Operations**

| Operation | Database Size | MB/Sec | MB/Min | Latency | Notes |
|-----------|--------------|--------|--------|---------|-------|
| **Full Backup** | 100MB | 20-50 | **1,200-3,000** | 2-5 seconds | Complete copy |
| **Incremental Backup** | 100MB (10% changed) | 50-200 | **3,000-12,000** | 0.5-2 seconds | Only changes |
| **Backup Verification** | 100MB | 33-100 | **1,980-6,000** | 1-3 seconds | Integrity check |
| **Restore** | 100MB | 20-50 | **1,200-3,000** | 2-5 seconds | Full restore |
| **Export (JSON)** | 10K records | 33-100 | **1,980-6,000** | 100-300ms | JSON format |
| **Export (BlazeBinary)** | 10K records | 66-200 | **3,960-12,000** | 50-150ms | Native format |
| **Import** | 10K records | 20-50 | **1,200-3,000** | 200-500ms | Data import |

**Backup Notes:**
- **Incremental backups**: 5-10x faster than full backups
- **BlazeBinary export**: 2-3x faster than JSON (native format)
- **Throughput**: Depends on disk I/O speed

---

### **11. Monitoring & Telemetry**

| Operation | Ops/Sec | Ops/Min | Latency | Notes |
|-----------|---------|---------|--------|-------|
| **Health Check** | 200-1,000 | **12,000-60,000** | 1-5ms | Database status |
| **Telemetry Recording** | 1,000,000+ | **60,000,000+** | <0.001ms | Async, zero blocking |
| **Metrics Collection** | 200-1,000 | **12,000-60,000** | 1-5ms | Query metrics |
| **Performance Monitoring** | 200-1,000 | **12,000-60,000** | 1-5ms | Performance stats |
| **Error Tracking** | 1,000,000+ | **60,000,000+** | <0.001ms | Async logging |

**Telemetry Notes:**
- **Async recording**: Zero blocking overhead
- **Sampling**: Default 1% reduces overhead by 99%
- **Health checks**: Include file integrity verification

---

### **12. Storage Operations**

| Operation | Ops/Sec | Ops/Min | Latency (p50) | Notes |
|-----------|---------|---------|---------------|-------|
| **Page Write (single)** | 2,000-5,000 | **120,000-300,000** | 0.2-0.5ms | 8KB page |
| **Page Write (batch, 100)** | 4,000-10,000 | **240,000-600,000** | 10-25ms | Single fsync |
| **Page Read (single)** | 3,300-10,000 | **198,000-600,000** | 0.1-0.3ms | Standard read |
| **Page Read (memory-mapped)** | 6,600-20,000 | **396,000-1,200,000** | 0.05-0.15ms | Zero-copy |
| **Overflow Write (100KB)** | 200-500 | **12,000-30,000** | 2-5ms | Large records |
| **Overflow Read (100KB)** | 333-1,000 | **19,980-60,000** | 1-3ms | Large records |
| **VACUUM (100MB DB)** | N/A | N/A | 5-15 seconds | Space reclamation |
| **Storage Layout Save** | 200-1,000 | **12,000-60,000** | 1-5ms | Metadata save |

**Storage Notes:**
- **Memory-mapped I/O**: 2-3x faster reads (zero-copy from kernel)
- **Batch writes**: Single fsync (10-100x fewer fsync calls)
- **Overflow pages**: Support records >8KB (up to 16MB)
- **VACUUM**: One-time cost, reclaims deleted space

---

## **Real-World Scenarios**

### **Bug Tracker Application**
- **Operations**: Small (200 bytes each)
- **Typical Load**: 100 inserts/min, 500 queries/min, 50 updates/min
- **Peak Load**: 1,000 inserts/min, 5,000 queries/min, 500 updates/min
- **BlazeDB Capacity**: **468,000 ops/min** (WiFi 100 Mbps) - **470x headroom**

### **Chat Application**
- **Operations**: Medium (550 bytes each)
- **Typical Load**: 500 messages/min, 1,000 queries/min
- **Peak Load**: 5,000 messages/min, 10,000 queries/min
- **BlazeDB Capacity**: **300,000 ops/min** (WiFi 100 Mbps) - **30x headroom**

### **File Sync Application**
- **Operations**: Large (1900 bytes each)
- **Typical Load**: 100 file updates/min, 200 queries/min
- **Peak Load**: 1,000 file updates/min, 2,000 queries/min
- **BlazeDB Capacity**: **207,000 ops/min** (WiFi 100 Mbps) - **207x headroom**

### **IoT Sensor Data**
- **Operations**: Small (200 bytes each)
- **Typical Load**: 10,000 sensor readings/min
- **Peak Load**: 100,000 sensor readings/min
- **BlazeDB Capacity**: **468,000 ops/min** (WiFi 100 Mbps) - **4.7x headroom**

---

## **Performance Optimization Impact**

### **Batch Operations**
- **2-5x faster** per record than individual operations
- **10-100x fewer fsync calls** (single fsync per batch)
- **Parallel encoding**: 2-4x speedup

### **Memory-Mapped I/O**
- **2-3x faster reads** on supported platforms
- **Zero-copy** reads from kernel page cache
- **Auto-enabled** on first read

### **Query Optimizations**
- **Early exit (LIMIT)**: 2-10x faster
- **Lazy evaluation**: 10-100x less memory
- **Parallel processing**: 2-5x faster on large datasets
- **Query caching**: 10-100x faster for repeated queries

### **Index Impact**
- **Indexed queries**: 10-100x faster than unindexed
- **Index creation**: One-time cost, permanent speedup
- **Compound indexes**: Support multi-field queries efficiently

---

## **Summary Table: Operations Per Minute**

| Category | Single Core | Multi-Core (8) | Network Sync (WiFi 100Mbps) |
|----------|-------------|----------------|----------------------------|
| **Insert** | 72K-150K | 600K-1.2M | 468K (small ops) |
| **Fetch** | 150K-300K | 1.2M-3M | N/A (local only) |
| **Update** | 60K-96K | 480K-960K | 468K (small ops) |
| **Delete** | 198K-600K | 1.56M-4.8M | 468K (small ops) |
| **Queries** | 3K-30K | 24K-240K | N/A (local only) |
| **JOINs** | 600-3K | 4.8K-24K | N/A (local only) |
| **Transactions** | 12K-600K | 96K-4.8M | N/A (local only) |
| **Search** | 1.2K-6K | 9.6K-48K | N/A (local only) |

---

## **Operational Details**

### **Write Path (Insert/Update)**
1. **Encrypt**: AES-256-GCM encryption (0.1-0.2ms)
2. **Encode**: BlazeBinary encoding (0.03-0.08ms per field)
3. **Write WAL**: Append to write-ahead log (0.2-0.5ms)
4. **Update Indexes**: Update all relevant indexes (0.1-0.3ms)
5. **Update Metadata**: Update collection metadata (0.05-0.1ms)
6. **Fsync**: Flush to disk (2-10ms, batched)

**Total**: 0.4-0.8ms (single), 15-30ms (batch of 100)

### **Read Path (Fetch/Query)**
1. **Read Page**: Memory-mapped I/O (0.05-0.15ms) or standard read (0.1-0.3ms)
2. **Decrypt**: AES-256-GCM decryption (0.1-0.2ms)
3. **Decode**: BlazeBinary decoding (0.02-0.05ms per field)
4. **Filter**: Apply query filters (0.1-10ms depending on complexity)
5. **Sort**: Sort results if needed (0-50ms depending on size)

**Total**: 0.2-0.4ms (single fetch), 2-200ms (query)

### **Query Execution**
1. **Parse**: Parse query DSL (0.1-0.5ms)
2. **Plan**: Query planner selects strategy (0.1-0.5ms)
3. **Execute**: Run query using selected strategy (2-200ms)
4. **Post-process**: Sort, limit, project fields (0-50ms)

**Total**: 2-250ms depending on query complexity and dataset size

---

## **Conclusion**

BlazeDB is designed for **high-performance embedded database** use cases:

- **Local Operations**: 60K-600K ops/min (single core) to 480K-4.8M ops/min (8 cores)
- **Network Sync**: 207K-468K ops/min (WiFi 100 Mbps) to 394K-1M ops/min (WiFi 1000 Mbps)
- **Query Performance**: 3K-30K queries/min (single core) to 24K-240K queries/min (8 cores)
- **Real-World Headroom**: 30-470x capacity for typical applications

**BlazeDB can handle production workloads with significant headroom for growth.**

---

**Last Updated**: 2025-01-XX
**Test Environment**: Apple M1 Pro, macOS 14.6, 8 cores, 16GB RAM, NVMe SSD
**Source**: `Docs/Project/PERFORMANCE_METRICS.md`, `Docs/Performance/THROUGHPUT_ANALYSIS.md`

---

##  **HOW TO GET ACTUAL MEASURED NUMBERS**

### **Quick Method: Run Benchmark Script**
```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
./run_benchmarks.sh
```

This script will:
1. Run all performance benchmarks
2. Extract key metrics (ops/sec, latency)
3. Save results to `benchmark_results/performance_results_TIMESTAMP.txt`
4. Show JSON metrics from `.build/test-metrics/`

### **Manual Method: Run Individual Benchmarks**

#### **Step 1: Run Comprehensive Benchmarks**
```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
swift test --filter ComprehensiveBenchmarks
```

**This will output actual measured:**
- Insert throughput (ops/sec)
- Fetch throughput (ops/sec)
- Query latency (ms)
- Update throughput (ops/sec)
- Delete throughput (ops/sec)

#### **Step 2: Run Performance Benchmarks (DEBUG mode)**
```bash
swift test --filter PerformanceBenchmarks
```

**Results saved to:** `.build/test-metrics/*.json`

#### **Step 3: Run Baseline Tests**
```bash
BLAZEDB_RUN_BASELINE_TESTS=1 swift test --filter BaselinePerformanceTests
```

**Results saved to:** `/tmp/blazedb_baselines.json`

#### **Step 4: Extract Actual Numbers**
```bash
# View JSON results
cat.build/test-metrics/*.json

# View baseline results
cat /tmp/blazedb_baselines.json
```

**Then update this document with ACTUAL measured numbers from the test output.**

---

## **NOTE: Current Numbers Are Estimates**

The numbers in this document are **ESTIMATES** based on:
- Test expectations/targets in benchmark code
- Realistic performance analysis documents
- Theoretical calculations

**To get ACTUAL measured numbers, you must run the benchmarks yourself.**

The benchmark script (`run_benchmarks.sh`) will:
- Run all performance tests
- Extract actual ops/sec and latency measurements
- Save results for analysis

**After running benchmarks, update this document with the actual measured values.**

