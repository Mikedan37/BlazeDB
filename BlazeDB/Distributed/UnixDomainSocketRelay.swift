//
//  UnixDomainSocketRelay.swift
//  BlazeDB Distributed
//
//  Unix Domain Socket relay for cross-app synchronization (same device, different apps)
//  Uses BlazeBinary encoding for maximum performance
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if canImport(Network)
import Network

/// Unix Domain Socket relay for cross-app sync (same device, different apps)
/// Uses BlazeBinary encoding (5-10x faster than JSON!)
public actor UnixDomainSocketRelay: BlazeSyncRelay {
    private let socketPath: String
    private let fromNodeId: UUID
    private let toNodeId: UUID
    private let mode: BlazeTopology.ConnectionMode
    private var connection: NWConnection?
    private var listener: NWListener?
    private var isConnected = false
    private var operationHandler: (([BlazeOperation]) async -> Void)?
    private var receiveTask: Task<Void, Never>?
    
    // Sync state tracking (for incremental sync)
    private var lastSyncedTimestamps: [UUID: LamportTimestamp] = [:]
    private var messageQueue: [BlazeOperation] = []
    
    public init(
        socketPath: String,
        fromNodeId: UUID,
        toNodeId: UUID,
        mode: BlazeTopology.ConnectionMode
    ) {
        self.socketPath = socketPath
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.mode = mode
    }
    
    // MARK: - BlazeSyncRelay Protocol
    
    public func connect() async throws {
        // Create Unix Domain Socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)
        
        // Create connection parameters
        let parameters = NWParameters()
        parameters.allowLocalEndpointReuse = true
        
        // Create connection
        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn
        
        // Set state update handler
        conn.stateUpdateHandler = { [weak self] state in
            Task {
                guard let self = self else { return }
                switch state {
                case .ready:
                    await self.handleConnectionReady()
                case .failed(let error):
                    BlazeLogger.error("UnixDomainSocket connection failed", error: error)
                default:
                    break
                }
            }
        }
        
        // Start connection
        conn.start(queue: .global())
        
        // Wait for connection (with timeout and retries)
        try await waitForConnectionWithRetries(timeout: 5.0, maxRetries: 10)
        
        BlazeLogger.info("UnixDomainSocketRelay connected: \(fromNodeId) → \(toNodeId) (path: \(socketPath))")
    }
    
    public func disconnect() async {
        isConnected = false
        receiveTask?.cancel()
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        messageQueue.removeAll()
        BlazeLogger.info("UnixDomainSocketRelay disconnected: \(fromNodeId) → \(toNodeId)")
    }
    
    public func exchangeSyncState() async throws -> SyncState {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        // Get last synced timestamp for requesting node
        let lastSynced = lastSyncedTimestamps[toNodeId] ?? LamportTimestamp(counter: 0, nodeId: toNodeId)
        
        // Get max timestamp from queue
        let maxTimestamp = messageQueue.map(\.timestamp).max() ?? lastSynced
        
        return SyncState(
            nodeId: fromNodeId,
            lastSyncedTimestamp: maxTimestamp,
            operationCount: messageQueue.count,
            collections: []
        )
    }
    
    public func pullOperations(since timestamp: LamportTimestamp) async throws -> [BlazeOperation] {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        // Send pull request (BlazeBinary encoded)
        let request = PullRequest(since: timestamp)
        let requestData = try encodePullRequest(request)
        try await sendData(requestData)
        
        // Receive operations (BlazeBinary encoded)
        let responseData = try await receiveData()
        let operations = try decodeOperations(responseData)
        
        return operations
    }
    
    public func pushOperations(_ ops: [BlazeOperation]) async throws {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        guard !ops.isEmpty else { return }
        
        // Update sync state
        let maxTimestamp = ops.map(\.timestamp).max() ?? lastSyncedTimestamps[toNodeId] ?? LamportTimestamp(counter: 0, nodeId: toNodeId)
        lastSyncedTimestamps[toNodeId] = maxTimestamp
        
        // Encode operations using BlazeBinary (fast!)
        let data = try encodeOperations(ops)
        
        // Send over Unix Domain Socket
        try await sendData(data)
        
        let sizeKB = Double(data.count) / 1024.0
        BlazeLogger.debug("UnixDomainSocketRelay pushed \(ops.count) operations (\(String(format: "%.2f", sizeKB)) KB)")
    }
    
    public func subscribe(to collections: [String]) async throws {
        // Send subscription request (BlazeBinary encoded)
        let request = SubscribeRequest(collections: collections)
        let data = try encodeSubscribeRequest(request)
        try await sendData(data)
        
        BlazeLogger.debug("UnixDomainSocketRelay subscribed to: \(collections)")
    }
    
    public func onOperationReceived(_ handler: @escaping ([BlazeOperation]) async -> Void) {
        self.operationHandler = handler
    }
    
    // MARK: - Server Side (Listener)
    
    /// Start listening for connections (server side)
    public func startListening() async throws {
        // Ensure socket directory exists
        let socketURL = URL(fileURLWithPath: socketPath)
        let socketDir = socketURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: socketDir.path) {
            try FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)
        }
        
        // Remove existing socket file if it exists
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        
        // Create Unix Domain Socket endpoint
        let endpoint = NWEndpoint.unix(path: socketPath)
        
        // Create listener parameters
        let parameters = NWParameters()
        parameters.allowLocalEndpointReuse = true
        
        // Create listener
        let listener = try NWListener(using: parameters, on: endpoint)
        self.listener = listener
        
        // Handle new connections
        listener.newConnectionHandler = { [weak self] newConnection in
            Task {
                await self?.handleNewConnection(newConnection)
            }
        }
        
        // Start listening
        listener.start(queue: .global())
        
        BlazeLogger.info("UnixDomainSocketRelay listening on: \(socketPath)")
    }
    
    // MARK: - Private Helpers
    
    private func handleConnectionReady() async {
        // Start receiving operations
        receiveTask = Task {
            while !Task.isCancelled && isConnected {
                do {
                    let data = try await receiveData()
                    let operations = try decodeOperations(data)
                    await operationHandler?(operations)
                } catch {
                    BlazeLogger.error("UnixDomainSocketRelay receive error", error: error)
                    break
                }
            }
        }
    }
    
    private func handleNewConnection(_ newConnection: NWConnection) async {
        newConnection.start(queue: .global())
        
        // Wait for ready state
        let state = await newConnection.state
        guard case .ready = state else {
            BlazeLogger.error("UnixDomainSocketRelay new connection failed")
            return
        }
        
        // Store connection
        self.connection = newConnection
        isConnected = true
        
        // Start receiving
        await handleConnectionReady()
        
        BlazeLogger.info("UnixDomainSocketRelay accepted new connection")
    }
    
    private func waitForConnectionWithRetries(timeout: TimeInterval, maxRetries: Int) async throws {
        let startTime = Date()
        
        while !isConnected && Date().timeIntervalSince(startTime) < timeout {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms between checks
            
            // Check connection state
            if let conn = connection {
                let state = await conn.state
                if case .ready = state {
                    // Connection ready - handleConnectionReady will set isConnected
                    break
                } else if case .failed = state {
                    // Connection failed - wait a bit more for server to be ready
                    continue
                }
            }
        }
        
        guard isConnected else {
            throw RelayError.notConnected
        }
    }
    
    // MARK: - BlazeBinary Encoding/Decoding
    
    private func encodeOperations(_ ops: [BlazeOperation]) throws -> Data {
        var data = Data()
        data.reserveCapacity(ops.count * 200) // Pre-allocate
        
        // Write count (4 bytes)
        var count = UInt32(ops.count).bigEndian
        data.append(Data(bytes: &count, count: 4))
        
        // Write each operation (BlazeBinary encoded)
        for op in ops {
            let opData = try BlazeOperation.encodeToBlazeBinary(op)
            var opLength = UInt32(opData.count).bigEndian
            data.append(Data(bytes: &opLength, count: 4))
            data.append(opData)
        }
        
        return data
    }
    
    private func decodeOperations(_ data: Data) throws -> [BlazeOperation] {
        var offset = 0
        
        // Read count (4 bytes)
        guard offset + 4 <= data.count else { throw RelayError.invalidData }
        let count = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        
        var operations: [BlazeOperation] = []
        
        // Read each operation
        for _ in 0..<count {
            // Read operation length (4 bytes)
            guard offset + 4 <= data.count else { break }
            let opLength = Int(data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offset += 4
            
            // Read operation data
            guard offset + opLength <= data.count else { break }
            let opData = data[offset..<offset+opLength]
            offset += opLength
            
            // Decode operation (BlazeBinary)
            let op = try BlazeOperation.decodeFromBlazeBinary(opData)
            operations.append(op)
        }
        
        return operations
    }
    
    private func encodePullRequest(_ request: PullRequest) throws -> Data {
        var data = Data()
        data.reserveCapacity(50)
        
        // Type: 0x01 = PullRequest
        data.append(0x01)
        
        // Timestamp (8 bytes counter + 16 bytes nodeId)
        var counter = request.since.counter.bigEndian
        data.append(Data(bytes: &counter, count: 8))
        data.append(request.since.nodeId.binaryData)
        
        return data
    }
    
    private func encodeSubscribeRequest(_ request: SubscribeRequest) throws -> Data {
        var data = Data()
        data.reserveCapacity(100)
        
        // Type: 0x02 = SubscribeRequest
        data.append(0x02)
        
        // Collection count (1 byte)
        data.append(UInt8(request.collections.count))
        
        // Each collection (1 byte length + UTF-8)
        for collection in request.collections {
            guard let bytes = collection.data(using: .utf8) else {
                throw BlazeDBError.invalidData(reason: "Failed to encode collection name: \(collection)")
            }
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        
        return data
    }
    
    // MARK: - Network I/O
    
    private func sendData(_ data: Data) async throws {
        guard let connection = connection else {
            throw RelayError.notConnected
        }
        
        // Send length prefix (4 bytes) + data
        var length = UInt32(data.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: lengthData + data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }
    
    private func receiveData() async throws -> Data {
        guard let connection = connection else {
            throw RelayError.notConnected
        }
        
        // Receive length prefix (4 bytes)
        let lengthData = try await receiveExactBytes(4)
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        
        // Receive actual data
        let data = try await receiveExactBytes(Int(length))
        return data
    }
    
    private func receiveExactBytes(_ count: Int) async throws -> Data {
        guard let connection = connection else {
            throw RelayError.notConnected
        }
        
        var received = Data()
        received.reserveCapacity(count)
        
        while received.count < count {
            let chunk = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: count - received.count, maximumLength: count - received.count) { content, context, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let content = content {
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(throwing: RelayError.invalidData)
                    }
                }
            }
            received.append(chunk)
        }
        
        return received
    }
}

// MARK: - Request Types

private struct PullRequest {
    let since: LamportTimestamp
}

private struct SubscribeRequest {
    let collections: [String]
}

#endif // canImport(Network)
#endif // !BLAZEDB_LINUX_CORE

