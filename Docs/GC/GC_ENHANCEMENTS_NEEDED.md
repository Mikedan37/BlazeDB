#  Garbage Collection Enhancements Needed

**Critical GC features missing for distributed sync, MVCC, and multi-database scenarios.**

---

## **Current GC Implementation**

### **What Exists:**
1. **Basic Record GC** - `StorageManager.performCleanup()` removes orphaned records
2. **MVCC Version GC** - `AutomaticGCManager` cleans up old MVCC versions
3. **Page-Level GC** - `PageGarbageCollector` reclaims unused pages
4. **Manual GC** - `runGarbageCollection()` for manual cleanup
5. **Auto GC** - Automatic GC on transaction commit

---

## **Missing GC Features**

### **1. Operation Log GC** **CRITICAL**

**Problem:**
- `OperationLog` grows indefinitely with every sync operation
- Stored in `operation_log.json` (can be GBs after months)
- No cleanup mechanism exists

**Impact:**
- Disk space exhaustion
- Slow sync startup (loading huge logs)
- Memory issues when loading logs

**Solution Needed:**
```swift
// Operation Log GC
class OperationLogGC {
 // Keep only last N operations per record
 func cleanupOldOperations(keepLast: Int = 1000) throws

 // Remove operations older than X days
 func cleanupOperationsOlderThan(days: Int) throws

 // Remove operations for records that no longer exist
 func cleanupOrphanedOperations() throws

 // Compact operation log (remove duplicates)
 func compactOperationLog() throws
}
```

**Implementation:**
- Add to `OperationLog` class
- Run periodically (daily/weekly)
- Configurable retention policy

---

### **2. Sync State GC** **CRITICAL**

**Problem:**
- `syncedRecords`, `recordVersions`, `lastSyncVersions` maps grow indefinitely
- Never cleaned up when records are deleted
- Memory leak in long-running sync

**Impact:**
- Memory exhaustion
- Slow sync operations (large maps)
- No cleanup of deleted records

**Solution Needed:**
```swift
// Sync State GC
extension BlazeSyncEngine {
 // Remove sync state for deleted records
 func cleanupSyncStateForDeletedRecords() async throws

 // Remove sync state older than X days
 func cleanupOldSyncState(olderThan: TimeInterval) async throws

 // Compact sync state (remove duplicates)
 func compactSyncState() async throws

 // Remove sync state for nodes that are no longer connected
 func cleanupSyncStateForDisconnectedNodes() async throws
}
```

**Implementation:**
- Add to `BlazeSyncEngine`
- Run on sync start/stop
- Clean up when records are deleted

---

### **3. MVCC Version GC for Distributed Sync** **HIGH PRIORITY**

**Problem:**
- MVCC versions can't be GC'd if other nodes are still reading them
- No coordination between nodes for version cleanup
- Versions accumulate across sync network

