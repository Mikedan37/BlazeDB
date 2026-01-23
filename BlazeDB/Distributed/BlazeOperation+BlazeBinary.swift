//
//  BlazeOperation+BlazeBinary.swift
//  BlazeDB Distributed
//
//  BlazeBinary encoding/decoding for BlazeOperation (faster than JSON!)
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

extension BlazeOperation {
    /// Encode operation to BlazeBinary format (faster than JSON!)
    static func encodeToBlazeBinary(_ op: BlazeOperation) throws -> Data {
        var data = Data()
        data.reserveCapacity(200)  // Pre-allocate for performance
        
        // Operation ID (16 bytes UUID)
        let idBytes = withUnsafeBytes(of: op.id.uuid) { Data($0) }
        data.append(idBytes)
        
        // Timestamp (8 bytes counter + 16 bytes nodeId)
        var counter = op.timestamp.counter.bigEndian
        data.append(Data(bytes: &counter, count: 8))
        let timestampNodeIdBytes = withUnsafeBytes(of: op.timestamp.nodeId.uuid) { Data($0) }
        data.append(timestampNodeIdBytes)
        
        // Node ID (16 bytes UUID)
        let nodeIdBytes = withUnsafeBytes(of: op.nodeId.uuid) { Data($0) }
        data.append(nodeIdBytes)
        
        // Operation type (1 byte)
        let typeByte: UInt8
        switch op.type {
        case .insert: typeByte = 0x01
        case .update: typeByte = 0x02
        case .delete: typeByte = 0x03
        case .createIndex: typeByte = 0x04
        case .dropIndex: typeByte = 0x05
        }
        data.append(typeByte)
        
        // Collection name (1 byte length + UTF-8 bytes)
        guard let collectionBytes = op.collectionName.data(using: .utf8) else {
            throw BlazeDBError.invalidData(reason: "Failed to encode collection name: \(op.collectionName)")
        }
        data.append(UInt8(collectionBytes.count))
        data.append(collectionBytes)
        
        // Record ID (16 bytes UUID)
        let recordIdBytes = withUnsafeBytes(of: op.recordId.uuid) { Data($0) }
        data.append(recordIdBytes)
        
        // Changes (encode as BlazeDataRecord using BlazeBinary)
        let changesRecord = BlazeDataRecord(op.changes)
        let changesData = try BlazeBinaryEncoder.encode(changesRecord)
        // Write changes length (4 bytes) + data
        var changesLength = UInt32(changesData.count).bigEndian
        data.append(Data(bytes: &changesLength, count: 4))
        data.append(changesData)
        
        // Dependencies (1 byte count + UUIDs)
        data.append(UInt8(op.dependencies.count))
        for dep in op.dependencies {
            let depBytes = withUnsafeBytes(of: dep.uuid) { Data($0) }
            data.append(depBytes)
        }
        
        // Role (1 byte: 0=nil, 1=server, 2=client)
        if let role = op.role {
            data.append(role == .server ? 0x01 : 0x02)
        } else {
            data.append(0x00)
        }
        
        // Nonce (16 bytes)
        data.append(op.nonce)
        
        // Expires at (8 bytes timestamp)
        let expiresTimestamp = op.expiresAt.timeIntervalSince1970
        var expiresTimestampBytes = expiresTimestamp.bitPattern.bigEndian
        data.append(Data(bytes: &expiresTimestampBytes, count: 8))
        
        // Signature (1 byte flag + optional 32 bytes)
        if let sig = op.signature {
            data.append(0x01)  // Has signature
            data.append(sig)
        } else {
            data.append(0x00)  // No signature
        }
        
        return data
    }
    
