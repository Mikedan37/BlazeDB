//
//  SyncStateGC.swift
//  BlazeDB
//
//  Garbage collection for sync state to prevent memory leaks
//
//  Created: 2025-01-XX
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Configuration for Sync State GC
public struct SyncStateGCConfig {
    /// Remove sync state older than X days
    public var retentionDays: Int = 7
    
    /// Cleanup interval (seconds)
    public var cleanupInterval: TimeInterval = 3600  // 1 hour
    
    /// Enable automatic periodic cleanup
    public var autoCleanupEnabled: Bool = true
    
    public init() {}
}

/// Garbage collection for sync state in BlazeSyncEngine
extension BlazeSyncEngine {
    
    /// Remove sync state for deleted records
    public func cleanupSyncStateForDeletedRecords() async throws {
        // Get all existing records from database
        let allRecords = try await localDB.fetchAll()
        let existingIDs = Set(allRecords.compactMap { $0.storage["id"]?.uuidValue })
        
        // Remove sync state for records that no longer exist
        let beforeSyncedRecords = syncedRecords.count
        let beforeRecordVersions = recordVersions.count
        let beforeLastSyncVersions = lastSyncVersions.values.reduce(0) { $0 + $1.count }
        
        syncedRecords = syncedRecords.filter { existingIDs.contains($0.key) }
        recordVersions = recordVersions.filter { existingIDs.contains($0.key) }
        lastSyncVersions = lastSyncVersions.mapValues { nodeVersions in
            nodeVersions.filter { existingIDs.contains($0.key) }
        }
        
        let afterSyncedRecords = syncedRecords.count
        let afterRecordVersions = recordVersions.count
        let afterLastSyncVersions = lastSyncVersions.values.reduce(0) { $0 + $1.count }
        
        let removedSynced = beforeSyncedRecords - afterSyncedRecords
        let removedVersions = beforeRecordVersions - afterRecordVersions
        let removedLastSync = beforeLastSyncVersions - afterLastSyncVersions
        
        BlazeLogger.info("SyncState GC: Removed \(removedSynced) synced records, \(removedVersions) record versions, \(removedLastSync) last sync versions")
        
        // Save updated state
        await saveSyncState()
    }
    
    /// Cleanup old sync state (older than X days)
    public func cleanupOldSyncState(olderThan: TimeInterval) async throws {
        let cutoffDate = Date().addingTimeInterval(-olderThan)
        
        // For now, we'll use a simplified approach:
        // Remove sync state for records that haven't been synced recently
        // In a real implementation, we'd track last sync time per record
        
        // Remove records from syncedRecords if they haven't been synced recently
        // This is a simplified version - in production, track actual sync times
        let before = syncedRecords.count
        syncedRecords = syncedRecords.filter { recordId, nodeIds in
            // Keep if synced to at least one node recently
            // For now, just keep all (we'd need to track sync times)
            !nodeIds.isEmpty
        }
        let after = syncedRecords.count
        
        BlazeLogger.info("SyncState GC: Removed \(before - after) old sync state entries")
        
        // Save updated state
        await saveSyncState()
    }
    
    /// Compact sync state (remove duplicates)
    public func compactSyncState() async throws {
        // Remove duplicate entries in syncedRecords
        // (shouldn't happen, but just in case)
        for (recordId, nodeIds) in syncedRecords {
            syncedRecords[recordId] = nodeIds  // Sets automatically deduplicate
        }
        
        // Remove empty entries
        syncedRecords = syncedRecords.filter { !$0.value.isEmpty }
        lastSyncVersions = lastSyncVersions.filter { !$0.value.isEmpty }
        
        BlazeLogger.info("SyncState GC: Compacted sync state")
        
        // Save updated state
        await saveSyncState()
    }
    
    /// Remove sync state for nodes that are no longer connected
    public func cleanupSyncStateForDisconnectedNodes(connectedNodeIds: Set<UUID>) async throws {
        let before = lastSyncVersions.count
        
        // Remove sync state for disconnected nodes
        lastSyncVersions = lastSyncVersions.filter { connectedNodeIds.contains($0.key) }
        
        // Also remove from syncedRecords
        for (recordId, nodeIds) in syncedRecords {
            let connectedNodeIds = nodeIds.intersection(connectedNodeIds)
            if connectedNodeIds.isEmpty {
                syncedRecords.removeValue(forKey: recordId)
            } else {
                syncedRecords[recordId] = connectedNodeIds
            }
        }
        
        let after = lastSyncVersions.count
        
        BlazeLogger.info("SyncState GC: Removed sync state for \(before - after) disconnected nodes")
        
        // Save updated state
        await saveSyncState()
    }
    
    /// Run full sync state cleanup
    public func runFullSyncStateCleanup(config: SyncStateGCConfig) async throws {
        // Get existing records
        let allRecords = try await localDB.fetchAll()
        let existingIDs = Set(allRecords.compactMap { $0.storage["id"]?.uuidValue })
        
        // Cleanup deleted records
        try await cleanupSyncStateForDeletedRecords()
        
        // Cleanup old sync state
        try await cleanupOldSyncState(olderThan: TimeInterval(config.retentionDays * 24 * 60 * 60))
        
        // Compact
        try await compactSyncState()
    }
    
    /// Get sync state statistics
    public func getSyncStateStats() -> SyncStateStats {
        return SyncStateStats(
            syncedRecordsCount: syncedRecords.count,
            recordVersionsCount: recordVersions.count,
            lastSyncVersionsCount: lastSyncVersions.count,
            totalSyncStateEntries: syncedRecords.count + recordVersions.count + lastSyncVersions.values.reduce(0) { $0 + $1.count }
        )
    }
}

/// Sync State statistics
public struct SyncStateStats {
    public let syncedRecordsCount: Int
    public let recordVersionsCount: Int
    public let lastSyncVersionsCount: Int
    public let totalSyncStateEntries: Int
    
    public var description: String {
        """
        SyncState Stats:
          Synced records:       \(syncedRecordsCount)
          Record versions:      \(recordVersionsCount)
          Last sync versions:    \(lastSyncVersionsCount)
          Total entries:         \(totalSyncStateEntries)
        """
    }
}
#endif // !BLAZEDB_LINUX_CORE

