//
//  MultiDatabaseGCCoordinator.swift
//  BlazeDB
//
//  Coordinates GC across multiple databases on the same device
//
//  Created: 2025-01-XX
//

import Foundation

/// Coordinates garbage collection across multiple databases
public actor MultiDatabaseGCCoordinator {
    public static let shared = MultiDatabaseGCCoordinator()
    
    private var registeredDatabases: [String: BlazeDBClient] = [:]
    private var gcConfig: MultiDatabaseGCConfig
    private var lastGCTime: Date = Date()
    
    private init() {
        self.gcConfig = MultiDatabaseGCConfig()
    }
    
    /// Register a database for GC coordination
    public func registerDatabase(_ db: BlazeDBClient, name: String) throws {
        registeredDatabases[name] = db
        BlazeLogger.info("Registered database '\(name)' for GC coordination")
    }
    
    /// Unregister a database
    public func unregisterDatabase(name: String) throws {
        registeredDatabases.removeValue(forKey: name)
        BlazeLogger.info("Unregistered database '\(name)' from GC coordination")
    }
    
    /// Coordinate GC across all registered databases
    public func coordinateGC() async throws {
        let now = Date()
        let timeSinceLastGC = now.timeIntervalSince(lastGCTime)
        
        // Check if it's time for GC
        guard timeSinceLastGC >= gcConfig.coordinationInterval else {
            return
        }
        
        BlazeLogger.info("Coordinating GC across \(registeredDatabases.count) databases")
        
        // Get minimum safe versions across all databases
        var globalMinVersions: [UUID: UInt64] = [:]
        
        for (name, db) in registeredDatabases {
            // Get MVCC stats for this database
            if db.isMVCCEnabled() {
                let stats = db.getMVCCStats()
                // In a real implementation, we'd track versions per record
                // For now, we'll just coordinate the GC timing
                BlazeLogger.debug("Database '\(name)': \(stats.totalVersions) versions")
            }
        }
        
        // Run GC on each database (coordinated)
        for (name, db) in registeredDatabases {
            do {
                let removed = db.runGarbageCollection()
                BlazeLogger.info("Database '\(name)': Removed \(removed) versions")
            } catch {
                BlazeLogger.warn("Failed to run GC on database '\(name)': \(error.localizedDescription)")
            }
        }
        
        lastGCTime = now
    }
    
    /// Get minimum safe version across all databases for a record
    public func getMinimumSafeVersion(recordID: UUID) -> UInt64? {
        // In a real implementation, we'd query all databases for their minimum versions
        // For now, return nil (no coordination needed)
        return nil
    }
    
    /// Update GC configuration
    public func updateConfig(_ config: MultiDatabaseGCConfig) {
        self.gcConfig = config
    }
    
    /// Get current configuration
    public func getConfig() -> MultiDatabaseGCConfig {
        return gcConfig
    }
    
    /// Get statistics
    public func getStats() -> MultiDatabaseGCStats {
        return MultiDatabaseGCStats(
            registeredDatabases: registeredDatabases.count,
            lastGCTime: lastGCTime,
            coordinationInterval: gcConfig.coordinationInterval
        )
    }
}

/// Configuration for multi-database GC coordination
public struct MultiDatabaseGCConfig {
    /// Coordination interval (seconds)
    public var coordinationInterval: TimeInterval = 3600  // 1 hour
    
    /// Enable cross-database GC
    public var enabled: Bool = true
    
    public init() {}
}

/// Multi-database GC statistics
public struct MultiDatabaseGCStats {
    public let registeredDatabases: Int
    public let lastGCTime: Date
    public let coordinationInterval: TimeInterval
    
    public var description: String {
        """
        Multi-Database GC Stats:
          Registered databases:  \(registeredDatabases)
          Last GC time:          \(lastGCTime)
          Coordination interval: \(coordinationInterval)s
        """
    }
}

