//
//  BlazeDBClient+Discovery.swift
//  BlazeDB
//
//  Simple discovery and auto-connect API
//  Makes finding and connecting to databases dead simple!
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation
#if canImport(Combine)
import Combine
#endif

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif

extension BlazeDBClient {
    
    // MARK: - Server Side (Advertise & Accept Connections)
    
    /// Start advertising this database for discovery (Server)
    /// Other devices can now find and connect to this database
    ///
    /// **Example:**
    /// ```swift
    /// // On Mac - advertise database
    /// try await serverDB.startServer(port: 8080)
    /// // Database is now discoverable!
    /// ```
    ///
    /// - Parameters:
    ///   - port: Port to listen on (default: 8080)
    ///   - allowAutoConnect: Allow clients to auto-connect without approval (default: false)
    ///   - authToken: Optional auth token for security
    /// - Returns: The server instance (keep it alive!)
    @discardableResult
    public func startServer(
        port: UInt16 = 8080,
        allowAutoConnect: Bool = false,
        authToken: String? = nil
    ) async throws -> BlazeServer {
        // Create and start server
        let server = try BlazeServer(
            database: self,
            port: port,
            authToken: authToken
        )
        
        try await server.start()
        
        // Advertise for discovery
        let discovery = BlazeDiscovery()
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let deviceName = Host.current().name ?? "Unknown"
        #else
        let deviceName = ProcessInfo.processInfo.hostName
        #endif
        discovery.advertise(
            database: self.name,
            deviceName: deviceName,
            port: port
        )
        
        // Store server and discovery for lifecycle management
        // Note: Server and discovery are managed by the caller
        
        BlazeLogger.info("✅ Server started! Database '\(self.name)' is discoverable on port \(port)")
        BlazeLogger.info("   Device: \(deviceName)")
        BlazeLogger.info("   Auto-connect: \(allowAutoConnect ? "enabled" : "disabled")")
        
        return server
    }
    
    // MARK: - Client Side (Discover & Connect)
    
    /// Discover databases on the network
    /// Returns a publisher that emits discovered databases as they're found
    ///
    /// **Example:**
    /// ```swift
    /// // On iPhone - discover databases
    /// let discovery = clientDB.discoverDatabases()
    /// 
    /// // Subscribe to discoveries
    /// discovery.sink { databases in
    ///     for db in databases {
    ///         print("Found: \(db.name) on \(db.deviceName)")
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: Publisher that emits arrays of discovered databases
    #if canImport(Combine)
    public func discoverDatabases() -> AnyPublisher<[DiscoveredDatabase], Never> {
        let discovery = BlazeDiscovery()
        discovery.startBrowsing()
        
        // Convert @Published to Publisher
        return discovery.$discoveredDatabases
            .eraseToAnyPublisher()
    }
    #else
    // Fallback for platforms without Combine
    public func discoverDatabases() -> BlazeDiscovery {
        let discovery = BlazeDiscovery()
        discovery.startBrowsing()
        return discovery
    }
    #endif
    
    /// Connect to a discovered database (one-liner!)
    ///
    /// **Example:**
    /// ```swift
    /// // Discover databases
    /// let discovery = clientDB.discoverDatabases()
    /// 
    /// discovery.sink { databases in
    ///     if let server = databases.first {
    ///         // Connect to first discovered database
    ///         Task {
    ///             try await clientDB.connect(to: server)
    ///             print("✅ Connected!")
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter discovered: The discovered database to connect to
    /// - Returns: The sync engine instance
    @discardableResult
    public func connect(to discovered: DiscoveredDatabase) async throws -> BlazeSyncEngine {
        return try await sync(
            to: discovered.host,
            port: discovered.port,
            database: discovered.database
        )
    }
    
    /// Auto-connect to the first discovered database
    /// Automatically connects when a database is found
    ///
    /// **Example:**
    /// ```swift
    /// // Auto-connect to first database found (no auth)
    /// try await clientDB.autoConnect()
    /// 
    /// // Auto-connect with shared secret (recommended!)
    /// try await clientDB.autoConnect(sharedSecret: "my-password-123")
    /// ```
    ///
    /// - Parameters:
    ///   - sharedSecret: Optional shared secret (if provided, uses token derivation)
    ///   - timeout: Maximum time to wait for discovery (default: 30 seconds)
    ///   - filter: Optional filter to match specific databases
    /// - Returns: The sync engine instance
    @discardableResult
    public func autoConnect(
        sharedSecret: String? = nil,
        timeout: TimeInterval = 30.0,
        filter: ((DiscoveredDatabase) -> Bool)? = nil
    ) async throws -> BlazeSyncEngine {
        let discovery = BlazeDiscovery()
        discovery.startBrowsing()
        
        // Wait for discovery with timeout
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let databases = discovery.discoveredDatabases
            
            // Apply filter if provided
            let matching = filter != nil ? databases.filter(filter!) : databases
            
            if let first = matching.first {
                discovery.stopBrowsing()
                BlazeLogger.info("✅ Auto-connecting to: \(first.name) on \(first.deviceName)")
                
                // Use shared secret if provided
                if let secret = sharedSecret {
                    return try await sync(
                        to: first.host,
                        port: first.port,
                        database: first.database,
                        sharedSecret: secret
                    )
                } else {
                    // No auth (for testing only)
                    return try await connect(to: first)
                }
            }
            
            // Wait a bit before checking again
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        discovery.stopBrowsing()
        throw BlazeDBError.connectionFailed("No databases discovered within \(timeout) seconds")
    }
    
