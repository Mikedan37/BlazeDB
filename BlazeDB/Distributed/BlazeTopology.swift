//
//  BlazeTopology.swift
//  BlazeDB Distributed
//
//  Multi-database coordinator for local and remote sync
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

/// Coordinates synchronization between multiple databases (local and remote)
public actor BlazeTopology {
    internal var nodes: [UUID: DBNode] = [:]
    internal var connections: [Connection] = []
    private let topologyId: UUID
    
    public struct DBNode {
        public let nodeId: UUID
        public let database: BlazeDBClient
        public let name: String
        public var syncMode: SyncMode
        public var remoteNode: RemoteNode?
        public var role: SyncRole  // SERVER/CLIENT ROLE
        
        public var path: String {
            // Access fileURL through internal property
            return database.fileURL.path
        }
        
        public init(nodeId: UUID, database: BlazeDBClient, name: String, syncMode: SyncMode, remoteNode: RemoteNode?, role: SyncRole) {
            self.nodeId = nodeId
            self.database = database
            self.name = name
            self.syncMode = syncMode
            self.remoteNode = remoteNode
            self.role = role
        }
    }
    
    public enum SyncMode {
        case localOnly
        case localAndRemote
        case remoteOnly
    }
    
    public struct Connection {
        public let from: UUID
        public let to: UUID
        public let type: ConnectionType
        public let relay: BlazeSyncRelay
        
        public init(from: UUID, to: UUID, type: ConnectionType, relay: BlazeSyncRelay) {
            self.from = from
            self.to = to
            self.type = type
            self.relay = relay
        }
    }
    
    public enum ConnectionType {
        case local      // Same app (in-memory queue)
        case crossApp   // Different apps (Unix Domain Socket)
        case remote     // Different device (TCP)
    }
    
    public init(topologyId: UUID = UUID()) {
        self.topologyId = topologyId
    }
    
    // MARK: - Node Registration
    
    /// Register a database in the topology
    /// - Parameters:
    ///   - db: The database to register
    ///   - name: Human-readable name
    ///   - syncMode: Sync mode (localOnly, localAndRemote, remoteOnly)
    ///   - role: Server (has priority) or Client (defers to server) - default: .client
    /// - Returns: Node ID for this database
    public func register(
        db: BlazeDBClient,
        name: String,
        syncMode: SyncMode = .localOnly,
        role: SyncRole = .client  // DEFAULT: Client (opt-in server mode)
    ) async throws -> UUID {
        let nodeId = UUID()
        
        let node = DBNode(
            nodeId: nodeId,
            database: db,
            name: name,
            syncMode: syncMode,
            remoteNode: nil,
            role: role
        )
        
        nodes[nodeId] = node
        
        let roleStr = role == .server ? "SERVER" : "CLIENT"
        BlazeLogger.info("Registered database: \(name) (node: \(nodeId), role: \(roleStr))")
        
        return nodeId
    }
    
    // MARK: - Local Connections (Same Device)
    
    /// Connect two databases on the same device
    public func connectLocal(
        from: UUID,
        to: UUID,
        mode: ConnectionMode = .bidirectional
    ) async throws {
        guard let fromNode = nodes[from],
              let toNode = nodes[to] else {
            throw TopologyError.nodeNotFound
        }
        
        // Create in-memory relay for local sync
        let relay = InMemoryRelay(
            fromNodeId: from,
            toNodeId: to,
            mode: mode
        )
        
        let connection = Connection(
            from: from,
            to: to,
            type: .local,
            relay: relay
        )
        
        connections.append(connection)
        
        // Start sync engines for both databases (with their roles)
        let fromEngine = BlazeSyncEngine(localDB: fromNode.database, relay: relay, role: fromNode.role)
        let toEngine = BlazeSyncEngine(localDB: toNode.database, relay: relay, role: toNode.role)
        
        // Start engines (they're actors, so we await)
        try await fromEngine.start()
        try await toEngine.start()
        
        BlazeLogger.info("Connected local: \(fromNode.name) ←→ \(toNode.name) (in-memory queue, <1ms latency)")
    }
    
    public enum ConnectionMode {
        case bidirectional
        case readOnly      // Target can only read from source
        case writeOnly     // Target can only write to source
    }
    
    // MARK: - Remote Connections (Different Devices)
    
    /// Connect a database to a remote server
    public func connectRemote(
        nodeId: UUID,
        remote: RemoteNode,
        policy: SyncPolicy
    ) async throws {
        guard let node = nodes[nodeId] else {
            throw TopologyError.nodeNotFound
        }
        
        // Create secure connection (DH handshake + E2E)
        let secureConnection = try await SecureConnection.create(
            to: remote,
            database: node.name,
            nodeId: nodeId
        )
        
        // Create TCP relay (raw TCP, not WebSocket)
        let relay = TCPRelay(connection: secureConnection)
        
        let connection = Connection(
            from: nodeId,
            to: remote.nodeId,
            type: .remote,
            relay: relay
        )
        
        connections.append(connection)
        
        // Update node with remote info
        var updatedNode = node
        updatedNode.remoteNode = remote
        nodes[nodeId] = updatedNode
        
        // Start sync engine (with node's role)
        let engine = BlazeSyncEngine(localDB: node.database, relay: relay, role: node.role)
        try await engine.start()
        
        BlazeLogger.info("Connected remote: \(node.name) → \(remote.host):\(remote.port) (TCP+TLS, E2E, ~5ms latency)")
    }
    
    // MARK: - Cross-App Sync (Unix Domain Sockets)
    
    /// Connect two databases in different apps using Unix Domain Sockets (same device, different apps)
    /// Uses BlazeBinary encoding for maximum performance (~0.3-0.5ms latency)
    public func connectCrossApp(
        from fromNodeId: UUID,
        to toNodeId: UUID,
        socketPath: String,
        mode: ConnectionMode = .bidirectional
    ) async throws {
        guard let fromNode = nodes[fromNodeId] else {
            throw TopologyError.nodeNotFound
        }
        guard let toNode = nodes[toNodeId] else {
            throw TopologyError.nodeNotFound
        }
        
        // Create two relay instances (one for each direction)
        // Server side (listens)
        let serverRelay = UnixDomainSocketRelay(
            socketPath: socketPath,
            fromNodeId: fromNodeId,
            toNodeId: toNodeId,
            mode: mode
        )
        
        // Client side (connects)
        let clientRelay = UnixDomainSocketRelay(
            socketPath: socketPath,
            fromNodeId: toNodeId,
            toNodeId: fromNodeId,
            mode: mode
        )
        
        // Start listening on server side
        try await serverRelay.startListening()
        
        // Connect on client side
        try await clientRelay.connect()
        
        // Create sync engines (each uses its own relay)
        let fromEngine = BlazeSyncEngine(
            localDB: fromNode.database,
            relay: serverRelay,
            nodeId: fromNodeId,
            role: fromNode.role
        )
        
        let toEngine = BlazeSyncEngine(
            localDB: toNode.database,
            relay: clientRelay,
            nodeId: toNodeId,
            role: toNode.role
        )
        
        // Start engines
        try await fromEngine.start()
        try await toEngine.start()
        
        // Store connections (both directions)
        connections.append(Connection(
            from: fromNodeId,
            to: toNodeId,
            type: .crossApp,
            relay: serverRelay
        ))
        connections.append(Connection(
            from: toNodeId,
            to: fromNodeId,
            type: .crossApp,
            relay: clientRelay
        ))
        
        BlazeLogger.info("Connected cross-app: \(fromNode.name) ←→ \(toNode.name) (Unix Domain Socket, BlazeBinary, <0.5ms latency)")
    }
    
    // MARK: - Cross-App Sync (App Groups - Legacy)
    
    /// Enable cross-app sync for a database (same device, different apps) - Legacy App Groups method
    public func enableCrossAppSync(
        nodeId: UUID,
        appGroup: String,
        exportPolicy: ExportPolicy
    ) async throws {
        guard let node = nodes[nodeId] else {
            throw TopologyError.nodeNotFound
        }
        
        // Create cross-app sync coordinator
        let coordinator = try CrossAppSyncCoordinator(
            database: node.database,
            appGroup: appGroup,
            exportPolicy: exportPolicy
        )
        
        try await coordinator.enable()
        
        BlazeLogger.info("Enabled cross-app sync (App Groups): \(node.name) (appGroup: \(appGroup), collections: \(exportPolicy.collections))")
    }
    
    // MARK: - Query Topology
    
    /// Get all nodes
    public func getNodes() -> [DBNode] {
        return Array(nodes.values)
    }
    
    /// Get connections for a node
    public func getConnections(for nodeId: UUID) -> [Connection] {
        return connections.filter { $0.from == nodeId || $0.to == nodeId }
    }
    
    /// Get topology graph
    public func getTopologyGraph() -> TopologyGraph {
        return TopologyGraph(
            nodes: Array(nodes.values),
            connections: connections
        )
    }
}

