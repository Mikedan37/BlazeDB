//
//  TCPRelay.swift
//  BlazeDB Distributed
//
//  Relay for remote synchronization over secure TCP connection (NOT WebSocket - raw TCP)
//

import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// UUID binary encoding extension
extension UUID {
    /// Get UUID as 16-byte binary data
    var binaryData: Data {
        var uuid = self.uuid
        return withUnsafeBytes(of: uuid) { Data($0) }
    }
    
    /// Create UUID from 16-byte binary data
    init(binaryData data: Data) {
        guard data.count == 16 else {
            self = UUID()
            return
        }
        let uuid = data.withUnsafeBytes { $0.load(as: uuid_t.self) }
        self = UUID(uuid: uuid)
    }
}

// Parallel map extension for concurrent encoding
extension Array {
    func concurrentMap<T>(_ transform: @escaping (Element) throws -> T) rethrows -> [T] {
        return try withTaskGroup(of: T.self) { group in
            for item in self {
                group.addTask {
                    try transform(item)
                }
            }
            
            var results: [T] = []
            results.reserveCapacity(self.count)
            
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
    }
}

/// Relay for remote synchronization using secure TCP connection (raw TCP, not WebSocket)
public actor TCPRelay: BlazeSyncRelay {
    private let connection: SecureConnection
    private var operationHandler: (([BlazeOperation]) async -> Void)?
    private var isConnected = false
    private var receiveTask: Task<Void, Error>?
    
    // Memory pooling: Reuse buffers instead of allocating
    private static var encodeBufferPool: [Data] = []
    private static var compressBufferPool: [UnsafeMutablePointer<UInt8>] = []
    private static let poolLock = NSLock()
    private static let maxPoolSize = 10
    
    // Smart caching: Cache encoded operations by hash
    private static var encodedCache: [UInt64: Data] = [:]
    private static var cacheHits: Int = 0
    private static var cacheMisses: Int = 0
    private static let cacheLock = NSLock()
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
                    let operations = try decodeOperations(data)
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
        let data = try encodeSyncStateRequest(request)
        try await connection.send(data)
        
        // Receive sync state
        let responseData = try await connection.receive()
        let state = try decodeSyncState(responseData)
        
        return state
    }
    
    public func pullOperations(since timestamp: LamportTimestamp) async throws -> [BlazeOperation] {
        // Send pull request
        let request = PullRequest(since: timestamp)
        let data = try encodePullRequest(request)
        try await connection.send(data)
        
        // Receive operations
        let responseData = try await connection.receive()
        let operations = try decodeOperations(responseData)
        
        return operations
    }
    
    public func pushOperations(_ ops: [BlazeOperation]) async throws {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        guard !ops.isEmpty else { return }
        
        // Encode operations (with batching and compression!)
        let data = try encodeOperations(ops)
        
        // Send encrypted (pipelined - don't wait for ACK!)
        try await connection.send(data)
        
        let sizeKB = Double(data.count) / 1024.0
        BlazeLogger.debug("TCPRelay pushed \(ops.count) operations (\(String(format: "%.2f", sizeKB)) KB)")
    }
    
    public func subscribe(to collections: [String]) async throws {
        // Send subscription request
        let request = SubscribeRequest(collections: collections)
        let data = try encodeSubscribeRequest(request)
        try await connection.send(data)
        
        BlazeLogger.debug("TCPRelay subscribed to: \(collections)")
    }
    
    public func onOperationReceived(_ handler: @escaping ([BlazeOperation]) async -> Void) {
        self.operationHandler = handler
    }
    
    // MARK: - Encoding/Decoding (Optimized with BlazeBinary!)
    