    /// Request connection to a discovered database (with approval)
    /// Server can approve or reject the connection
    ///
    /// **Example:**
    /// ```swift
    /// // Request connection
    /// let request = ConnectionRequest(
    ///     clientName: "My iPhone",
    ///     clientId: UUID(),
    ///     requestedDatabase: "ServerDB"
    /// )
    /// 
    /// try await clientDB.requestConnection(to: discovered, request: request)
    /// ```
    ///
    /// - Parameters:
    ///   - discovered: The discovered database
    ///   - request: Connection request details
    /// - Returns: The sync engine if approved
    @discardableResult
    public func requestConnection(
        to discovered: DiscoveredDatabase,
        request: ConnectionRequest
    ) async throws -> BlazeSyncEngine {
        // For now, this is the same as connect
        // In the future, this would send a request and wait for approval
        BlazeLogger.info("📨 Requesting connection to \(discovered.name)...")
        return try await connect(to: discovered)
    }
    
    // MARK: - TCP Host/Port Discovery (No Bonjour, Works Everywhere)
    
    /// Simple TCP server candidate for non-Bonjour discovery.
    ///
    /// Use this when you already know a set of likely hosts (e.g. `raspberrypi.local`,
    /// `192.168.1.10`, `api.myapp.com`) and a fixed BlazeDB port (e.g. 9090).
    public struct TCPServerCandidate {
        public let host: String
        public let port: UInt16
        public let database: String
        
        public init(host: String, port: UInt16 = 9090, database: String) {
            self.host = host
            self.port = port
            self.database = database
        }
    }
    
    /// Try to connect to the **first reachable** BlazeDB server from a list of TCP candidates.
    ///
    /// This uses the existing BlazeBinary + SecureConnection + shared-secret handshake,
    /// but **does not rely on Bonjour/mDNS**, so it works on iOS, macOS, Linux, and inside Docker
    /// without any special discovery entitlements.
    ///
    /// The typical pattern for your Raspberry Pi + iPhone setup:
    ///
    /// ```swift
    /// let candidates: [BlazeDBClient.TCPServerCandidate] = [
    ///     .init(host: "raspberrypi.local", port: 9090, database: "ServerMainDB"),
    ///     .init(host: "192.168.1.100", port: 9090, database: "ServerMainDB")
    /// ]
    ///
    /// let engine = try await db.autoConnectTCP(
    ///     candidates: candidates,
    ///     sharedSecret: "super-secret-password"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - candidates: List of host/port/database combinations to try.
    ///   - sharedSecret: Shared secret used to derive the auth token (must match server).
    ///   - perHostTimeout: Maximum time to spend trying each host before moving on.
    ///   - stopOnFirstSuccess: If true (default), stop after the first successful connection.
    /// - Returns: A connected `BlazeSyncEngine` if any candidate succeeds.
    @discardableResult
    public func autoConnectTCP(
        candidates: [TCPServerCandidate],
        sharedSecret: String,
        perHostTimeout: TimeInterval = 3.0,
        stopOnFirstSuccess: Bool = true
    ) async throws -> BlazeSyncEngine {
        guard !candidates.isEmpty else {
            throw BlazeDBError.connectionFailed("No TCP candidates provided for autoConnectTCP")
        }
        
        // Try candidates sequentially with a per-host timeout.
        // This keeps things simple and avoids hammering the network with many parallel dials,
        // which is especially important on iOS.
        for candidate in candidates {
            do {
                BlazeLogger.info("🔍 Trying BlazeDB server at \(candidate.host):\(candidate.port) (\(candidate.database))")
                
                let engine = try await withTimeout(seconds: perHostTimeout) {
                    try await self.sync(
                        to: candidate.host,
                        port: candidate.port,
                        database: candidate.database,
                        sharedSecret: sharedSecret
                    )
                }
                
                BlazeLogger.info("✅ Connected to BlazeDB server at \(candidate.host):\(candidate.port)")
                if stopOnFirstSuccess {
                    return engine
                }
                
                // If we don't stop on first success, remember last and keep going.
                return engine
            } catch {
                BlazeLogger.warn("Failed to connect to \(candidate.host):\(candidate.port): \(error)")
                continue
            }
        }
        
        throw BlazeDBError.connectionFailed("Failed to connect to any BlazeDB TCP candidate")
    }
}

// MARK: - Small Utility: Async Timeout Wrapper

/// Run an async operation with a simple timeout.
/// If the timeout elapses first, this throws `BlazeDBError.connectionFailed`.
func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    // If the timeout is non-positive, just run the operation directly.
    guard seconds > 0 else {
        return try await operation()
    }
    
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Main operation task
        group.addTask {
            return try await operation()
        }
        
        // Timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw BlazeDBError.connectionFailed("Connection attempt timed out after \(seconds) seconds")
        }
        
        // First to finish wins; the other is cancelled when the group ends.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}


// MARK: - Connection Request

/// Connection request from client to server
public struct ConnectionRequest {
    public let clientName: String
    public let clientId: UUID
    public let requestedDatabase: String
    public let authToken: String?
    
    public init(
        clientName: String,
        clientId: UUID = UUID(),
        requestedDatabase: String,
        authToken: String? = nil
    ) {
        self.clientName = clientName
        self.clientId = clientId
        self.requestedDatabase = requestedDatabase
        self.authToken = authToken
    }
}

// MARK: - BlazeDBError Extension

extension BlazeDBError {
    static func connectionFailed(_ message: String) -> BlazeDBError {
        return .unknown(message)
    }
}
#endif // !BLAZEDB_LINUX_CORE