    /// Decode operation from BlazeBinary format
    static func decodeFromBlazeBinary(_ data: Data) throws -> BlazeOperation {
        var offset = 0
        
        // Operation ID (16 bytes)
        guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let idBytes = data[offset..<offset+16]
        let id = idBytes.withUnsafeBytes { bytes in
            UUID(uuid: bytes.load(as: uuid_t.self))
        }
        offset += 16
        
        // Timestamp counter (8 bytes)
        guard offset + 8 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let counter = data[offset..<offset+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        offset += 8
        
        // Timestamp nodeId (16 bytes)
        guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let timestampNodeIdBytes = data[offset..<offset+16]
        let timestampNodeId = timestampNodeIdBytes.withUnsafeBytes { bytes in
            UUID(uuid: bytes.load(as: uuid_t.self))
        }
        offset += 16
        let timestamp = LamportTimestamp(counter: counter, nodeId: timestampNodeId)
        
        // Node ID (16 bytes)
        guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let nodeIdBytes = data[offset..<offset+16]
        let nodeId = nodeIdBytes.withUnsafeBytes { bytes in
            UUID(uuid: bytes.load(as: uuid_t.self))
        }
        offset += 16
        
        // Operation type (1 byte)
        guard offset < data.count else { throw BlazeOperationDecodeError.invalidData }
        let typeByte = data[offset]
        offset += 1
        let type: OperationType
        switch typeByte {
        case 0x01: type = .insert
        case 0x02: type = .update
        case 0x03: type = .delete
        case 0x04: type = .createIndex
        case 0x05: type = .dropIndex
        default: throw BlazeOperationDecodeError.invalidType
        }
        
        // Collection name (1 byte length + UTF-8)
        guard offset < data.count else { throw BlazeOperationDecodeError.invalidData }
        let nameLength = Int(data[offset])
        offset += 1
        guard offset + nameLength <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let collectionName = String(data: data[offset..<offset+nameLength], encoding: .utf8) ?? ""
        offset += nameLength
        
        // Record ID (16 bytes)
        guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let recordIdBytes = data[offset..<offset+16]
        let recordId = recordIdBytes.withUnsafeBytes { bytes in
            UUID(uuid: bytes.load(as: uuid_t.self))
        }
        offset += 16
        
        // Changes (4 bytes length + BlazeBinary data)
        guard offset + 4 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let changesLength = Int(data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        offset += 4
        guard offset + changesLength <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let changesData = data[offset..<offset+changesLength]
        offset += changesLength
        let changesRecord = try BlazeBinaryDecoder.decode(changesData)
        let changes = changesRecord.storage
        
        // Dependencies (1 byte count + UUIDs)
        guard offset < data.count else { throw BlazeOperationDecodeError.invalidData }
        let depCount = Int(data[offset])
        offset += 1
        var dependencies: [UUID] = []
        for _ in 0..<depCount {
            guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
            let depBytes = data[offset..<offset+16]
            let dep = depBytes.withUnsafeBytes { bytes in
                UUID(uuid: bytes.load(as: uuid_t.self))
            }
            dependencies.append(dep)
            offset += 16
        }
        
        // Role (1 byte)
        guard offset < data.count else { throw BlazeOperationDecodeError.invalidData }
        let roleByte = data[offset]
        offset += 1
        let role: SyncRole? = roleByte == 0x00 ? nil : (roleByte == 0x01 ? .server : .client)
        
        // Nonce (16 bytes)
        guard offset + 16 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let nonce = data[offset..<offset+16]
        offset += 16
        
        // Expires at (8 bytes)
        guard offset + 8 <= data.count else { throw BlazeOperationDecodeError.invalidData }
        let expiresTimestampBits = data[offset..<offset+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let expiresTimestamp = Double(bitPattern: expiresTimestampBits)
        let expiresAt = Date(timeIntervalSince1970: expiresTimestamp)
        offset += 8
        
        // Signature (1 byte flag + optional 32 bytes)
        guard offset < data.count else { throw BlazeOperationDecodeError.invalidData }
        let hasSignature = data[offset] == 0x01
        offset += 1
        let signature: Data?
        if hasSignature {
            guard offset + 32 <= data.count else { throw BlazeOperationDecodeError.invalidData }
            signature = data[offset..<offset+32]
            offset += 32
        } else {
            signature = nil
        }
        
        return BlazeOperation(
            id: id,
            timestamp: timestamp,
            nodeId: nodeId,
            type: type,
            collectionName: collectionName,
            recordId: recordId,
            changes: changes,
            dependencies: dependencies,
            role: role,
            nonce: nonce,
            expiresAt: expiresAt,
            signature: signature
        )
    }
}

enum BlazeOperationDecodeError: Error {
    case invalidData
    case invalidType
}

// UUID extension is already defined in TCPRelay.swift (binaryData property)

#endif // !BLAZEDB_LINUX_CORE