**Impact:**
- Disk space waste (can't GC versions in use elsewhere)
- Need to track which versions are in use across nodes
- Complex coordination required

**Solution Needed:**
```swift
// Distributed MVCC GC
class DistributedVersionGC {
 // Track minimum version in use across all nodes
 var minVersionInUse: [UUID: UInt64] = [:] // Record ID -> Min version

 // Request version cleanup from other nodes
 func requestVersionCleanup(recordID: UUID, minVersion: UInt64) async throws

 // Coordinate GC across nodes
 func coordinateGC(recordID: UUID) async throws -> UInt64 // Returns safe version to GC

 // Broadcast version usage to other nodes
 func broadcastVersionUsage(recordID: UUID, version: UInt64) async throws
}
```

**Implementation:**
- Add to `BlazeSyncEngine`
- Coordinate with `AutomaticGCManager`
- Use Lamport timestamps for ordering

---

### **4. Cross-Database GC Coordination** **HIGH PRIORITY**

**Problem:**
- Multiple databases on same device don't coordinate GC
- Can GC versions that other DBs are using
- No shared GC state

**Impact:**
- Data loss if DBs share data
- Inefficient GC (can't GC shared versions)
- No coordination for multi-DB scenarios

**Solution Needed:**
```swift
// Multi-Database GC Coordinator
class MultiDatabaseGCCoordinator {
 static let shared = MultiDatabaseGCCoordinator()

 // Register database for GC coordination
 func registerDatabase(_ db: BlazeDBClient, name: String) throws

 // Unregister database
 func unregisterDatabase(name: String) throws

 // Coordinate GC across all registered databases
 func coordinateGC() async throws

 // Get minimum safe version across all DBs
 func getMinimumSafeVersion(recordID: UUID) -> UInt64?
}
```

**Implementation:**
- Add to `BlazeDBManager`
- Coordinate with `AutomaticGCManager`
- Use shared state (file or in-memory)

---

### **5. Relay Memory GC** **MEDIUM PRIORITY**

**Problem:**
- `InMemoryRelay` queues can grow indefinitely
- No cleanup of old queued operations
- Memory leak in long-running sync

**Impact:**
- Memory exhaustion
- Slow relay operations
- No cleanup mechanism

**Solution Needed:**
```swift
// Relay Memory GC
extension InMemoryRelay {
 // Cleanup old queued operations
 func cleanupOldOperations(olderThan: TimeInterval) throws

 // Limit queue size
 func limitQueueSize(maxSize: Int) throws

 // Compact queue (remove duplicates)
 func compactQueue() throws
}
```

**Implementation:**
- Add to `InMemoryRelay`
- Run periodically
- Configurable limits

---

### **6. Conflict Resolution GC** **MEDIUM PRIORITY**

**Problem:**
- Old conflict versions accumulate
- No cleanup of resolved conflicts
- Can grow large over time

**Impact:**
- Disk space waste
- Slow conflict resolution
- No cleanup mechanism

**Solution Needed:**
```swift
// Conflict Resolution GC
extension ConflictResolution {
 // Cleanup resolved conflicts older than X days
 func cleanupResolvedConflicts(olderThan: TimeInterval) throws

 // Remove conflict versions that are no longer needed
 func cleanupOldConflictVersions() throws
}
```

**Implementation:**
- Add to `ConflictResolution`
- Run after conflict resolution
- Configurable retention

---

### **7. Sync Metadata GC** **MEDIUM PRIORITY**

**Problem:**
- Sync metadata (node info, connection state) accumulates
- No cleanup of disconnected nodes
- Can grow large over time

**Impact:**
- Memory waste
- Slow sync operations
- No cleanup mechanism

**Solution Needed:**
```swift
// Sync Metadata GC
extension BlazeTopology {
 // Cleanup metadata for disconnected nodes
 func cleanupDisconnectedNodeMetadata() async throws

 // Remove old sync metadata
 func cleanupOldSyncMetadata(olderThan: TimeInterval) async throws
}
```

**Implementation:**
- Add to `BlazeTopology`
- Run on node disconnect
- Configurable retention

---

### **8. Incremental Sync State GC** **MEDIUM PRIORITY**

**Problem:**
- `syncedRecords`, `recordVersions`, `lastSyncVersions` grow with every record
- No cleanup when records are deleted
- Memory leak over time

**Impact:**
- Memory exhaustion
- Slow sync operations
- No cleanup mechanism

**Solution Needed:**
```swift
// Incremental Sync State GC
extension BlazeSyncEngine {
 // Cleanup sync state for deleted records
 func cleanupSyncStateForDeletedRecords() async throws {
 let allRecords = try localDB.fetchAll()
 let existingIDs = Set(allRecords.map { $0.storage["id"]?.uuidValue?? UUID() })

 // Remove sync state for records that no longer exist
 syncedRecords = syncedRecords.filter { existingIDs.contains($0.key) }
 recordVersions = recordVersions.filter { existingIDs.contains($0.key) }
 lastSyncVersions = lastSyncVersions.mapValues { nodeVersions in
 nodeVersions.filter { existingIDs.contains($0.key) }
 }
 }

 // Cleanup old sync state (older than X days)
 func cleanupOldSyncState(olderThan: TimeInterval) async throws {
 let cutoff = Date().addingTimeInterval(-olderThan)
 // Implementation...
 }
}
```

**Implementation:**
- Add to `BlazeSyncEngine`
- Run periodically
- Clean up on record deletion

---

## **Implementation Priority**

### ** Critical (Do First):**
1. **Operation Log GC** - Prevents disk exhaustion
2. **Sync State GC** - Prevents memory leaks

### ** High Priority (Do Soon):**
3. **MVCC Version GC for Distributed Sync** - Prevents version accumulation
4. **Cross-Database GC Coordination** - Prevents data loss

### ** Medium Priority (Do Later):**
5. **Relay Memory GC** - Prevents memory leaks
6. **Conflict Resolution GC** - Prevents disk waste
7. **Sync Metadata GC** - Prevents memory waste
8. **Incremental Sync State GC** - Prevents memory leaks

---

## **Recommended Implementation Order**

1. **Phase 1: Operation Log GC** (1-2 days)
 - Add cleanup methods to `OperationLog`
 - Add periodic cleanup task
 - Add configuration options

2. **Phase 2: Sync State GC** (1-2 days)
 - Add cleanup methods to `BlazeSyncEngine`
 - Clean up on record deletion
 - Add periodic cleanup task

3. **Phase 3: MVCC Distributed GC** (3-5 days)
 - Add version tracking across nodes
 - Add coordination protocol
 - Integrate with `AutomaticGCManager`

4. **Phase 4: Cross-Database Coordination** (2-3 days)
 - Add `MultiDatabaseGCCoordinator`
 - Integrate with `BlazeDBManager`
 - Add shared state management

5. **Phase 5: Remaining Features** (3-5 days)
 - Relay memory GC
 - Conflict resolution GC
 - Sync metadata GC
 - Incremental sync state GC

---

## **Configuration Options Needed**

```swift
// GC Configuration for Distributed Sync
public struct DistributedGCConfig {
 // Operation Log
 var operationLogRetentionDays: Int = 30
 var operationLogMaxOperations: Int = 10_000

 // Sync State
 var syncStateRetentionDays: Int = 7
 var syncStateCleanupInterval: TimeInterval = 3600 // 1 hour

 // MVCC Versions
 var mvccVersionRetentionDays: Int = 7
 var mvccVersionCoordinationEnabled: Bool = true

 // Cross-Database
 var crossDatabaseGCEnabled: Bool = true
 var crossDatabaseGCInterval: TimeInterval = 3600 // 1 hour

 // Relay Memory
 var relayQueueMaxSize: Int = 10_000
 var relayQueueCleanupInterval: TimeInterval = 300 // 5 minutes
}
```

---

## **Testing Requirements**

For each GC feature, add tests:
1. **Unit Tests** - Test GC logic in isolation
2. **Integration Tests** - Test GC with real databases
3. **Performance Tests** - Ensure GC doesn't slow down operations
4. **Memory Tests** - Ensure GC actually frees memory
5. **Distributed Tests** - Test GC coordination across nodes

---

## **Summary**

**Current State:**
- Basic GC exists (records, MVCC versions, pages)
- No GC for distributed sync components
- No coordination across databases
- No cleanup of sync state

**Needed:**
- **Operation Log GC** (critical - prevents disk exhaustion)
- **Sync State GC** (critical - prevents memory leaks)
- **MVCC Distributed GC** (high - prevents version accumulation)
- **Cross-Database Coordination** (high - prevents data loss)
- **Remaining features** (medium - quality of life)

**Total Estimated Time:** 10-17 days for all features

---

**These GC enhancements are essential for production use of distributed BlazeDB!**