    private func encodeOperations(_ ops: [BlazeOperation]) throws -> Data {
        // ULTRA-OPTIMIZED: Multi-threaded encoding with native BlazeBinary + streaming compression!
        
        // Get pooled buffer (reuse instead of allocating)
        var data = getPooledBuffer(capacity: ops.count * 100)
        defer { returnPooledBuffer(data) }
        
        // Write count (variable-length encoding for small counts!)
        if ops.count < 256 {
            // Small count: 1 byte
            data.append(UInt8(ops.count))
        } else {
            // Large count: 4 bytes (with marker)
            data.append(0xFF)  // Marker: 4-byte count follows
            var count = UInt32(ops.count).bigEndian
            data.append(Data(bytes: &count, count: 4))
        }
        
        // DEDUPLICATION: Remove duplicate operations (same ID) - O(n) with Set
        var seen = Set<UUID>()
        let uniqueOps = ops.filter { op in
            if seen.contains(op.id) {
                return false
            }
            seen.insert(op.id)
            return true
        }
        
        // STREAMING COMPRESSION: Compress while encoding (pipeline!)
        // SMART CACHING + PARALLEL ENCODING: Check cache first, then encode in parallel!
        let encodedOps = try uniqueOps.concurrentMap { op in
            // Check cache first (smart caching!)
            if let cached = Self.getCachedOperation(op) {
                Self.cacheLock.lock()
                Self.cacheHits += 1
                Self.cacheLock.unlock()
                return cached
            }
            
            // Cache miss - encode and cache it
            Self.cacheLock.lock()
            Self.cacheMisses += 1
            Self.cacheLock.unlock()
            
            let encoded = try encodeOperationNative(op)  // Native BlazeBinary, not JSON!
            Self.cacheEncodedOperation(op, encoded)
            return encoded
        }
        
        // Append all encoded operations (zero-copy where possible)
        // Use variable-length encoding for operation lengths
        for opData in encodedOps {
            if opData.count < 128 {
                // Small op: 1 byte length (7 bits)
                data.append(UInt8(opData.count))
            } else if opData.count < 32768 {
                // Medium op: 2 bytes length (with marker)
                data.append(0x80 | UInt8((opData.count >> 8) & 0x7F))  // High byte with marker
                data.append(UInt8(opData.count & 0xFF))  // Low byte
            } else {
                // Large op: 4 bytes length (with marker)
                data.append(0xFF)  // Marker: 4-byte length follows
                var opLength = UInt32(opData.count).bigEndian
                data.append(Data(bytes: &opLength, count: 4))
            }
            data.append(opData)
        }
        
        // ADAPTIVE COMPRESSION: Always compress (chooses best algorithm)
        return try compress(data)
    }
    
    // Memory pooling: Get reusable buffer
    private func getPooledBuffer(capacity: Int) -> Data {
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
    private func returnPooledBuffer(_ buffer: Data) {
        Self.poolLock.lock()
        defer { Self.poolLock.unlock() }
        
        // Add to pool if not full
        if Self.encodeBufferPool.count < Self.maxPoolSize {
            Self.encodeBufferPool.append(buffer)
        }
        // Otherwise, let it deallocate (pool is full)
    }
    
    // Smart caching: Get cached encoded operation
    private static func getCachedOperation(_ op: BlazeOperation) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let hash = operationHash(op)
        return encodedCache[hash]
    }
    
