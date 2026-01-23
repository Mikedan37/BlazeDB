//
//  InMemoryRelay.swift
//  BlazeDB Distributed
//
//  In-memory relay for local database synchronization (same device)
//

#if !BLAZEDB_LINUX_CORE
import Foundation

/// In-memory relay for coordinating databases on the same device (in-memory queue, not Unix Domain Sockets)
public actor InMemoryRelay: BlazeSyncRelay {
    private let fromNodeId: UUID
    private let toNodeId: UUID
    private let mode: BlazeTopology.ConnectionMode
    internal var messageQueue: [BlazeOperation] = []
    private var operationHandler: (([BlazeOperation]) async -> Void)?
    private var isConnected = false
    // Track sync state per node (for incremental sync)
    private var lastSyncedTimestamps: [UUID: LamportTimestamp] = [:]
    
    public init(
        fromNodeId: UUID,
        toNodeId: UUID,
        mode: BlazeTopology.ConnectionMode
    ) {
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.mode = mode
    }
    
    // MARK: - BlazeSyncRelay Protocol
    
    public func connect() async throws {
        isConnected = true
        BlazeLogger.info("InMemoryRelay connected: \(fromNodeId) → \(toNodeId)")
    }
    
    public func disconnect() async {
        isConnected = false
        messageQueue.removeAll()
        BlazeLogger.info("InMemoryRelay disconnected: \(fromNodeId) → \(toNodeId)")
    }
    
    public func exchangeSyncState() async throws -> SyncState {
        // Get the last synced timestamp for the requesting node (or 0 if never synced)
        let lastSynced = lastSyncedTimestamps[toNodeId] ?? LamportTimestamp(counter: 0, nodeId: toNodeId)
        
        // Get max timestamp from all operations in queue
        let maxTimestamp = messageQueue.map(\.timestamp).max() ?? lastSynced
        
        return SyncState(
            nodeId: fromNodeId,
            lastSyncedTimestamp: maxTimestamp,
            operationCount: messageQueue.count,
            collections: []
        )
    }
    
    public func pullOperations(since timestamp: LamportTimestamp) async throws -> [BlazeOperation] {
        return messageQueue.filter { $0.timestamp > timestamp }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    public func pushOperations(_ ops: [BlazeOperation]) async throws {
        guard isConnected else {
            throw RelayError.notConnected
        }
        
        guard !ops.isEmpty else { return }
        
        // Update last synced timestamp (track what we've sent)
        let maxTimestamp = ops.map(\.timestamp).max() ?? lastSyncedTimestamps[toNodeId] ?? LamportTimestamp(counter: 0, nodeId: toNodeId)
        lastSyncedTimestamps[toNodeId] = maxTimestamp
        
        // Check mode
        switch mode {
        case .bidirectional:
            // Add to queue and notify
            messageQueue.append(contentsOf: ops)
            await operationHandler?(ops)
            
        case .readOnly:
            // Only push if we're the source (fromNodeId)
            // In read-only mode, target doesn't push back
            messageQueue.append(contentsOf: ops)
            await operationHandler?(ops)
            
        case .writeOnly:
            // Only push if we're the target (toNodeId)
            // In write-only mode, source doesn't receive
            break
        }
    }
    
    public func subscribe(to collections: [String]) async throws {
        // No-op for in-memory relay (all operations are local)
    }
    
    public func onOperationReceived(_ handler: @escaping ([BlazeOperation]) async -> Void) {
        self.operationHandler = handler
    }
}

enum RelayError: Error {
    case notConnected
    case invalidData
    case compressionFailed
    case decompressionFailed
}


#endif // !BLAZEDB_LINUX_CORE
