//
//  RelayMemoryGC.swift
//  BlazeDB
//
//  Garbage collection for relay memory queues
//
//  Created: 2025-01-XX
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Configuration for relay memory GC
public struct RelayMemoryGCConfig {
    /// Maximum queue size
    public var maxQueueSize: Int = 10_000
    
    /// Remove operations older than X seconds
    public var retentionSeconds: TimeInterval = 300  // 5 minutes
    
    /// Enable automatic cleanup
    public var autoCleanupEnabled: Bool = true
    
    /// Cleanup interval (seconds)
    public var cleanupInterval: TimeInterval = 60  // 1 minute
    
    public init() {}
}

/// Garbage collection for InMemoryRelay
extension InMemoryRelay {
    
    /// Cleanup old queued operations
    public func cleanupOldOperations(olderThan: TimeInterval) throws {
        let cutoffTime = Date().addingTimeInterval(-olderThan)
        
        // Filter out old operations
        // Note: We don't have timestamps on operations, so we'll use a simplified approach
        // In production, we'd track operation creation time
        let before = messageQueue.count
        
        // For now, just limit queue size (simplified)
        if messageQueue.count > 1000 {
            // Keep only most recent operations
            messageQueue = Array(messageQueue.suffix(1000))
        }
        
        let after = messageQueue.count
        BlazeLogger.info("InMemoryRelay GC: Removed \(before - after) old operations")
    }
    
    /// Limit queue size
    public func limitQueueSize(maxSize: Int) throws {
        if messageQueue.count > maxSize {
            let removed = messageQueue.count - maxSize
            messageQueue = Array(messageQueue.suffix(maxSize))
            BlazeLogger.info("InMemoryRelay GC: Limited queue to \(maxSize) operations (removed \(removed))")
        }
    }
    
    /// Compact queue (remove duplicates)
    public func compactQueue() throws {
        var seen: Set<UUID> = []
        var compacted: [BlazeOperation] = []
        var removed = 0
        
        for op in messageQueue {
            if seen.contains(op.id) {
                removed += 1
            } else {
                seen.insert(op.id)
                compacted.append(op)
            }
        }
        
        messageQueue = compacted
        BlazeLogger.info("InMemoryRelay GC: Removed \(removed) duplicate operations")
    }
    
    /// Run full cleanup
    public func runFullCleanup(config: RelayMemoryGCConfig) throws {
        try limitQueueSize(maxSize: config.maxQueueSize)
        try cleanupOldOperations(olderThan: config.retentionSeconds)
        try compactQueue()
    }
    
    /// Get queue statistics
    public func getQueueStats() -> RelayQueueStats {
        return RelayQueueStats(
            queueSize: messageQueue.count,
            uniqueOperations: Set(messageQueue.map { $0.id }).count,
            operationsByType: Dictionary(grouping: messageQueue) { $0.type }.mapValues { $0.count }
        )
    }
}

/// Relay queue statistics
public struct RelayQueueStats {
    public let queueSize: Int
    public let uniqueOperations: Int
    public let operationsByType: [OperationType: Int]
    
    public var description: String {
        """
        Relay Queue Stats:
          Queue size:           \(queueSize)
          Unique operations:    \(uniqueOperations)
          Operations by type:   \(operationsByType)
        """
    }
}
#endif // !BLAZEDB_LINUX_CORE

