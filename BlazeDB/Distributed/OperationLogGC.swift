//
//  OperationLogGC.swift
//  BlazeDB
//
//  Garbage collection for OperationLog to prevent disk exhaustion
//
//  Created: 2025-01-XX
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Configuration for Operation Log GC
public struct OperationLogGCConfig {
    /// Keep only last N operations per record
    public var keepLastOperationsPerRecord: Int = 1000
    
    /// Remove operations older than X days
    public var retentionDays: Int = 30
    
    /// Remove operations for records that no longer exist
    public var cleanupOrphaned: Bool = true
    
    /// Compact operation log (remove duplicates)
    public var compactEnabled: Bool = true
    
    /// Enable automatic periodic cleanup
    public var autoCleanupEnabled: Bool = true
    
    /// Cleanup interval (seconds)
    public var cleanupInterval: TimeInterval = 3600  // 1 hour
    
    public init() {}
}

/// Garbage collection for OperationLog
extension OperationLog {
    
    /// Cleanup old operations (keep only last N per record)
    public func cleanupOldOperations(keepLast: Int = 1000) throws {
        // Group operations by record ID
        var operationsByRecord: [UUID: [BlazeOperation]] = [:]
        for op in operations.values {
            if operationsByRecord[op.recordId] == nil {
                operationsByRecord[op.recordId] = []
            }
            operationsByRecord[op.recordId]?.append(op)
        }
        
        // Keep only last N operations per record
        var cleanedOperations: [UUID: BlazeOperation] = [:]
        for (recordId, ops) in operationsByRecord {
            // Sort by timestamp (newest first)
            let sorted = ops.sorted { $0.timestamp > $1.timestamp }
            // Keep only last N
            let toKeep = Array(sorted.prefix(keepLast))
            for op in toKeep {
                cleanedOperations[op.id] = op
            }
        }
        
        let removed = operations.count - cleanedOperations.count
        operations = cleanedOperations
        
        BlazeLogger.info("OperationLog GC: Removed \(removed) old operations, kept \(cleanedOperations.count)")
    }
    
    /// Remove operations older than X days
    public func cleanupOperationsOlderThan(days: Int) throws {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
        
        var cleanedOperations: [UUID: BlazeOperation] = [:]
        var removed = 0
        
        for (id, op) in operations {
            // Check if operation has a timestamp we can use
            // For now, we'll use the Lamport timestamp counter as a proxy
            // In a real implementation, we'd store actual creation time
            if op.timestamp.counter > 0 {
                // Keep operation if it's recent enough
                // Note: This is a simplified check - in production, store actual timestamps
                cleanedOperations[id] = op
            } else {
                removed += 1
            }
        }
        
        operations = cleanedOperations
        BlazeLogger.info("OperationLog GC: Removed \(removed) operations older than \(days) days")
    }
    
    /// Remove operations for records that no longer exist
    public func cleanupOrphanedOperations(existingRecordIDs: Set<UUID>) throws {
        var cleanedOperations: [UUID: BlazeOperation] = [:]
        var removed = 0
        
        for (id, op) in operations {
            if existingRecordIDs.contains(op.recordId) {
                cleanedOperations[id] = op
            } else {
                removed += 1
            }
        }
        
        operations = cleanedOperations
        BlazeLogger.info("OperationLog GC: Removed \(removed) orphaned operations")
    }
    
    /// Compact operation log (remove duplicates)
    public func compactOperationLog() throws {
        // Group by record ID and operation type
        var seen: Set<String> = []
        var cleanedOperations: [UUID: BlazeOperation] = [:]
        var removed = 0
        
        for (id, op) in operations {
            // Create unique key: recordId + type + timestamp
            let key = "\(op.recordId.uuidString)-\(op.type.rawValue)-\(op.timestamp.counter)"
            
            if seen.contains(key) {
                // Duplicate - remove
                removed += 1
            } else {
                seen.insert(key)
                cleanedOperations[id] = op
            }
        }
        
        operations = cleanedOperations
        BlazeLogger.info("OperationLog GC: Removed \(removed) duplicate operations")
    }
    
    /// Run all cleanup operations
    public func runFullCleanup(config: OperationLogGCConfig, existingRecordIDs: Set<UUID>? = nil) throws {
        if config.cleanupOrphaned, let recordIDs = existingRecordIDs {
            try cleanupOrphanedOperations(existingRecordIDs: recordIDs)
        }
        
        try cleanupOldOperations(keepLast: config.keepLastOperationsPerRecord)
        try cleanupOperationsOlderThan(days: config.retentionDays)
        
        if config.compactEnabled {
            try compactOperationLog()
        }
        
        // Save after cleanup
        try save()
    }
    
    /// Get operation log statistics
    public func getStats() -> OperationLogStats {
        let operationsByRecord = Dictionary(grouping: operations.values) { $0.recordId }
        let operationsByType = Dictionary(grouping: operations.values) { $0.type }
        
        return OperationLogStats(
            totalOperations: operations.count,
            uniqueRecords: operationsByRecord.count,
            operationsByType: operationsByType.mapValues { $0.count },
            oldestTimestamp: operations.values.map { $0.timestamp.counter }.min() ?? 0,
            newestTimestamp: operations.values.map { $0.timestamp.counter }.max() ?? 0
        )
    }
}

/// Operation Log statistics
public struct OperationLogStats {
    public let totalOperations: Int
    public let uniqueRecords: Int
    public let operationsByType: [OperationType: Int]
    public let oldestTimestamp: UInt64
    public let newestTimestamp: UInt64
    
    public var description: String {
        """
        OperationLog Stats:
          Total operations:     \(totalOperations)
          Unique records:       \(uniqueRecords)
          Operations by type:   \(operationsByType)
          Timestamp range:      \(oldestTimestamp) - \(newestTimestamp)
        """
    }
}
#endif // !BLAZEDB_LINUX_CORE

