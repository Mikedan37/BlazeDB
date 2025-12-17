//
//  ConnectionPool.swift
//  BlazeDB
//
//  Production-grade connection pooling for BlazeServer
//  Manages connection lifecycle, health checks, and resource limits
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Pooled connection with metadata
public struct PooledConnection {
    let id: UUID
    let connection: SecureConnection
    let syncEngine: BlazeSyncEngine
    let createdAt: Date
    var lastUsed: Date
    var useCount: Int
    var isHealthy: Bool
    var isInUse: Bool
    
    mutating func markUsed() {
        lastUsed = Date()
        useCount += 1
        isInUse = true
    }
    
    mutating func markAvailable() {
        isInUse = false
    }
}

/// Connection pool statistics
public struct ConnectionPoolStats {
    public let totalConnections: Int
    public let activeConnections: Int
    public let idleConnections: Int
    public let maxConnections: Int
    public let rejectedConnections: Int
    public let averageConnectionAge: TimeInterval
    public let averageUseCount: Double
}

/// Production-grade connection pool for BlazeServer
public actor ConnectionPool {
    private var connections: [UUID: PooledConnection] = [:]
    private var availableConnections: [UUID] = []  // Queue of available connection IDs
    private let maxConnections: Int
    private let maxIdleTime: TimeInterval
    private let healthCheckInterval: TimeInterval
    private var rejectedConnections: Int = 0
    private var healthCheckTask: Task<Void, Never>?
    
    /// Initialize connection pool
    /// - Parameters:
    ///   - maxConnections: Maximum concurrent connections (default: 100)
    ///   - maxIdleTime: Maximum idle time before closing (default: 300 seconds)
    ///   - healthCheckInterval: How often to check connection health (default: 60 seconds)
    public init(
        maxConnections: Int = 100,
        maxIdleTime: TimeInterval = 300.0,
        healthCheckInterval: TimeInterval = 60.0
    ) {
        self.maxConnections = maxConnections
        self.maxIdleTime = maxIdleTime
        self.healthCheckInterval = healthCheckInterval
        
        BlazeLogger.info("ConnectionPool initialized (max: \(maxConnections), idle: \(maxIdleTime)s, health: \(healthCheckInterval)s)")
        
        // Start health check task
        Task {
            await startHealthChecks()
        }
    }
    
    // MARK: - Connection Management
    
    /// Add a new connection to the pool
    /// - Parameters:
    ///   - connection: Secure connection
    ///   - syncEngine: Sync engine for this connection
    /// - Returns: Connection ID
    @discardableResult
    public func addConnection(
        connection: SecureConnection,
        syncEngine: BlazeSyncEngine
    ) -> UUID {
        let id = UUID()
        let pooled = PooledConnection(
            id: id,
            connection: connection,
            syncEngine: syncEngine,
            createdAt: Date(),
            lastUsed: Date(),
            useCount: 0,
            isHealthy: true,
            isInUse: false
        )
        
        connections[id] = pooled
        availableConnections.append(id)
        
        BlazeLogger.debug("Connection \(id) added to pool (\(connections.count)/\(maxConnections))")
        
        return id
    }
    
    /// Acquire a connection from the pool (reuse if available)
    /// - Returns: Pooled connection, or nil if pool is full
    public func acquireConnection() -> PooledConnection? {
        // Check if we're at max capacity
        guard connections.count < maxConnections else {
            rejectedConnections += 1
            BlazeLogger.warn("Connection pool full (\(connections.count)/\(maxConnections)), rejecting new connection")
            return nil
        }
        
        // Try to reuse an available connection
        while !availableConnections.isEmpty {
            let id = availableConnections.removeFirst()
            
            if var pooled = connections[id], pooled.isHealthy && !pooled.isInUse {
                // Reuse this connection
                pooled.markUsed()
                connections[id] = pooled
                
                BlazeLogger.debug("Reusing connection \(id) (use count: \(pooled.useCount))")
                return pooled
            }
        }
        
        // No available connection, but we have room for a new one
        return nil
    }
    
    /// Release a connection back to the pool
    /// - Parameter id: Connection ID
    public func releaseConnection(id: UUID) {
        guard var pooled = connections[id] else { return }
        
        pooled.markAvailable()
        connections[id] = pooled
        
        // Add back to available queue
        if !availableConnections.contains(id) {
            availableConnections.append(id)
        }
        
        BlazeLogger.debug("Connection \(id) released to pool")
    }
    
    /// Remove a connection from the pool
    /// - Parameter id: Connection ID
    public func removeConnection(id: UUID) async {
        if let pooled = connections[id] {
            // Stop sync engine
            await pooled.syncEngine.stop()
        }
        
        connections.removeValue(forKey: id)
        availableConnections.removeAll { $0 == id }
        
        BlazeLogger.debug("Connection \(id) removed from pool")
    }
    
    /// Close all connections and clear pool
    public func closeAll() async {
        BlazeLogger.info("Closing all connections in pool (\(connections.count) total)")
        
        for pooled in connections.values {
            await pooled.syncEngine.stop()
        }
        
        connections.removeAll()
        availableConnections.removeAll()
        rejectedConnections = 0
        
        BlazeLogger.info("Connection pool cleared")
    }
    
    // MARK: - Health Checks
    
    /// Start periodic health checks
    private func startHealthChecks() {
        healthCheckTask?.cancel()
        
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                await performHealthChecks()
            }
        }
    }
    
    /// Perform health checks on all connections
    private func performHealthChecks() async {
        let now = Date()
        var toRemove: [UUID] = []
        
        for (id, pooled) in connections {
            // Check if connection is too old
            let age = now.timeIntervalSince(pooled.lastUsed)
            if age > maxIdleTime && !pooled.isInUse {
                BlazeLogger.debug("Connection \(id) idle too long (\(Int(age))s), marking for removal")
                toRemove.append(id)
                continue
            }
            
            // Check connection health (basic check - connection still exists)
            // In a full implementation, we'd ping the connection
            var updated = pooled
            updated.isHealthy = true  // Assume healthy if still in connections dict
            connections[id] = updated
        }
        
        // Remove stale connections
        for id in toRemove {
            await removeConnection(id: id)
        }
        
        if !toRemove.isEmpty {
            BlazeLogger.info("Health check: Removed \(toRemove.count) stale connections")
        }
    }
    
    // MARK: - Statistics
    
    /// Get connection pool statistics
    public func getStats() -> ConnectionPoolStats {
        let now = Date()
        var totalAge: TimeInterval = 0
        var totalUseCount = 0
        
        for pooled in connections.values {
            totalAge += now.timeIntervalSince(pooled.createdAt)
            totalUseCount += pooled.useCount
        }
        
        let avgAge = connections.isEmpty ? 0 : totalAge / Double(connections.count)
        let avgUseCount = connections.isEmpty ? 0 : Double(totalUseCount) / Double(connections.count)
        
        let active = connections.values.filter { $0.isInUse }.count
        let idle = connections.count - active
        
        return ConnectionPoolStats(
            totalConnections: connections.count,
            activeConnections: active,
            idleConnections: idle,
            maxConnections: maxConnections,
            rejectedConnections: rejectedConnections,
            averageConnectionAge: avgAge,
            averageUseCount: avgUseCount
        )
    }
    
    /// Get connection count
    public func getConnectionCount() -> Int {
        return connections.count
    }
    
    /// Get available connection count
    public func getAvailableCount() -> Int {
        return availableConnections.count
    }
    
    deinit {
        healthCheckTask?.cancel()
    }
}


#endif // !BLAZEDB_LINUX_CORE