// MARK: - Remote Node

public struct RemoteNode {
    let nodeId: UUID
    let host: String
    let port: UInt16
    let database: String
    let useTLS: Bool
    let authToken: String?  // SECURITY: Authentication token
    
    public init(
        host: String,
        port: UInt16 = 8080,
        database: String,
        useTLS: Bool = true,
        authToken: String? = nil  // SECURITY: Optional auth token
    ) {
        self.nodeId = UUID()  // Will be set during handshake
        self.host = host
        self.port = port
        self.database = database
        self.useTLS = useTLS
        self.authToken = authToken
    }
}

// MARK: - Export Policy

public struct ExportPolicy {
    let collections: [String]
    let fields: [String]?  // nil = all, [] = none
    let filter: QueryFilter?
    let readOnly: Bool
    
    public init(
        collections: [String],
        fields: [String]? = nil,
        filter: QueryFilter? = nil,
        readOnly: Bool = true
    ) {
        self.collections = collections
        self.fields = fields
        self.filter = filter
        self.readOnly = readOnly
    }
}

public enum QueryFilter {
    case whereField(String, equals: BlazeDocumentField)
    case whereField(String, notEquals: BlazeDocumentField)
    case whereField(String, greaterThan: BlazeDocumentField)
    case whereField(String, lessThan: BlazeDocumentField)
    case and([QueryFilter])
    case or([QueryFilter])
}

