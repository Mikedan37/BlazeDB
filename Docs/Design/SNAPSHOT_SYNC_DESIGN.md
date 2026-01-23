# BlazeDB Snapshot-Based Initial Sync Design

**Status:** Design Document Only (No Implementation)
**Date:** 2025-01-XX
**Scope:** Design for snapshot-based initial sync to avoid replaying entire operation logs

---

## Problem Statement

### Current State: Op-Log Only Sync

BlazeDB currently uses **operation log (op-log) based sync only**. This means:

- **Incremental sync works well** - only changed operations are transferred
- **Initial sync is slow** - new devices must replay entire operation log (could be 100K+ operations)
- **No fast bootstrap** - large databases require downloading all historical operations
-  **Memory pressure** - large operation logs consume memory during replay
-  **Network bandwidth** - entire operation history must be transferred

### Example Problem

A database with 1 million records and 100K operations:
- **Current approach:** New device downloads 100K operations and replays them sequentially
- **Time:** 5-10 minutes on slow network
- **Memory:** 200MB+ for operation log in memory
- **Network:** 20-50MB of operation data

---

## Design Goals

1. **Fast Initial Sync:** New devices can bootstrap from a snapshot instead of replaying operations
2. **Backward Compatible:** Existing op-log sync continues to work
3. **Consistency Guarantees:** Snapshots are consistent with operation log
4. **Crash Safe:** Snapshot creation failures don't corrupt database
5. **Storage Efficient:** Snapshots are compressed and incremental where possible

---

## Snapshot Architecture

### Snapshot Contents

A snapshot contains:

1. **Database State:**
 - All records at snapshot timestamp
 - Record IDs and versions
 - Index definitions
 - Metadata (schema version, etc.)

2. **Snapshot Metadata:**
 - Snapshot timestamp (Lamport timestamp)
 - Snapshot version (monotonic counter)
 - Database checksum (for validation)
 - Record count
 - File size

3. **Compression:**
 - Snapshot data is compressed (LZ4 or ZLIB)
 - Compression ratio: 50-70% for typical data

### Snapshot Format

```
Snapshot File Structure:

 Header (64 bytes) 
 - Magic: "BZSN" (4 bytes) 
 - Version: UInt32 (1) 
 - Timestamp: LamportTimestamp 
 - Record Count: UInt64 
 - Checksum: UInt64 
 - Compression: UInt8 (0=none, 1=LZ4)
 - Reserved: 31 bytes 


 Compressed Snapshot Data 
 - Records (BlazeBinary format) 
 - Index Definitions (JSON) 
 - Metadata (JSON) 

```

---

## Snapshot Creation Timing

### Automatic Snapshot Creation

Snapshots are created automatically when:

1. **Operation Log Size Threshold:**
 - When operation log exceeds 10,000 operations
 - Prevents operation log from growing unbounded

2. **Time-Based:**
 - Every 24 hours (if operation log has changes)
 - Ensures recent snapshots are available

3. **Record Count Threshold:**
 - When database exceeds 100,000 records
 - Ensures large databases have snapshots

4. **Manual Trigger:**
 - Application can request snapshot creation
 - Useful before major migrations or backups

### Snapshot Retention

- **Keep last 3 snapshots** (oldest, middle, newest)
- **Delete snapshots older than 30 days**
- **Keep snapshot if operation log is corrupted** (fallback)

---

## Snapshot + Op-Log Handoff

### Initial Sync Flow

```

 1. Client connects to server 

 ↓

 2. Exchange sync state 
 - Client: lastSyncedTimestamp = 0 (new device) 
 - Server: lastSyncedTimestamp = T, hasSnapshot = Y 

 ↓

 3. Server determines sync strategy 
 IF client.lastSyncedTimestamp == 0: 
 → Use snapshot (fast bootstrap) 
 ELSE IF client.lastSyncedTimestamp < snapshot.timestamp:
 → Use snapshot + operations since snapshot 
 ELSE: 
 → Use op-log only (incremental sync) 

 ↓

 4a. Snapshot Transfer (if needed) 
 - Download snapshot file 
 - Validate checksum 
 - Decompress 
 - Load into database 

 ↓

 4b. Operation Replay (if needed) 
 - Pull operations since snapshot.timestamp 
 - Apply operations in order 
 - Update sync state 

 ↓

 5. Continue incremental sync 
 - Real-time operation exchange 

```

