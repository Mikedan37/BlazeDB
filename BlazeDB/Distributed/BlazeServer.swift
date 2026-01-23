//
//  BlazeServer.swift
//  BlazeDB Distributed
//
//  Server for accepting remote database connections
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif

/// Server that accepts remote BlazeDB connections
/// Platform-neutral wrapper around ServerTransportProvider
public actor BlazeServer {
    private let port: UInt16
    private let database: BlazeDBClient
    private let databaseName: String
    private let authToken: String?
    private let sharedSecret: String?
    private let transportProvider: ServerTransportProvider
    private var isRunning = false
    private var connections: [UUID: SecureConnection] = [:]
    private var syncEngines: [UUID: BlazeSyncEngine] = [:]
    
    /// Initialize with a custom transport provider
    /// - Parameters:
    ///   - port: Port number to listen on
    ///   - database: Database client instance
    ///   - databaseName: Name of the database
    ///   - authToken: Optional authentication token
    ///   - sharedSecret: Optional shared secret for authentication
    ///   - transportProvider: Transport provider to use (defaults to platform-appropriate provider)
    public init(
        port: UInt16 = 8080,
        database: BlazeDBClient,
        databaseName: String,
        authToken: String? = nil,
        sharedSecret: String? = nil,
        transportProvider: ServerTransportProvider? = nil
    ) {
        self.port = port
        self.database = database
        self.databaseName = databaseName
        self.authToken = authToken
        self.sharedSecret = sharedSecret
        self.transportProvider = transportProvider ?? DefaultServerTransportProvider()
    }
    
    /// Start listening for connections
    public func start() async throws {
        guard !isRunning else { return }
        
        // Check if transport is available
        guard transportProvider.isAvailable() else {
            throw ServerTransportError.notAvailable
        }
        
        // Start server using transport provider
        try await transportProvider.startServer(port: port) { [weak self] serverConnection in
            guard let self = self else { return }
            await self.handleConnection(serverConnection)
        }
        
        self.isRunning = true
        
        BlazeLogger.info("BlazeServer listening on port \(port) (database: \(databaseName), auth: \(authToken != nil ? "enabled" : "disabled"))")
    }
    
    /// Stop listening
    public func stop() async {
        guard isRunning else { return }
        
        await transportProvider.stopServer()
        isRunning = false
        
        // Stop all sync engines
        for engine in syncEngines.values {
            await engine.stop()
        }
        syncEngines.removeAll()
        connections.removeAll()
        
        BlazeLogger.info("BlazeServer stopped")
    }
    
    /// Handle incoming connection
    private func handleConnection(_ serverConnection: ServerConnection) async {
        let connectionId = UUID()
        
        BlazeLogger.debug("New connection: \(connectionId)")
        
        // Start connection
        await serverConnection.start()
        
        // Wait for connection to be ready
        guard await serverConnection.waitForReady() else {
            BlazeLogger.error("Connection \(connectionId) failed to establish")
            serverConnection.cancel()
            return
        }
        
        #if canImport(Network)
        // On Apple platforms, extract NWConnection for SecureConnection
        guard let nwConnection = serverConnection.getNWConnection() else {
            BlazeLogger.error("Connection \(connectionId): Unable to get NWConnection")
            serverConnection.cancel()
            return
        }
        
        // Create secure connection wrapper
        let secureConnection = SecureConnection(
            connection: nwConnection,
            nodeId: connectionId,
            database: databaseName,
            authToken: nil  // Server doesn't need auth token
        )
        
        // Perform server-side handshake
        do {
            try await secureConnection.performServerHandshake(
                expectedAuthToken: authToken,
                sharedSecret: sharedSecret,
                serverDatabase: databaseName
            )
            
            connections[connectionId] = secureConnection
            
            // Create relay for this connection
            let relay = TCPRelay(connection: secureConnection)
            
            // Create sync engine (server role - has priority)
            let engine = BlazeSyncEngine(
                localDB: database,
                relay: relay,
                role: .server  // Server has priority
            )
            
            try await engine.start()
            syncEngines[connectionId] = engine
            
            BlazeLogger.info("Connection \(connectionId) established and syncing")
            
        } catch {
            BlazeLogger.error("Handshake failed for \(connectionId)", error: error)
            serverConnection.cancel()
        }
        #else
        // On Linux/headless platforms, SecureConnection is not available
        BlazeLogger.warn("Connection \(connectionId): SecureConnection not available on this platform")
        serverConnection.cancel()
        #endif
    }
    
    /// Get active connection count
    public func getConnectionCount() -> Int {
        return connections.count
    }
    
    /// Get all connection IDs
    public func getConnectionIds() -> [UUID] {
        return Array(connections.keys)
    }
}

#endif // !BLAZEDB_LINUX_CORE
