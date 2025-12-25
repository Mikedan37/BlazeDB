//
//  TCPRelay.swift
//  BlazeDB Distributed
//
//  Relay for remote synchronization over secure TCP connection (raw TCP, not WebSocket)
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// Relay for remote synchronization using secure TCP connection (raw TCP, not WebSocket)
public actor TCPRelay: BlazeSyncRelay {
    private let connection: SecureConnection
    private var operationHandler: (([BlazeOperation]) async -> Void)?
    private var isConnected = false
    private var receiveTask: Task<Void, Error>?
    
    // Memory pooling: Reuse buffers instead of allocating
    nonisolated(unsafe) private static var encodeBufferPool: [Data] = []
    private static let poolLock = NSLock()
    private static let maxPoolSize = 10
    
    // Smart caching: Cache encoded operations by hash
    nonisolated(unsafe) private static var encodedCache: [UInt64: Data] = [:]
    nonisolated(unsafe) internal static var cacheHits: Int = 0
    nonisolated(unsafe) internal static var cacheMisses: Int = 0
    internal static let cacheLock = NSLock()
    private static let maxCacheSize = 10000  // Cache up to 10K operations
    
    public init(connection: SecureConnection) {
        self.connection = connection
    }
    
    // MARK: - BlazeSyncRelay Protocol
    
    public func connect() async throws {
        isConnected = true
        
        // Start receiving operations
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let data = try await connection.receive()
                    let operations = try await decodeOperations(data)
                    await operationHandler?(operations)
                } catch {
                    BlazeLogger.error("TCPRelay receive error", error: error)
                    break
                }
            }
        }
        
        BlazeLogger.info("TCPRelay connected and receiving operations")
    }
    
    public func disconnect() async {
        isConnected = false
        receiveTask?.cancel()
        BlazeLogger.info("TCPRelay disconnected")
    }
    
    public func exchangeSyncState() async throws -> SyncState {
        // Send sync state request
        let request = SyncStateRequest()
        let data = try await encodeSyncStateRequest(request)
        try await connection.send(data)
        
        // Receive sync state
        let responseData = try await connection.receive()
        let state = try await decodeSyncState(responseData)
        
        return state
    }
    
    public func pullOperations(since timestamp: LamportTimestamp) async throws -> [BlazeOperation] {
        // Send pull request
        let request = PullRequest(since: timestamp)
        let data = try await encodePullRequest(request)
        try await connection.send(data)
        
        // Receive operations
        let responseData = try await connection.receive()
        let operations = try await decodeOperations(responseData)
        
        return operations
    }
    
    public func pushOperations(_ ops: [BlazeOperation]) async throws {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        guard !ops.isEmpty else { return }
        
        // Encode operations (with batching and compression!)
        let data = try await encodeOperations(ops)
        
        // Send encrypted (pipelined - don't wait for ACK!)
        try await connection.send(data)
        
        let sizeKB = Double(data.count) / 1024.0
        BlazeLogger.debug("TCPRelay pushed \(ops.count) operations (\(String(format: "%.2f", sizeKB)) KB)")
    }
    
    public func subscribe(to collections: [String]) async throws {
        // Send subscription request
        let request = SubscribeRequest(collections: collections)
        let data = try await encodeSubscribeRequest(request)
        try await connection.send(data)
        
        BlazeLogger.debug("TCPRelay subscribed to: \(collections)")
    }
    
    public nonisolated func onOperationReceived(_ handler: @escaping ([BlazeOperation]) async -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            await self.setOperationHandler(handler)
        }
    }
    
    private func setOperationHandler(_ handler: @escaping ([BlazeOperation]) async -> Void) {
        self.operationHandler = handler
    }
    
    // MARK: - Memory Pooling
    
    // Memory pooling: Get reusable buffer
    internal func getPooledBuffer(capacity: Int) -> Data {
        Self.poolLock.lock()
        defer { Self.poolLock.unlock() }
        
        // Find any available buffer (we'll resize if needed)
        if !Self.encodeBufferPool.isEmpty {
            var buffer = Self.encodeBufferPool.removeFirst()
            buffer.removeAll(keepingCapacity: true)  // Clear but keep capacity
            if buffer.count < capacity {
                buffer.reserveCapacity(capacity)  // Expand if needed
            }
            return buffer
        }
        
        // No buffer available, create new one
        var newBuffer = Data()
        newBuffer.reserveCapacity(capacity)
        return newBuffer
    }
    
    // Memory pooling: Return buffer to pool
    internal func returnPooledBuffer(_ buffer: Data) {
        Self.poolLock.lock()
        defer { Self.poolLock.unlock() }
        
        // Add to pool if not full
        if Self.encodeBufferPool.count < Self.maxPoolSize {
            Self.encodeBufferPool.append(buffer)
        }
        // Otherwise, let it deallocate (pool is full)
    }
    
    // MARK: - Smart Caching
    
    // Smart caching: Get cached encoded operation
    nonisolated internal static func getCachedOperation(_ op: BlazeOperation) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let hash = operationHash(op)
        return encodedCache[hash]
    }
    
    // Smart caching: Cache encoded operation
    nonisolated internal static func cacheEncodedOperation(_ op: BlazeOperation, _ encoded: Data) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Evict oldest if cache is full (simple FIFO)
        if encodedCache.count >= maxCacheSize {
            // Remove 10% of oldest entries
            let keysToRemove = Array(encodedCache.keys.prefix(maxCacheSize / 10))
            for key in keysToRemove {
                encodedCache.removeValue(forKey: key)
            }
        }
        
        let hash = operationHash(op)
        encodedCache[hash] = encoded
    }
    
    // Helper methods for async-safe cache hit/miss tracking
    nonisolated internal static func incrementCacheHits() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cacheHits += 1
    }
    
    nonisolated internal static func incrementCacheMisses() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cacheMisses += 1
    }
    
    // Smart caching: Hash operation for cache key
    private static func operationHash(_ op: BlazeOperation) -> UInt64 {
        // Fast hash of operation (ID + type + recordId + changes hash)
        var hasher = Hasher()
        hasher.combine(op.id)
        hasher.combine(op.type)
        hasher.combine(op.recordId)
        hasher.combine(op.collectionName)
        // Hash changes (simple hash of keys + values)
        for (key, value) in op.changes.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(String(describing: value))  // Simple hash of value
        }
        return UInt64(truncatingIfNeeded: hasher.finalize())
    }
    
    /// Get cache statistics (for monitoring)
    public static func getCacheStats() -> (hits: Int, misses: Int, size: Int, hitRate: Double) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let total = cacheHits + cacheMisses
        let hitRate = total > 0 ? Double(cacheHits) / Double(total) : 0.0
        
        return (cacheHits, cacheMisses, encodedCache.count, hitRate)
    }
}


#endif // !BLAZEDB_LINUX_CORE