### Sync Strategy Selection

```swift
func selectSyncStrategy(
 clientState: SyncState,
 serverState: SyncState,
 snapshot: SnapshotMetadata?
) -> SyncStrategy {
 // New device - use snapshot if available
 if clientState.lastSyncedTimestamp == 0 {
 if let snapshot = snapshot {
 return.snapshot(snapshot)
 } else {
 return.fullOpLog // Fallback to op-log
 }
 }

 // Client is behind snapshot - use snapshot + operations
 if let snapshot = snapshot,
 clientState.lastSyncedTimestamp < snapshot.timestamp {
 return.snapshotPlusOps(snapshot, since: snapshot.timestamp)
 }

 // Client is up-to-date or ahead - use incremental op-log
 return.incrementalOpLog(since: clientState.lastSyncedTimestamp)
}
```

---

## Snapshot Validation

### Checksum Validation

- **Database checksum:** CRC32 or SHA-256 of all record data
- **Snapshot checksum:** Validated before loading
- **Mismatch indicates corruption:** Snapshot is rejected, fallback to op-log

### Consistency Validation

- **Timestamp validation:** Snapshot timestamp must be <= current operation log timestamp
- **Record count validation:** Snapshot record count must match database state at timestamp
- **Version validation:** Record versions in snapshot must match operation log state

### Failure Handling

- **Snapshot corruption:** Fallback to op-log sync
- **Checksum mismatch:** Re-download snapshot or use op-log
- **Timestamp inconsistency:** Use op-log (snapshot may be stale)

---

## Crash Safety

### Snapshot Creation

- **Atomic write:** Snapshot is written to temporary file, then renamed
- **Transaction safety:** Snapshot creation does not block database operations
- **Partial snapshot:** If creation fails, partial file is deleted, no corruption

### Snapshot Loading

- **Validation before load:** Snapshot is validated before applying to database
- **Rollback on failure:** If loading fails, database state is unchanged
- **Transaction boundary:** Snapshot loading is wrapped in transaction

### Interaction with Locking

- **Snapshot creation:** Requires exclusive database access (same as backup)
- **Snapshot loading:** Requires exclusive database access (same as restore)
- **File locking:** Snapshots are created/loaded with same locking as database operations

---

## Compatibility with Existing Sync

### Backward Compatibility

- **Op-log sync continues to work:** Existing sync logic unchanged
- **Gradual rollout:** Snapshots are optional, devices without snapshots use op-log
- **Protocol versioning:** Sync protocol includes snapshot support flag

### Protocol Extensions

```swift
// Extended SyncState
public struct SyncState {
 public let lastSyncedTimestamp: LamportTimestamp
 public let operationCount: Int
 public let nodeId: UUID

 // New fields for snapshot support
 public let hasSnapshot: Bool
 public let snapshotTimestamp: LamportTimestamp?
 public let snapshotVersion: UInt32?
}

// New sync messages
public enum SyncMessage {
 case syncState(SyncState)
 case requestSnapshot // Client requests snapshot
 case snapshotMetadata(SnapshotMetadata) // Server sends snapshot info
 case snapshotChunk(Data, chunkIndex: Int, totalChunks: Int) // Chunked transfer
 case operations([BlazeOperation]) // Existing op-log messages
}
```

### Incremental Migration

1. **Phase 1:** Add snapshot creation (server-side only)
2. **Phase 2:** Add snapshot transfer protocol (client can request)
3. **Phase 3:** Enable snapshot-based initial sync (opt-in)
4. **Phase 4:** Make snapshot default for new devices (after validation)

---

## Performance Considerations

### Snapshot Creation

- **Time:** 1-5 seconds for 100K records (depends on compression)
- **CPU:** 10-20% CPU during creation (compression overhead)
- **Disk I/O:** Sequential read of all records
- **Memory:** Temporary buffer for compression (same size as snapshot)

### Snapshot Transfer

- **Network:** 5-20MB for 100K records (compressed)
- **Time:** 10-60 seconds on typical network (depends on bandwidth)
- **Chunking:** Large snapshots are transferred in 1MB chunks
- **Resumable:** Failed transfers can resume from last chunk

### Snapshot Loading

- **Time:** 2-10 seconds for 100K records (decompression + insert)
- **CPU:** 5-15% CPU during loading
- **Disk I/O:** Sequential write of records
- **Memory:** Temporary buffer for decompression

