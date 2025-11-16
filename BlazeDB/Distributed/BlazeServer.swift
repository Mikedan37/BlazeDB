//
//  BlazeServer.swift
//  BlazeDB Distributed
//
//  Server for accepting remote database connections
//

import Foundation
import Network

/// Server that accepts remote BlazeDB connections
public actor BlazeServer {
    private let port: UInt16
    private let database: BlazeDBClient
    private let databaseName: String
    private let authToken: String?
    private let sharedSecret: String?
    private var listener: NWListener?
    private var isRunning = false
    private var connections: [UUID: SecureConnection] = [:]
    private var syncEngines: [UUID: BlazeSyncEngine] = [:]
    
    public init(
        port: UInt16 = 8080,
        database: BlazeDBClient,
        databaseName: String,
        authToken: String? = nil,
        sharedSecret: String? = nil
    ) {
        self.port = port
        self.database = database
        self.databaseName = databaseName
        self.authToken = authToken
        self.sharedSecret = sharedSecret
    }
    
    /// Start listening for connections
    public func start() async throws {
        guard !isRunning else { return }
        
        // Create TCP listener
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        // Handle new connections
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            Task {
                await self.handleConnection(connection)
            }
        }
        
        // Start listening
        listener.start(queue: .global())
        self.listener = listener
        self.isRunning = true
        
        BlazeLogger.info("BlazeServer listening on port \(port) (database: \(databaseName), auth: \(authToken != nil ? "enabled" : "disabled"))")
    }
    
    /// Stop listening
    public func stop() async {
        guard isRunning else { return }
        
        listener?.cancel()
        listener = nil
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
    private func handleConnection(_ connection: NWConnection) async {
        let connectionId = UUID()
        
        BlazeLogger.debug("New connection: \(connectionId)")
        
        // Start connection
        connection.start(queue: .global())
        
        // Wait for connection to be ready
        let state = await connection.state
        guard case .ready = state else {
            BlazeLogger.error("Connection \(connectionId) failed to establish")
            return
        }
        
        // Create secure connection wrapper
        let secureConnection = SecureConnection(
            connection: connection,
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
            connection.cancel()
        }
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
