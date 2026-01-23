//
//  BlazeOperation.swift
//  BlazeDB Distributed
//
//  Core operation type for distributed sync
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

/// Represents a single database operation that can be replicated across nodes
public struct BlazeOperation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: LamportTimestamp
    public let nodeId: UUID
    public let type: OperationType
    public let collectionName: String
    public let recordId: UUID
    public let changes: [String: BlazeDocumentField]
    public let dependencies: [UUID]  // Operations this depends on
    public let role: SyncRole?  // SERVER/CLIENT ROLE (for priority resolution)
    
    // SECURITY: Replay protection
    public let nonce: Data  // Random nonce to prevent replay attacks
    public let expiresAt: Date  // Operation expiry (prevents old operations)
    
    // SECURITY: Operation signature (HMAC-SHA256)
    public var signature: Data?  // Optional signature for tamper detection
    
    public init(
        id: UUID = UUID(),
        timestamp: LamportTimestamp,
        nodeId: UUID,
        type: OperationType,
        collectionName: String,
        recordId: UUID,
        changes: [String: BlazeDocumentField],
        dependencies: [UUID] = [],
        role: SyncRole? = nil,  // Optional: track role for conflict resolution
        nonce: Data? = nil,  // Auto-generate if not provided
        expiresAt: Date? = nil,  // Default: 60 seconds from now
        signature: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.nodeId = nodeId
        self.type = type
        self.collectionName = collectionName
        self.recordId = recordId
        self.changes = changes
        self.dependencies = dependencies
        self.role = role
        self.nonce = nonce ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        self.expiresAt = expiresAt ?? Date().addingTimeInterval(60)  // 60 second expiry
        self.signature = signature
    }
}

public enum OperationType: String, Codable, Sendable {
    case insert
    case update
    case delete
    case createIndex
    case dropIndex
    
    // Helper for bit-packed decoding
    static func fromPackedByte(_ byte: UInt8) -> OperationType {
        let typeBits = (byte >> 5) & 0x07  // Extract top 3 bits
        switch typeBits {
        case 1: return .insert
        case 2: return .update
        case 3: return .delete
        case 4: return .createIndex
        case 5: return .dropIndex
        default: return .insert  // Default fallback
        }
    }
    
    // Helper for separate byte decoding
    static func fromByte(_ byte: UInt8) -> OperationType {
        switch byte {
        case 0x01: return .insert
        case 0x02: return .update
        case 0x03: return .delete
        case 0x04: return .createIndex
        case 0x05: return .dropIndex
        default: return .insert  // Default fallback
        }
    }
}

/// Lamport timestamp for causal ordering
public struct LamportTimestamp: Comparable, Codable, Hashable, Sendable {
    public let counter: UInt64
    public let nodeId: UUID
    
    public init(counter: UInt64, nodeId: UUID) {
        self.counter = counter
        self.nodeId = nodeId
    }
    
    public static func < (lhs: LamportTimestamp, rhs: LamportTimestamp) -> Bool {
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        // Tie-breaker: use node ID for deterministic ordering
        return lhs.nodeId.uuidString < rhs.nodeId.uuidString
    }
}

/// Tracks operations for a node
public actor OperationLog {
    internal var operations: [UUID: BlazeOperation] = [:]
    private var currentClock: UInt64 = 0
    private let nodeId: UUID
    private let storageURL: URL
    
    public init(nodeId: UUID, storageURL: URL) {
        self.nodeId = nodeId
        self.storageURL = storageURL
    }
    
    /// Record a new local operation
    public func recordOperation(
        type: OperationType,
        collectionName: String,
        recordId: UUID,
        changes: [String: BlazeDocumentField],
        role: SyncRole? = nil  // SERVER/CLIENT ROLE
    ) -> BlazeOperation {
        // Increment logical clock
        currentClock += 1
        
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: currentClock, nodeId: nodeId),
            nodeId: nodeId,
            type: type,
            collectionName: collectionName,
            recordId: recordId,
            changes: changes,
            role: role  // Include role in operation
        )
        
        operations[op.id] = op
        return op
    }
    
    /// Apply a remote operation (updates clock)
    public func applyRemoteOperation(_ op: BlazeOperation) {
        operations[op.id] = op
        
        // Update logical clock (Lamport rule: max(local, remote) + 1)
        if op.timestamp.counter >= currentClock {
            currentClock = op.timestamp.counter + 1
        }
    }
    
    /// Get operations since a timestamp
    public func getOperations(since timestamp: LamportTimestamp) -> [BlazeOperation] {
        return operations.values
            .filter { $0.timestamp > timestamp }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Check if operation exists
    public func contains(_ operationId: UUID) -> Bool {
        return operations[operationId] != nil
    }
    
    /// Get current sync state
    public func getCurrentState() -> SyncState {
        let maxTimestamp = operations.values.map(\.timestamp).max() ?? LamportTimestamp(counter: 0, nodeId: nodeId)
        
        return SyncState(
            nodeId: nodeId,
            lastSyncedTimestamp: maxTimestamp,
            operationCount: operations.count,
            collections: Set(operations.values.map(\.collectionName)).map { $0 }
        )
    }
    
    /// Persist to disk using BlazeBinary (faster than JSON!)
    public func save() throws {
        var data = Data()
        data.reserveCapacity(operations.count * 200)  // Pre-allocate
        
        // Write count (4 bytes)
        var count = UInt32(operations.count).bigEndian
        data.append(Data(bytes: &count, count: 4))
        
        // Write each operation in BlazeBinary format
        for op in operations.values {
            let opData = try BlazeOperation.encodeToBlazeBinary(op)
            // Write operation length (4 bytes) + data
            var opLength = UInt32(opData.count).bigEndian
            data.append(Data(bytes: &opLength, count: 4))
            data.append(opData)
        }
        
        try data.write(to: storageURL)
    }
    
    /// Load from disk using BlazeBinary (faster than JSON!)
    public func load() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        let data = try Data(contentsOf: storageURL)
        var offset = 0
        
        // Read count (4 bytes)
        guard offset + 4 <= data.count else { return }
        let count = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        
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
            
            // Decode operation
            let op = try BlazeOperation.decodeFromBlazeBinary(opData)
            operations[op.id] = op
            currentClock = max(currentClock, op.timestamp.counter)
        }
    }
    
    /// Configure GC (placeholder for future use)
    private var gcConfig: OperationLogGCConfig?
    
    public func configureGC(_ config: OperationLogGCConfig) {
        // Store config for periodic cleanup
        // In a real implementation, we'd store this and use it in periodic cleanup
    }
}

public struct SyncState: Codable, Sendable {
    public let nodeId: UUID
    public let lastSyncedTimestamp: LamportTimestamp
    public let operationCount: Int
    public let collections: [String]
}

#endif // !BLAZEDB_LINUX_CORE
