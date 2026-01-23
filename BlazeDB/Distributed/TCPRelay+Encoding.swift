//
//  TCPRelay+Encoding.swift
//  BlazeDB Distributed
//
//  Encoding/decoding logic for TCPRelay
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

extension TCPRelay {
    // MARK: - Operation Encoding/Decoding
    
    internal func encodeOperations(_ ops: [BlazeOperation]) async throws -> Data {
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
        
        // SMART CACHING + PARALLEL ENCODING: Check cache first, then encode in parallel!
        let encodedOps = try await uniqueOps.concurrentMap { @Sendable op in
            // Check cache first (smart caching!)
            if let cached = Self.getCachedOperation(op) {
                Self.incrementCacheHits()
                return cached
            }
            
            // Cache miss - encode and cache it
            Self.incrementCacheMisses()
            
            let encoded = try self.encodeOperationNative(op)  // Native BlazeBinary, not JSON!
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
        
        // Compress (stubbed - returns data as-is)
        return compress(data)
    }
    
    internal func decodeOperations(_ data: Data) async throws -> [BlazeOperation] {
        var operations: [BlazeOperation] = []
        var offset = 0
        
        // Decompress if needed (stubbed)
        let decompressed = try decompressIfNeeded(data)
        
        // Read count (variable-length encoding)
        guard offset < decompressed.count else {
            throw RelayError.invalidData
        }
        let firstByte = decompressed[decompressed.startIndex + offset]
        let count: UInt32
        if firstByte == 0xFF {
            // 4-byte count
            guard offset + 5 <= decompressed.count else {
                throw RelayError.invalidData
            }
            var countBytes: [UInt8] = []
            countBytes.reserveCapacity(4)
            for i in 0..<4 {
                countBytes.append(decompressed[decompressed.startIndex + offset + 1 + i])
            }
            count = (UInt32(countBytes[0]) << 24) | (UInt32(countBytes[1]) << 16) | (UInt32(countBytes[2]) << 8) | UInt32(countBytes[3])
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
            let lengthByte = decompressed[decompressed.startIndex + offset]
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
                let low = UInt16(decompressed[decompressed.startIndex + offset + 1])
                opLength = Int(high | low)
                offset += 2
            } else if lengthByte == 0xFF {
                // 4-byte length
                guard offset + 5 <= decompressed.count else {
                    throw RelayError.invalidData
                }
                var lengthBytes: [UInt8] = []
                lengthBytes.reserveCapacity(4)
                for i in 0..<4 {
                    lengthBytes.append(decompressed[decompressed.startIndex + offset + 1 + i])
                }
                opLength = Int((UInt32(lengthBytes[0]) << 24) | (UInt32(lengthBytes[1]) << 16) | (UInt32(lengthBytes[2]) << 8) | UInt32(lengthBytes[3]))
                offset += 5
            } else {
                throw RelayError.invalidData
            }
            
            guard offset + opLength <= decompressed.count else {
                throw RelayError.invalidData
            }
            let opDataRange = (decompressed.startIndex + offset)..<(decompressed.startIndex + offset + opLength)
            let opData = decompressed[opDataRange]
            offset += opLength
            
            let op = try decodeOperation(opData)
            operations.append(op)
        }
        
        return operations
    }
    
    private func encodeOperation(_ op: BlazeOperation) throws -> Data {
        // Use native BlazeBinary encoding
        return try encodeOperationNative(op)
    }
    
    private func decodeOperation(_ data: Data) throws -> BlazeOperation {
        // Use native BlazeBinary decoding (NO JSON!)
        return try decodeOperationNative(data)
    }
    
    // MARK: - Native BlazeBinary Encoding
    
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
            throw BlazeDBError.invalidData(reason: "Failed to encode collection name as UTF-8")
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
        var opIdBytes: [UInt8] = []
        opIdBytes.reserveCapacity(16)
        for i in 0..<16 {
            opIdBytes.append(data[data.startIndex + offset + i])
        }
        let opId = UUID(binaryData: Data(opIdBytes))
        offset += 16
        