### Comparison: Snapshot vs Op-Log

| Metric | Op-Log Only | Snapshot + Op-Log |
|--------|-------------|-------------------|
| Initial Sync Time | 5-10 min | 30-90 sec |
| Network Transfer | 20-50 MB | 5-20 MB |
| Memory Usage | 200 MB+ | 50-100 MB |
| CPU Usage | Low | Medium (compression) |
| Storage | Low (op-log) | Medium (snapshot) |

---

## Storage Requirements

### Snapshot Storage

- **Size:** 50-70% of database size (compressed)
- **Location:** Same directory as database file
- **Naming:** `database.snapshot.<timestamp>.blazedb`
- **Retention:** Last 3 snapshots (configurable)

### Storage Overhead

For a 100MB database:
- **Snapshot size:** 30-50MB (compressed)
- **3 snapshots:** 90-150MB
- **Total overhead:** ~100-150MB (acceptable for fast sync)

---

## Failure and Recovery Scenarios

### Scenario 1: Snapshot Creation Fails

**Cause:** Disk full, I/O error, crash during creation

**Handling:**
- Partial snapshot file is deleted
- Operation log sync continues normally
- Next snapshot attempt after threshold

**Impact:** None (op-log sync unaffected)

---

### Scenario 2: Snapshot Corruption

**Cause:** Disk corruption, network error during transfer

**Handling:**
- Checksum validation fails
- Snapshot is rejected
- Fallback to op-log sync
- Corrupted snapshot is deleted

**Impact:** Initial sync falls back to op-log (slower but works)

---

### Scenario 3: Snapshot Timestamp Inconsistency

**Cause:** Clock skew, operation log corruption

**Handling:**
- Timestamp validation fails
- Snapshot is rejected
- Fallback to op-log sync
- Snapshot is marked as invalid

**Impact:** Initial sync falls back to op-log

---

### Scenario 4: Crash During Snapshot Loading

**Cause:** Process crash, system crash

**Handling:**
- Database state is unchanged (transaction rollback)
- Snapshot loading is retried
- If retry fails, fallback to op-log

**Impact:** None (database state preserved)

---

## Implementation Considerations

### Non-Goals (Explicitly Out of Scope)

- **No implementation in this phase** - design only
- **No performance tuning** - design focuses on correctness
- **No protocol changes** - design is additive to existing sync
- **No snapshot merging** - snapshots are full, not incremental
- **No distributed snapshot coordination** - each node creates own snapshots

### Future Enhancements (Post-Design)

- **Incremental snapshots:** Only changed records since last snapshot
- **Snapshot compression:** Better algorithms (LZMA for archival)
- **Snapshot streaming:** Stream snapshot during creation (reduce memory)
- **Multi-node snapshots:** Coordinated snapshots across nodes
- **Snapshot versioning:** Multiple snapshot formats for compatibility

---

## Testing Strategy (When Implemented)

### Unit Tests

- Snapshot creation with various record counts
- Snapshot validation (checksum, timestamp, consistency)
- Snapshot compression/decompression
- Snapshot loading with rollback on failure

### Integration Tests

- Snapshot + op-log handoff (initial sync)
- Snapshot fallback to op-log (corruption scenarios)
- Snapshot creation during active database operations
- Snapshot loading with file locking

### Performance Tests

- Snapshot creation time vs record count
- Snapshot transfer time vs network speed
- Snapshot loading time vs record count
- Memory usage during snapshot operations

### Crash Tests

- Crash during snapshot creation
- Crash during snapshot loading
- Crash during snapshot transfer
- Recovery after crash

---

## Conclusion

Snapshot-based initial sync provides **fast bootstrap for new devices** while maintaining **backward compatibility** with existing op-log sync. The design is **crash-safe**, **consistent**, and **storage-efficient**.

**Key Benefits:**
- 10-20x faster initial sync (30-90 sec vs 5-10 min)
- 50-70% reduction in network transfer
- Backward compatible with op-log sync
- Crash-safe and validated

**Next Steps (When Implementing):**
1. Implement snapshot creation (server-side)
2. Add snapshot transfer protocol
3. Implement snapshot loading (client-side)
4. Add snapshot validation and fallback
5. Enable snapshot-based initial sync (opt-in)
6. Performance testing and optimization

---

**End of Snapshot-Based Sync Design Document**

