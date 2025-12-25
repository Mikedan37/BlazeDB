//
//  SyncMetadataGC.swift
//  BlazeDB
//
//  Garbage collection for sync metadata
//
//  Created: 2025-01-XX
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Configuration for sync metadata GC
public struct SyncMetadataGCConfig {
    /// Remove metadata older than X days
    public var retentionDays: Int = 30
    
    /// Enable automatic cleanup
    public var autoCleanupEnabled: Bool = true
    
    /// Cleanup interval (seconds)
    public var cleanupInterval: TimeInterval = 3600  // 1 hour
    
    public init() {}
}

/// Garbage collection for sync metadata in BlazeTopology
extension BlazeTopology {
    
    /// Cleanup metadata for disconnected nodes
    public func cleanupDisconnectedNodeMetadata() async throws {
        // Get all connected node IDs
        let connectedNodeIds = Set(connections.map { $0.from })
        connectedNodeIds.formUnion(Set(connections.map { $0.to }))
        
        // Remove nodes that are no longer connected
        let before = nodes.count
        nodes = nodes.filter { connectedNodeIds.contains($0.key) }
        let after = nodes.count
        
        BlazeLogger.info("SyncMetadata GC: Removed metadata for \(before - after) disconnected nodes")
    }
    
    /// Remove old sync metadata
    public func cleanupOldSyncMetadata(olderThan: TimeInterval) async throws {
        // In a real implementation, we'd track metadata creation time
        // For now, just cleanup disconnected nodes
        try await cleanupDisconnectedNodeMetadata()
    }
    
    /// Run full cleanup
    public func runFullCleanup(config: SyncMetadataGCConfig) async throws {
        try await cleanupDisconnectedNodeMetadata()
        try await cleanupOldSyncMetadata(olderThan: TimeInterval(config.retentionDays * 24 * 60 * 60))
    }
    
    /// Get metadata statistics
    public func getMetadataStats() -> SyncMetadataStats {
        return SyncMetadataStats(
            totalNodes: nodes.count,
            totalConnections: connections.count,
            localConnections: connections.filter { $0.type == BlazeTopology.ConnectionType.local }.count,
            crossAppConnections: connections.filter { $0.type == BlazeTopology.ConnectionType.crossApp }.count,
            remoteConnections: connections.filter { $0.type == BlazeTopology.ConnectionType.remote }.count
        )
    }
}

/// Sync metadata statistics
public struct SyncMetadataStats {
    public let totalNodes: Int
    public let totalConnections: Int
    public let localConnections: Int
    public let crossAppConnections: Int
    public let remoteConnections: Int
    
    public var description: String {
        """
        Sync Metadata Stats:
          Total nodes:           \(totalNodes)
          Total connections:     \(totalConnections)
          Local connections:     \(localConnections)
          Cross-app connections: \(crossAppConnections)
          Remote connections:    \(remoteConnections)
        """
    }
}
#endif // !BLAZEDB_LINUX_CORE