        // Decode timestamp (variable-length counter + 16 bytes nodeId)
        guard offset < data.count else { throw RelayError.invalidData }
        let counterMarker = data[data.startIndex + offset]
        let counter: UInt64
        if counterMarker == 0x00 {
            // 1-byte counter
            guard offset + 2 <= data.count else { throw RelayError.invalidData }
            counter = UInt64(data[data.startIndex + offset + 1])
            offset += 2
        } else if counterMarker == 0x01 {
            // 2-byte counter
            guard offset + 3 <= data.count else { throw RelayError.invalidData }
            let counterRange = (data.startIndex + offset + 1)..<(data.startIndex + offset + 3)
            let counterBytes = Array(data[counterRange])
            counter = UInt64((UInt16(counterBytes[0]) << 8) | UInt16(counterBytes[1]))
            offset += 3
        } else if counterMarker == 0x02 {
            // 8-byte counter
            guard offset + 9 <= data.count else { throw RelayError.invalidData }
            let counterRange = (data.startIndex + offset + 1)..<(data.startIndex + offset + 9)
            let counterBytes = Array(data[counterRange])
            counter = (UInt64(counterBytes[0]) << 56) | (UInt64(counterBytes[1]) << 48) | (UInt64(counterBytes[2]) << 40) | (UInt64(counterBytes[3]) << 32) |
                      (UInt64(counterBytes[4]) << 24) | (UInt64(counterBytes[5]) << 16) | (UInt64(counterBytes[6]) << 8) | UInt64(counterBytes[7])
            offset += 9
        } else {
            // Legacy: assume 8-byte counter (no marker, old format)
            guard offset + 8 <= data.count else { throw RelayError.invalidData }
            let counterRange = (data.startIndex + offset)..<(data.startIndex + offset + 8)
            let counterBytes = Array(data[counterRange])
            counter = (UInt64(counterBytes[0]) << 56) | (UInt64(counterBytes[1]) << 48) | (UInt64(counterBytes[2]) << 40) | (UInt64(counterBytes[3]) << 32) |
                      (UInt64(counterBytes[4]) << 24) | (UInt64(counterBytes[5]) << 16) | (UInt64(counterBytes[6]) << 8) | UInt64(counterBytes[7])
            offset += 8
        }
        
        guard offset + 16 <= data.count else { throw RelayError.invalidData }
        var nodeIdBytes: [UInt8] = []
        nodeIdBytes.reserveCapacity(16)
        for i in 0..<16 {
            nodeIdBytes.append(data[data.startIndex + offset + i])
        }
        let nodeId = UUID(binaryData: Data(nodeIdBytes))
        offset += 16
        let timestamp = LamportTimestamp(counter: counter, nodeId: nodeId)
        
        // Decode type + collection length (bit-packed or separate)
        guard offset < data.count else { throw RelayError.invalidData }
        let packedByte = data[data.startIndex + offset]
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
            let lengthMarker = data[data.startIndex + offset]
            offset += 1
            
            if lengthMarker == 0x80 {
                // 1-byte length
                guard offset < data.count else { throw RelayError.invalidData }
                nameLength = Int(data[data.startIndex + offset])
                offset += 1
            } else if lengthMarker == 0x81 {
                // 2-byte length
                guard offset + 2 <= data.count else { throw RelayError.invalidData }
                let lengthRange = (data.startIndex + offset)..<(data.startIndex + offset + 2)
                let lengthBytes = Array(data[lengthRange])
                nameLength = Int((UInt16(lengthBytes[0]) << 8) | UInt16(lengthBytes[1]))
                offset += 2
            } else {
                // Legacy: assume 1-byte length (old format)
                nameLength = Int(lengthMarker)
            }
        }
        
        guard offset + nameLength <= data.count else { throw RelayError.invalidData }
        let nameRange = (data.startIndex + offset)..<(data.startIndex + offset + nameLength)
        let collectionName = String(data: data[nameRange], encoding: .utf8) ?? ""
        offset += nameLength
        
        // Decode record ID (16 bytes)
        guard offset + 16 <= data.count else { throw RelayError.invalidData }
        var recordIdBytes: [UInt8] = []
        recordIdBytes.reserveCapacity(16)
        for i in 0..<16 {
            recordIdBytes.append(data[data.startIndex + offset + i])
        }
        let recordId = UUID(binaryData: Data(recordIdBytes))
        offset += 16
        
        // Decode changes (rest of data, using BlazeBinary)
        let changesRange = (data.startIndex + offset)..<data.endIndex
        let changesData = data[changesRange]
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
    
    // MARK: - Request/Response Encoding
    
    internal struct SyncStateRequest: Codable {}
    internal func encodeSyncStateRequest(_ request: SyncStateRequest) async throws -> Data {
        return try JSONEncoder().encode(request)
    }
    
    internal func decodeSyncState(_ data: Data) async throws -> SyncState {
        return try JSONDecoder().decode(SyncState.self, from: data)
    }
    
    internal struct PullRequest: Codable {
        let since: LamportTimestamp
    }
    
    internal func encodePullRequest(_ request: PullRequest) async throws -> Data {
        return try JSONEncoder().encode(request)
    }
    
    internal struct SubscribeRequest: Codable {
        let collections: [String]
    }
    
    internal func encodeSubscribeRequest(_ request: SubscribeRequest) async throws -> Data {
        return try JSONEncoder().encode(request)
    }
}
#endif // !BLAZEDB_LINUX_CORE