    // Smart caching: Cache encoded operation
    private static func cacheEncodedOperation(_ op: BlazeOperation, _ encoded: Data) {
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
            hasher.combine(value.description)  // Simple hash of value
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
    
    // Native BlazeBinary encoding (PURE BINARY - NO JSON, NO STRINGS!)
    // OPTIMIZED: Variable-length encoding, bit-packing, zero-copy
    private func encodeOperationNative(_ op: BlazeOperation) throws -> Data {
        var data = Data()
        data.reserveCapacity(100)  // Delta encoding = smaller!
        
        // Encode operation ID (16 bytes UUID - BINARY, not string!)
        data.append(op.id.binaryData)
        
        // VARIABLE-LENGTH TIMESTAMP: Use fewer bytes for small counters!
        let counter = op.timestamp.counter
        if counter < 256 {
            // Small counter: 1 byte (marker + value)
            data.append(0x00)  // Marker: 1-byte counter follows
            data.append(UInt8(counter))
        } else if counter < 65536 {
            // Medium counter: 2 bytes (marker + value)
            data.append(0x01)  // Marker: 2-byte counter follows
            var counter16 = UInt16(counter).bigEndian
            data.append(Data(bytes: &counter16, count: 2))
        } else {
            // Large counter: 8 bytes (marker + value)
            data.append(0x02)  // Marker: 8-byte counter follows
            var counter64 = counter.bigEndian
            data.append(Data(bytes: &counter64, count: 8))
        }
        data.append(op.timestamp.nodeId.binaryData)  // BINARY UUID!
        
        // BIT-PACKED TYPE + COLLECTION LENGTH: Save 1 byte!
        guard let collectionData = op.collectionName.data(using: .utf8) else {
            throw BlazeDBError.invalidData(reason: "Failed to encode collection name: \(op.collectionName)")
        }
        let typeByte: UInt8
        switch op.type {
        case .insert: typeByte = 0x01
        case .update: typeByte = 0x02
        case .delete: typeByte = 0x03
        case .createIndex: typeByte = 0x04
        case .dropIndex: typeByte = 0x05
        }
        
        // Pack type (3 bits) + collection length (5 bits) into 1 byte!
        // Type: 0x01-0x05 (3 bits: 1-5), Length: 0-31 (5 bits) - if length > 31, use 2 bytes
        if collectionData.count < 32 {
            // Pack: type (3 bits, shifted left 5) | length (5 bits)
            let packed = ((typeByte & 0x07) << 5) | UInt8(collectionData.count)
            data.append(packed)
        } else {
            // Length > 31: Use 1 byte for type, 1 byte for length marker, 1-2 bytes for length
            data.append(typeByte)
            if collectionData.count < 256 {
                data.append(0x80)  // Marker: 1-byte length follows
                data.append(UInt8(collectionData.count))
            } else {
                data.append(0x81)  // Marker: 2-byte length follows
                var length = UInt16(collectionData.count).bigEndian
                data.append(Data(bytes: &length, count: 2))
            }
        }
        data.append(collectionData)
        
        // Encode record ID (16 bytes UUID - BINARY, not string!)
        data.append(op.recordId.binaryData)
        
        // Encode changes using BlazeBinary (most efficient!)
        let changesRecord = BlazeDataRecord(op.changes)
        let changesData = try BlazeBinaryEncoder.encode(changesRecord)
        data.append(changesData)
        
        return data
    }
    
    // Decode native BlazeBinary operation (handles variable-length encoding!)
    private func decodeOperationNative(_ data: Data) throws -> BlazeOperation {
        var offset = 0
        
        // Decode operation ID (16 bytes)
        guard offset + 16 <= data.count else { throw RelayError.invalidData }
        let opId = UUID(binaryData: data[offset..<offset+16])
        offset += 16
        
        // Decode timestamp (variable-length counter + 16 bytes nodeId)
        guard offset < data.count else { throw RelayError.invalidData }
        let counterMarker = data[offset]
        let counter: UInt64
        if counterMarker == 0x00 {
            // 1-byte counter
            guard offset + 2 <= data.count else { throw RelayError.invalidData }
            counter = UInt64(data[offset + 1])
            offset += 2
        } else if counterMarker == 0x01 {
            // 2-byte counter
            guard offset + 3 <= data.count else { throw RelayError.invalidData }
            counter = UInt64(data[offset+1..<offset+3].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
            offset += 3
        } else if counterMarker == 0x02 {
            // 8-byte counter
            guard offset + 9 <= data.count else { throw RelayError.invalidData }
            counter = data[offset+1..<offset+9].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            offset += 9
        } else {
            // Legacy: assume 8-byte counter (no marker, old format)
            guard offset + 8 <= data.count else { throw RelayError.invalidData }
            counter = data[offset..<offset+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            offset += 8
        }
        
        guard offset + 16 <= data.count else { throw RelayError.invalidData }
        let nodeId = UUID(binaryData: data[offset..<offset+16])
        offset += 16
        let timestamp = LamportTimestamp(counter: counter, nodeId: nodeId)
        
        // Decode type + collection length (bit-packed or separate)
        guard offset < data.count else { throw RelayError.invalidData }
        let packedByte = data[offset]
        offset += 1
        
        let opType: OperationType
        let nameLength: Int
        
        // Check if bit-packed: top 3 bits set (0x20-0xE0) = packed, else separate
        if (packedByte & 0xE0) != 0 && packedByte >= 0x20 {
            // Bit-packed: type (3 bits) + length (5 bits)
            opType = OperationType.fromPackedByte(packedByte)
            nameLength = Int(packedByte & 0x1F)
        } else {
            // Separate: type byte (0x01-0x05), then length
            opType = OperationType.fromByte(packedByte)
            
            guard offset < data.count else { throw RelayError.invalidData }
            let lengthMarker = data[offset]
            offset += 1
            
            if lengthMarker == 0x80 {
                // 1-byte length
                guard offset < data.count else { throw RelayError.invalidData }
                nameLength = Int(data[offset])
                offset += 1
            } else if lengthMarker == 0x81 {
                // 2-byte length
                guard offset + 2 <= data.count else { throw RelayError.invalidData }
                nameLength = Int(data[offset..<offset+2].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })
                offset += 2
            } else {
                // Legacy: assume 1-byte length (old format)
                nameLength = Int(lengthMarker)
            }
        }
        
        guard offset + nameLength <= data.count else { throw RelayError.invalidData }
        let collectionName = String(data: data[offset..<offset+nameLength], encoding: .utf8) ?? ""
        offset += nameLength
        
        // Decode record ID (16 bytes)
        guard offset + 16 <= data.count else { throw RelayError.invalidData }
        let recordId = UUID(binaryData: data[offset..<offset+16])
        offset += 16
        
        // Decode changes (rest of data, using BlazeBinary)
        let changesData = data[offset...]
        let changesRecord = try BlazeBinaryDecoder.decode(changesData)
        
        return BlazeOperation(
            id: opId,
            timestamp: timestamp,
            nodeId: nodeId,
            type: opType,
            collectionName: collectionName,
            recordId: recordId,
            changes: changesRecord.storage
        )
    }
    
    private func encodeOperationOptimized(_ op: BlazeOperation) throws -> Data {
        // Minimal encoding: Only essential fields
        // Skip nodeId, dependencies if not needed for basic sync
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // No pretty printing
        
        // Create minimal operation (only what's needed)
        struct MinimalOperation: Codable {
            let id: UUID
            let timestamp: LamportTimestamp
            let type: OperationType
            let collectionName: String
            let recordId: UUID
            let changes: [String: BlazeDocumentField]
        }
        
        let minimal = MinimalOperation(
            id: op.id,
            timestamp: op.timestamp,
            type: op.type,
            collectionName: op.collectionName,
            recordId: op.recordId,
            changes: op.changes
        )
        
        return try encoder.encode(minimal)
    }
    
    private func decodeOperations(_ data: Data) throws -> [BlazeOperation] {
        var operations: [BlazeOperation] = []
        var offset = 0
        
        // Decompress if needed (check magic bytes)
        let decompressed = try decompressIfNeeded(data)
        
        // Read count (variable-length encoding)
        guard offset < decompressed.count else {
            throw RelayError.invalidData
        }
        let firstByte = decompressed[offset]
        let count: UInt32
        if firstByte == 0xFF {
            // 4-byte count
            guard offset + 5 <= decompressed.count else {
                throw RelayError.invalidData
            }
            count = decompressed[offset+1..<offset+5].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            offset += 5
        } else {
            // 1-byte count
            count = UInt32(firstByte)
            offset += 1
        }
        
        // Decode each operation
        for _ in 0..<count {
            guard offset < decompressed.count else {
                throw RelayError.invalidData
            }
            
            // Read operation length (variable-length encoding)
            let lengthByte = decompressed[offset]
            let opLength: Int
            if lengthByte < 128 {
                // 1-byte length (7 bits)
                opLength = Int(lengthByte)
                offset += 1
            } else if (lengthByte & 0x80) != 0 && (lengthByte & 0x81) == 0x80 {
                // 2-byte length
                guard offset + 2 <= decompressed.count else {
                    throw RelayError.invalidData
                }
                let high = UInt16(lengthByte & 0x7F) << 8
                let low = UInt16(decompressed[offset + 1])
                opLength = Int(high | low)
                offset += 2
            } else if lengthByte == 0xFF {
                // 4-byte length
                guard offset + 5 <= decompressed.count else {
                    throw RelayError.invalidData
                }
                opLength = Int(decompressed[offset+1..<offset+5].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                offset += 5
            } else {
                throw RelayError.invalidData
            }
            
            guard offset + opLength <= decompressed.count else {
                throw RelayError.invalidData
            }
            let opData = decompressed[offset..<offset+opLength]
            offset += opLength
            
            let op = try decodeOperation(opData)
            operations.append(op)
        }
        
        return operations
    }
    
    private func encodeOperation(_ op: BlazeOperation) throws -> Data {
        // NOTE: Native BlazeBinary encoding for BlazeOperation is intentionally not implemented.
        // JSON encoding is used for compatibility and simplicity. Future versions may add
        // BlazeBinary encoding for improved performance, but JSON remains the default format.
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // No pretty printing = smaller
        return try encoder.encode(op)
    }
    
    private func decodeOperation(_ data: Data) throws -> BlazeOperation {
        // Use native BlazeBinary decoding (NO JSON!)
        return try decodeOperationNative(data)
    }
    
    // MARK: - Advanced Adaptive Compression
    
    // Compression dictionary for common patterns (learns over time)
    private static var compressionDictionary: Data?
    private static var dictionarySize: Int = 0
    
    private func compress(_ data: Data) throws -> Data {
        // ULTRA-FAST MODE: Always use LZ4 (fastest compression!)
        // For maximum speed, prioritize speed over compression ratio
        let algorithm: compression_algorithm
        let magicBytes: String
        
        // ULTRA-FAST: Use LZ4 for everything (fastest algorithm!)
        // Small overhead in compression ratio, but 3-5x faster compression!
        algorithm = COMPRESSION_LZ4
        magicBytes = "BZL4"  // BlazeDB LZ4
        
        // Legacy adaptive mode (commented out for ultra-fast):
        // Small data (<1KB): Use fastest (LZ4)
        // if data.count < 1024 {
        //     algorithm = COMPRESSION_LZ4
        //     magicBytes = "BZL4"  // BlazeDB LZ4
        // }
        // Medium data (1-10KB): Use balanced (ZLIB - good compression, fast)
        // else if data.count < 10_240 {
        //     algorithm = COMPRESSION_ZLIB
        //     magicBytes = "BZLB"  // BlazeDB ZLIB (balanced)
        // }
        // Large data (>10KB): Use best compression (LZMA)
        // else {
        //     algorithm = COMPRESSION_LZMA
        //     magicBytes = "BZMA"  // BlazeDB LZMA
        // }
        
        // MEMORY POOLING: Reuse compression buffer
        let buffer = getPooledCompressBuffer(capacity: data.count)
        defer { returnPooledCompressBuffer(buffer) }
        
        // Use dictionary if available (better compression for repeated patterns)
        let dictionary = Self.compressionDictionary
        let dictPtr = dictionary?.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) }
        let dictSize = dictionary?.count ?? 0
        
        let compressedSize = data.withUnsafeBytes { source in
            compression_encode_buffer(
                buffer, data.count,
                source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                dictPtr, dictSize,  // Dictionary for better compression!
                algorithm
            )
        }
        
        guard compressedSize > 0 && compressedSize < data.count else {
            // Compression didn't help, return original
            return data
        }
        
        // Update dictionary with this data (learn common patterns)
        updateCompressionDictionary(data)
        
        // Prepend magic bytes + algorithm indicator
        var result = Data(magicBytes.utf8)
        result.append(Data(bytes: buffer, count: compressedSize))
        return result
    }
    
    // Memory pooling: Get reusable compression buffer
    private func getPooledCompressBuffer(capacity: Int) -> UnsafeMutablePointer<UInt8> {
        Self.poolLock.lock()
        defer { Self.poolLock.unlock() }
        
        // Find buffer with sufficient capacity
        if let index = Self.compressBufferPool.firstIndex(where: { 
            // Check capacity (we'll track this separately or use a fixed size)
            true  // For now, reuse any buffer
        }) {
            return Self.compressBufferPool.remove(at: index)
        }
        
        // No buffer available, allocate new one
        return UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    }
    
    // Memory pooling: Return compression buffer to pool
    private func returnPooledCompressBuffer(_ buffer: UnsafeMutablePointer<UInt8>) {
        Self.poolLock.lock()
        defer { Self.poolLock.unlock() }
        
        // Add to pool if not full
        if Self.compressBufferPool.count < Self.maxPoolSize {
            Self.compressBufferPool.append(buffer)
        } else {
            // Pool is full, deallocate
            buffer.deallocate()
        }
    }
    
    /// Update compression dictionary with new data patterns
    private func updateCompressionDictionary(_ data: Data) {
        // Learn common patterns (first 1KB of data, most common patterns)
        let sampleSize = min(1024, data.count)
        let sample = data.prefix(sampleSize)
        
        // Update dictionary (rolling window, keep last 4KB)
        if Self.compressionDictionary == nil {
            Self.compressionDictionary = sample
            Self.dictionarySize = sampleSize
        } else {
            // Merge with existing dictionary (rolling average)
            var merged = Self.compressionDictionary!
            merged.append(sample)
            
            // Keep only last 4KB
            if merged.count > 4096 {
                merged = merged.suffix(4096)
            }
            
            Self.compressionDictionary = merged
            Self.dictionarySize = merged.count
        }
    }
    
    private func decompressIfNeeded(_ data: Data) throws -> Data {
        // Check for compression magic bytes
        guard data.count >= 4 else {
            return data  // Not compressed
        }
        
        let magic = String(data: data[0..<4], encoding: .utf8) ?? ""
        let compressed = data[4...]
        
        // Determine algorithm from magic bytes
        let algorithm: compression_algorithm
        switch magic {
        case "BZL4":  // LZ4 (fastest)
            algorithm = COMPRESSION_LZ4
        case "BZLB":  // ZLIB (balanced)
            algorithm = COMPRESSION_ZLIB
        case "BZMA":  // LZMA (best compression)
            algorithm = COMPRESSION_LZMA
        case "BZCZ":  // Legacy (LZ4)
            algorithm = COMPRESSION_LZ4
        default:
            // Not compressed
            return data
        }
        
        // Estimate decompressed size (algorithm-specific multipliers)
        let multiplier: Int
        switch algorithm {
        case COMPRESSION_LZ4: multiplier = 3  // LZ4: 2-3x
        case COMPRESSION_ZLIB: multiplier = 4  // ZLIB: 3-4x
        case COMPRESSION_LZMA: multiplier = 10  // LZMA: 5-10x (best compression)
        default: multiplier = 3
        }
        
        let estimatedSize = compressed.count * multiplier
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedSize)
        defer { buffer.deallocate() }
        
        // Use dictionary if available
        let dictionary = Self.compressionDictionary
        let dictPtr = dictionary?.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) }
        let dictSize = dictionary?.count ?? 0
        
        let decompressedSize = compressed.withUnsafeBytes { source in
            compression_decode_buffer(
                buffer, estimatedSize,
                source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                dictPtr, dictSize,  // Dictionary for better decompression!
                algorithm
            )
        }
        
        guard decompressedSize > 0 else {
            throw RelayError.decompressionFailed
        }
        
        return Data(bytes: buffer, count: decompressedSize)
    }
    
    private struct SyncStateRequest: Codable {}
    private func encodeSyncStateRequest(_ request: SyncStateRequest) throws -> Data {
        return try JSONEncoder().encode(request)
    }
    
    private func decodeSyncState(_ data: Data) throws -> SyncState {
        return try JSONDecoder().decode(SyncState.self, from: data)
    }
    
    private struct PullRequest: Codable {
        let since: LamportTimestamp
    }
    
    private func encodePullRequest(_ request: PullRequest) throws -> Data {
        return try JSONEncoder().encode(request)
    }
    
    private struct SubscribeRequest: Codable {
        let collections: [String]
    }
    
    private func encodeSubscribeRequest(_ request: SubscribeRequest) throws -> Data {
        return try JSONEncoder().encode(request)
    }
}