// MARK: - Sync Policy

public struct SyncPolicy {
    let collections: [String]?
    let teams: [UUID]?
    let excludeFields: [String]
    let respectRLS: Bool
    let encryptionMode: EncryptionMode
    
    public enum EncryptionMode {
        case e2eOnly      // Server blind (max privacy)
        case smartProxy   // Server can read (functionality)
    }
    
    public init(
        collections: [String]? = nil,
        teams: [UUID]? = nil,
        excludeFields: [String] = [],
        respectRLS: Bool = true,
        encryptionMode: EncryptionMode = .e2eOnly
    ) {
        self.collections = collections
        self.teams = teams
        self.excludeFields = excludeFields
        self.respectRLS = respectRLS
        self.encryptionMode = encryptionMode
    }
}

// MARK: - Topology Graph

public struct TopologyGraph {
    let nodes: [BlazeTopology.DBNode]
    let connections: [BlazeTopology.Connection]
    
    public func visualize() -> String {
        var result = "BlazeDB Topology:\n"
        result += "═══════════════════\n\n"
        
        for node in nodes {
            result += "📦 \(node.name) (node: \(node.nodeId))\n"
            
            let nodeConnections = connections.filter { $0.from == node.nodeId || $0.to == node.nodeId }
            for conn in nodeConnections {
                let otherNodeId = conn.from == node.nodeId ? conn.to : conn.from
                if let otherNode = nodes.first(where: { $0.nodeId == otherNodeId }) {
                    let type = conn.type == .local ? "local" : "remote"
                    result += "   └─→ \(otherNode.name) (\(type))\n"
                }
            }
            
            result += "\n"
        }
        
        return result
    }
}

// MARK: - Management Helpers

extension BlazeTopology {
    /// Disconnect all recorded connections in this topology.
    ///
    /// Note: The current implementation only clears the in-memory connection
    /// metadata. Individual `BlazeSyncEngine` instances should be stopped by
    /// the caller if they are being tracked externally.
    public func disconnectAll() async {
        connections.removeAll()
        BlazeLogger.info("Disconnected all topology connections")
    }
}

// MARK: - Errors

public enum TopologyError: Error, LocalizedError {
    case nodeNotFound
    case connectionFailed(String)
    case invalidPolicy
    case handshakeFailed
    
    public var errorDescription: String? {
        switch self {
        case .nodeNotFound:
            return "Database node not found in topology"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .invalidPolicy:
            return "Invalid sync policy"
        case .handshakeFailed:
            return "Handshake failed"
        }
    }
}


#endif // !BLAZEDB_LINUX_CORE
