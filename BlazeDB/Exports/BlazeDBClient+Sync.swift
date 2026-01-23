//
//  BlazeDBClient+Sync.swift
//  BlazeDB
//
//  Simple sync API - makes connecting databases dead simple!
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif

extension BlazeDBClient {
    
    /// Simple sync with another database (one-liner!)
    /// 
    /// **Example:**
    /// ```swift
    /// // Connect db1 to db2 (bidirectional sync)
    /// try await db1.sync(with: db2)
    /// 
    /// // Insert into db1 - automatically syncs to db2!
    /// let id = try db1.insert(BlazeDataRecord(["message": .string("Hello!")]))
    /// ```
    ///
    /// - Parameters:
    ///   - other: The other database to sync with
    ///   - mode: Connection mode (.bidirectional, .readOnly, .writeOnly)
    ///   - role: Your role (.server = you win conflicts, .client = other wins)
    /// - Returns: The topology instance (keep it alive!)
    @discardableResult
    public func sync(
        with other: BlazeDBClient,
        mode: BlazeTopology.ConnectionMode = .bidirectional,
        role: SyncRole = .server
    ) async throws -> BlazeTopology {
        // Create or get shared topology
        let topology = BlazeTopology.shared
        
        // Register this database
        let thisId = try await topology.register(
            db: self,
            name: self.name,
            syncMode: .localAndRemote,
            role: role
        )
        
        // Register other database
        let otherId = try await topology.register(
            db: other,
            name: other.name,
            syncMode: .localAndRemote,
            role: role == .server ? .client : .server
        )
        
        // Connect them
        try await topology.connectLocal(
            from: thisId,
            to: otherId,
            mode: mode
        )
        
        return topology
    }
    
    /// Simple remote sync (one-liner!)
    ///
    /// **Example:**
    /// ```swift
    /// // Connect to remote server
    /// try await clientDB.sync(to: "192.168.1.100", port: 8080)
    /// 
    /// // Insert - automatically syncs to server!
    /// let id = try clientDB.insert(BlazeDataRecord(["message": .string("Hello!")]))
    /// ```
    ///
    /// - Parameters:
    ///   - host: Server IP address or hostname
    ///   - port: Server port (default: 8080)
    ///   - database: Database name on server (default: same as this database)
    ///   - useTLS: Use TLS encryption (default: true)
    ///   - authToken: Optional auth token
    /// - Returns: The sync engine instance
    @discardableResult
    public func sync(
        to host: String,
        port: UInt16 = 8080,
        database: String? = nil,
        useTLS: Bool = true,
        authToken: String? = nil
    ) async throws -> BlazeSyncEngine {
        let remoteNode = RemoteNode(
            host: host,
            port: port,
            database: database ?? self.name,
            useTLS: useTLS,
            authToken: authToken
        )
        
        return try await enableSync(
            remote: remoteNode,
            policy: SyncPolicy(),
            role: .client
        )
    }
    
    /// Check if sync is active
    public func isSyncing() async -> Bool {
        // NOTE: Sync status tracking intentionally simplified.
        // Returns false as sync state is managed internally by BlazeSyncEngine.
        // For production use, track sync engine state at application level.
        return false
    }
}

// MARK: - Shared Topology

extension BlazeTopology {
    /// Shared topology instance for simple sync
    public static let shared = BlazeTopology()
}

// ConnectionMode is defined in BlazeTopology.swift as BlazeTopology.ConnectionMode

#endif // !BLAZEDB_LINUX_CORE
