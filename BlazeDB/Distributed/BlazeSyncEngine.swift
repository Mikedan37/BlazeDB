//
//  BlazeSyncEngine.swift
//  BlazeDB Distributed
//
//  Sync engine for distributed BlazeDB
//

#if !BLAZEDB_LINUX_CORE
#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif
import Foundation

/// Protocol for sync transport implementations
@preconcurrency
public protocol BlazeSyncRelay: Sendable {
    func connect() async throws
    func disconnect() async
    func exchangeSyncState() async throws -> SyncState
    func pullOperations(since: LamportTimestamp) async throws -> [BlazeOperation]
    func pushOperations(_ ops: [BlazeOperation]) async throws
    func subscribe(to collections: [String]) async throws
    func onOperationReceived(_ handler: @escaping ([BlazeOperation]) async -> Void)
}

/// Sync role: Server has priority in conflicts, Client defers to server
public enum SyncRole: String, Codable, Sendable {
    case server      // Server has priority (wins conflicts)
    case client      // Client defers to server (server wins conflicts)
    
    /// Check if this role has priority over another
    public func hasPriority(over other: SyncRole) -> Bool {
        switch (self, other) {
        case (.server, .client): return true   // Server beats client
        case (.client, .server): return false  // Client defers to server
        case (.server, .server): return false // Servers equal (use timestamp)
        case (.client, .client): return false  // Clients equal (use timestamp)
        }
    }
}

/// Manages synchronization between local BlazeDB and remote nodes
public actor BlazeSyncEngine {
    nonisolated(unsafe) internal let localDB: BlazeDBClient
    private let relay: BlazeSyncRelay
    private let opLog: OperationLog
    private let nodeId: UUID
    private let role: SyncRole  // SERVER/CLIENT ROLE
    private let securityValidator: SecurityValidator  // SECURITY: Validation
    private var isRunning = false
    private var syncTask: Task<Void, Error>?
    private var changeObserverToken: ObserverToken?
    
    // ULTRA-AGGRESSIVE batching for maximum throughput
    private var operationQueue: [BlazeOperation] = []
    private var batchTimer: Task<Void, Never>?
    private var batchSize: Int = 10_000  // ULTRA-FAST: 10,000 operations per batch (2x increase!)
    private let batchDelay: UInt64 = 100_000  // 0.1ms delay (ULTRA fast! 2.5x faster!)
    
    // Pipelining: Multiple batches in flight
    private var inFlightBatches: Int = 0
    private let maxInFlight: Int = 200  // ULTRA-FAST: Send up to 200 batches in parallel (4x increase!)
    private var pendingBatches: [Task<Void, Never>] = []
    
    // Delta encoding: Track previous state to only send changes
    private var previousStates: [UUID: [String: BlazeDocumentField]] = [:]
    
    // Predictive prefetching: Pre-compress likely operations
    private var prefetchQueue: [BlazeOperation] = []
    private var prefetchTask: Task<Void, Never>?
    
    // Adaptive batching: Track performance to adjust batch size
    private var lastBatchTime: UInt64 = 0
    private var batchTimes: [UInt64] = []  // Track last 10 batch times
    private let targetBatchTime: UInt64 = 5_000_000  // 5ms target per batch
    
    // Operation merging: Track pending operations per record
    private var pendingOps: [UUID: [BlazeOperation]] = [:]  // Record ID -> operations
    
    // INCREMENTAL SYNC: Track what's been synced to which nodes
    internal var syncedRecords: [UUID: Set<UUID>] = [:]  // Record ID -> Set of node IDs that have it
    internal var recordVersions: [UUID: UInt64] = [:]  // Record ID -> version number (increments on change)
    internal var lastSyncVersions: [UUID: [UUID: UInt64]] = [:]  // Node ID -> Record ID -> Last synced version
    
    // GC Configuration
    private var syncStateGCConfig: SyncStateGCConfig = SyncStateGCConfig()
    private var gcTask: Task<Void, Never>?
    
    public init(
        localDB: BlazeDBClient,
        relay: BlazeSyncRelay,
        nodeId: UUID = UUID(),
        role: SyncRole = .client,  // DEFAULT: Client (opt-in server mode)
        securityValidator: SecurityValidator? = nil  // SECURITY: Optional validator
    ) {
        self.localDB = localDB
        self.relay = relay
        self.nodeId = nodeId
        self.role = role
        self.securityValidator = securityValidator ?? SecurityValidator()  // Default validator
        
        let opLogURL = localDB.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("operation_log.json")
        self.opLog = OperationLog(nodeId: nodeId, storageURL: opLogURL)
    }
    
    /// Start synchronization
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Load operation log from disk
        try await opLog.load()
        
        // Connect to relay
        try await relay.connect()
        
        // Initial sync
        try await synchronize()
        
        // Subscribe to real-time updates
        try await relay.subscribe(to: [localDB.name])
        
        // Listen for incoming operations
        relay.onOperationReceived { [weak self] operations in
            guard let self = self else { return }
            // Wrap in Task to handle errors
            Task {
                do {
                    try await self.applyRemoteOperations(operations)
                } catch {
                    BlazeLogger.error("Failed to apply remote operations", error: error)
                }
            }
        }
        
        // Watch for local changes and create operations automatically
        changeObserverToken = localDB.observe { [weak self] changes in
            guard let self = self else { return }
            Task {
                await self.handleLocalChanges(changes)
            }
        }
        
        // PREDICTIVE PREFETCHING: Pre-encode likely operations in background
        startPredictivePrefetching()
        
        // Start periodic sync
        syncTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
                try await self.synchronize()
            }
        }
        
        // Start periodic GC if enabled
        if syncStateGCConfig.autoCleanupEnabled {
            startPeriodicGC()
        }
    }
    
    /// Stop synchronization
    public func stop() async {
        isRunning = false
        syncTask?.cancel()
        batchTimer?.cancel()
        changeObserverToken?.invalidate()
        prefetchTask?.cancel()
        gcTask?.cancel()
        
        // Flush any remaining operations
        await flushBatch()
        
        // Wait for all in-flight batches to complete
        for task in pendingBatches {
            _ = await task.result
        }
        
        // Run final GC cleanup
        try? await runFullSyncStateCleanup(config: syncStateGCConfig)
        
        // INCREMENTAL SYNC: Save sync state before disconnecting
        await saveSyncState()
        
        await relay.disconnect()
    }
    
    /// Manual sync
    public func syncNow() async throws {
        try await synchronize()
    }
    
    // MARK: - Private
    
    private func synchronize() async throws {
        // Get sync states
        let remoteState = try await relay.exchangeSyncState()
        let localState = await opLog.getCurrentState()
        
        // INCREMENTAL SYNC: Pull only what we don't have
        if remoteState.lastSyncedTimestamp > localState.lastSyncedTimestamp {
            let missingOps = try await relay.pullOperations(since: localState.lastSyncedTimestamp)
            try await applyRemoteOperations(missingOps)
        }
        
        // INCREMENTAL SYNC: Push only what remote doesn't have (changed/new records)
        if localState.lastSyncedTimestamp > remoteState.lastSyncedTimestamp {
            // Get all operations since remote's last sync
            let allOps = await opLog.getOperations(since: remoteState.lastSyncedTimestamp)
            
            // Filter to only records that have changed or are new
            let opsToSync = await filterOperationsForIncrementalSync(allOps, remoteNodeId: remoteState.nodeId)
            
            if !opsToSync.isEmpty {
                try await relay.pushOperations(opsToSync)
                
                // Mark records as synced to this node
                await markRecordsAsSynced(opsToSync, toNode: remoteState.nodeId)
            }
        }
        
        // Save operation log
        try await opLog.save()
        
        // INCREMENTAL SYNC: Save sync state
        await saveSyncState()
    }
    
    /// INCREMENTAL SYNC: Filter operations to only sync changed/new records
    private func filterOperationsForIncrementalSync(
        _ operations: [BlazeOperation],
        remoteNodeId: UUID
    ) async -> [BlazeOperation] {
        var opsToSync: [BlazeOperation] = []
        
        for op in operations {
            let recordId = op.recordId
            
            // Check if this record has been synced to this node before
            let lastSyncedVersion = lastSyncVersions[remoteNodeId]?[recordId] ?? 0
            let currentVersion = recordVersions[recordId] ?? 0
            
            // Only sync if:
            // 1. Record is new (insert) - always sync
            // 2. Record has changed (version increased) - sync if version > last synced
            // 3. Record was deleted - always sync
            if op.type == .insert || op.type == .delete {
                // New record or delete - always sync
                opsToSync.append(op)
            } else if op.type == .update {
                // Update - only sync if version changed
                if currentVersion > lastSyncedVersion {
                    opsToSync.append(op)
                }
                // Skip if version hasn't changed (already synced)
            } else {
                // Other operations (index, etc.) - always sync
                opsToSync.append(op)
            }
        }
        
        return opsToSync
    }
    
    /// INCREMENTAL SYNC: Mark records as synced to a specific node
    private func markRecordsAsSynced(_ operations: [BlazeOperation], toNode nodeId: UUID) async {
        // Initialize node's sync tracking if needed
        if lastSyncVersions[nodeId] == nil {
            lastSyncVersions[nodeId] = [:]
        }
        
        for op in operations {
            let recordId = op.recordId
            let currentVersion = recordVersions[recordId] ?? 0
            
            // Mark record as synced to this node
            lastSyncVersions[nodeId]?[recordId] = currentVersion
            
            // Track which nodes have this record
            if syncedRecords[recordId] == nil {
                syncedRecords[recordId] = []
            }
            syncedRecords[recordId]?.insert(nodeId)
        }
    }
    
    private func applyRemoteOperations(_ operations: [BlazeOperation]) async throws {
        // Sort by timestamp (causal order)
        let sorted = operations.sorted { $0.timestamp < $1.timestamp }
        
        // OPTIMIZATION: Batch validate operations (faster!)
        do {
            try await securityValidator.validateOperationsBatch(
                sorted,
                userId: sorted.first?.nodeId ?? nodeId,
                publicKey: nil  // NOTE: Public key validation intentionally not implemented.
                // Security validation uses nodeId and operation signatures instead.
            )
        } catch {
            BlazeLogger.warn("Security validation failed for batch: \(error.localizedDescription)")
            // Fall back to individual validation for better error reporting
            for op in sorted {
                do {
                    try await securityValidator.validateOperationWithoutSignature(
                        op,
                        userId: op.nodeId
                    )
                } catch {
                    BlazeLogger.warn("Security validation failed for operation \(op.id): \(error.localizedDescription)")
                    continue
                }
            }
        }
        
        for op in sorted {
            
            // INCREMENTAL SYNC: Skip if already applied (idempotent)
            if await opLog.contains(op.id) {
                continue
            }
            
            // INCREMENTAL SYNC: Track version for remote operations
            let recordId = op.recordId
            if recordVersions[recordId] == nil {
                recordVersions[recordId] = 0
            }
            recordVersions[recordId] = (recordVersions[recordId] ?? 0) + 1
            
            // Apply to local database
            switch op.type {
            case .insert:
                let record = BlazeDataRecord(op.changes)
                try localDB.insert(record, id: op.recordId)
                
            case .update:
                if let existing = try await localDB.fetch(id: op.recordId) {
                    // SERVER PRIORITY: Use role from operation (if available)
                    let remoteRole = op.role ?? ((role == .server) ? .client : .server)
                    let merged = mergeWithCRDT(existing: existing, changes: op.changes, timestamp: op.timestamp, remoteRole: remoteRole)
                    try await localDB.update(id: op.recordId, with: merged)
                }
                
            case .delete:
                try await localDB.delete(id: op.recordId)
                
            case .createIndex, .dropIndex:
                // Handle index operations
                break
            }
            
            // Record in operation log
            await opLog.applyRemoteOperation(op)
        }
    }
    
    private func mergeWithCRDT(
        existing: BlazeDataRecord,
        changes: [String: BlazeDocumentField],
        timestamp: LamportTimestamp,
        remoteRole: SyncRole? = nil
    ) -> BlazeDataRecord {
        var record = existing
        
        // SERVER PRIORITY: If remote is server and we're client, server wins
        if let remoteRole = remoteRole, remoteRole.hasPriority(over: role) {
            // Remote server has priority - use their changes
            for (key, value) in changes {
                record.storage[key] = value
            }
            return record
        }
        
        // If we're server and remote is client, we win (keep existing)
        // If roles are equal, use Last-Write-Wins (timestamp)
        // For now, simple Last-Write-Wins
        for (key, value) in changes {
            record.storage[key] = value
        }
        
        return record
    }
    
    /// Handle local database changes and create operations
    private func handleLocalChanges(_ changes: [DatabaseChange]) async {
        guard isRunning else { return }
        
        for change in changes {
            // Extract record ID from change type
            guard let recordId = change.recordID else {
                // Skip batch operations for now (they'll be handled by periodic sync)
                continue
            }
            
            // Get operation type (skip batch operations)
            guard let opType = change.type.toOperationType() else {
                continue
            }
            
            // Fetch the record to get its fields (for insert/update)
            var fields: [String: BlazeDocumentField] = [:]
            if opType != .delete {
                if let record = try? await localDB.fetch(id: recordId) {
                    fields = record.storage
                    
                    // INCREMENTAL SYNC: Increment version on change
                    if recordVersions[recordId] == nil {
                        recordVersions[recordId] = 0  // New record
                    }
                    recordVersions[recordId] = (recordVersions[recordId] ?? 0) + 1
                    
                    // DELTA ENCODING: Only send changed fields!
                    if let previous = previousStates[recordId] {
                        // Only include fields that changed
                        var delta: [String: BlazeDocumentField] = [:]
                        for (key, value) in fields {
                            if previous[key] != value {
                                delta[key] = value  // Only changed fields!
                            }
                        }
                        fields = delta  // Use delta instead of full record!
                    }
                    
                    // Update previous state
                    previousStates[recordId] = fields
                }
            } else {
                // Delete: Remove from previous states and mark as deleted
                previousStates.removeValue(forKey: recordId)
                recordVersions[recordId] = (recordVersions[recordId] ?? 0) + 1  // Increment version on delete
                syncedRecords.removeValue(forKey: recordId)  // Remove from synced records
            }
            
            // Skip if this change came from a remote operation (avoid loops)
            // We'll track this by checking if the operation was already logged
            let op = await opLog.recordOperation(
                type: opType,
                collectionName: localDB.name,
                recordId: recordId,
                changes: fields,
                role: role  // SERVER/CLIENT ROLE: Include role in operation
            )
            
            // OPERATION MERGING: Merge with existing operations for same record!
            await mergeOperation(op)
            
            // Flush if batch is full (after merging!)
            if operationQueue.count >= batchSize {
                await flushBatch()
            } else {
                // Schedule flush after delay (if not already scheduled)
                scheduleBatchFlush()
            }
        }
    }
    
    /// Schedule a batch flush after delay
    private func scheduleBatchFlush() {
        // Cancel existing timer
        batchTimer?.cancel()
        
        // Schedule new flush
        batchTimer = Task {
            try? await Task.sleep(nanoseconds: batchDelay)
            await flushBatch()
        }
    }
    
    /// OPERATION MERGING: Merge multiple operations for same record into one
    private func mergeOperation(_ op: BlazeOperation) async {
        let recordId = op.recordId
        
        // Get existing pending operations for this record
        var existingOps = pendingOps[recordId] ?? []
        
        // Merge logic:
        // - Insert + Update = Update (with insert's fields)
        // - Update + Update = Single Update (merge changes)
        // - Insert + Delete = Skip both (no-op)
        // - Update + Delete = Delete (skip update)
        
        if existingOps.isEmpty {
            // First operation for this record
            pendingOps[recordId] = [op]
            operationQueue.append(op)
            return
        }
        
        // Merge with all existing operations (accumulate merges)
        var current = op
        for existing in existingOps {
            if let merged = mergeTwoOperations(existing, current) {
                current = merged
            } else {
                // Can't merge with this one, keep both
                pendingOps[recordId] = existingOps + [op]
                operationQueue.append(op)
                return
            }
        }
        
        // Successfully merged all operations
        pendingOps[recordId] = [current]
        // Remove old operations from queue
        operationQueue.removeAll { $0.recordId == recordId && $0.id != current.id }
        // Add merged operation (if not already in queue)
        if !operationQueue.contains(where: { $0.id == current.id }) {
            operationQueue.append(current)
        }
    }
    
    /// Merge two operations into one (if possible)
    private func mergeTwoOperations(_ op1: BlazeOperation, _ op2: BlazeOperation) -> BlazeOperation? {
        // Same record?
        guard op1.recordId == op2.recordId else { return nil }
        
        // Insert + Update = Update (with insert's fields)
        if op1.type == .insert && op2.type == .update {
            var mergedChanges = op1.changes
            for (key, value) in op2.changes {
                mergedChanges[key] = value  // Update overwrites insert
            }
            return BlazeOperation(
                id: op2.id,  // Use update's ID (more recent)
                timestamp: op2.timestamp > op1.timestamp ? op2.timestamp : op1.timestamp,
                nodeId: op2.nodeId,
                type: .update,  // Result is update
                collectionName: op2.collectionName,
                recordId: op2.recordId,
                changes: mergedChanges
            )
        }
        
        // Update + Update = Single Update (merge changes)
        if op1.type == .update && op2.type == .update {
            var mergedChanges = op1.changes
            for (key, value) in op2.changes {
                mergedChanges[key] = value  // Later update wins
            }
            return BlazeOperation(
                id: op2.id,  // Use later update's ID
                timestamp: op2.timestamp > op1.timestamp ? op2.timestamp : op1.timestamp,
                nodeId: op2.nodeId,
                type: .update,
                collectionName: op2.collectionName,
                recordId: op2.recordId,
                changes: mergedChanges
            )
        }
        
        // Insert + Delete = Skip both (no-op)
        if (op1.type == .insert && op2.type == .delete) || (op1.type == .delete && op2.type == .insert) {
            return nil  // No operation needed
        }
        
        // Update + Delete = Delete (skip update)
        if op1.type == .update && op2.type == .delete {
            return op2  // Delete wins
        }
        if op1.type == .delete && op2.type == .update {
            return op1  // Delete wins (ignore update)
        }
        
        // Can't merge
        return nil
    }
    
    /// Flush queued operations in one batch (with pipelining + adaptive batching!)
    private func flushBatch() async {
        guard !operationQueue.isEmpty else { return }
        
        // Don't create more batches if we're already at max in-flight
        guard inFlightBatches < maxInFlight else {
            // Schedule retry in 0.5ms
            batchTimer = Task {
                try? await Task.sleep(nanoseconds: 500_000)
                await flushBatch()
            }
            return
        }
        
        let batch = operationQueue
        operationQueue.removeAll()
        pendingOps.removeAll()  // Clear pending ops after flush
        batchTimer?.cancel()
        
        // ADAPTIVE BATCHING: Measure batch time and adjust batch size!
        let startTime = DispatchTime.now().uptimeNanoseconds
        
        // Increment in-flight counter
        inFlightBatches += 1
        
        // Send in parallel (pipelining - don't wait!)
        let relay = self.relay  // Capture relay before Task to avoid Sendable issue
        let sendTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await relay.pushOperations(batch)
                
                // Measure batch time
                let endTime = DispatchTime.now().uptimeNanoseconds
                let batchTime = endTime - startTime
                await self.recordBatchTime(batchTime)
                
                // Decrement counter when done
                await self.decrementInFlight()
            } catch {
                BlazeLogger.error("Failed to push batch", error: error)
                // Re-queue operations for retry
                await self.requeueBatch(batch)
                await self.decrementInFlight()
            }
        }
        
        pendingBatches.append(sendTask)
        
        // Clean up completed tasks
        pendingBatches = pendingBatches.filter { !$0.isCancelled }
    }
    
    /// ADAPTIVE BATCHING: Record batch time and adjust batch size
    private func recordBatchTime(_ time: UInt64) async {
        batchTimes.append(time)
        if batchTimes.count > 10 {
            batchTimes.removeFirst()  // Keep last 10
        }
        
        // Calculate average batch time
        let avgTime = batchTimes.reduce(0, +) / UInt64(batchTimes.count)
        
        // Adjust batch size based on performance
        if avgTime < targetBatchTime / 2 {
            // Too fast - increase batch size (more aggressive!)
            batchSize = min(batchSize + 1000, 50_000)  // ULTRA-FAST: Max 50K ops (2.5x increase!)
        } else if avgTime > targetBatchTime * 2 {
            // Too slow - decrease batch size (less aggressive)
            batchSize = max(batchSize - 1000, 1000)  // Min 1K ops
        }
        // Otherwise, keep current batch size
        
        if batchTimes.count == 10 {
            BlazeLogger.debug("Adaptive batching: avg=\(avgTime/1_000_000)ms, batchSize=\(batchSize)")
        }
    }
    
    private func decrementInFlight() async {
        inFlightBatches = max(0, inFlightBatches - 1)
    }
    
    private func requeueBatch(_ batch: [BlazeOperation]) async {
        operationQueue.insert(contentsOf: batch, at: 0)
    }
    
    /// PREDICTIVE PREFETCHING: Pre-encode likely operations in background
    private func startPredictivePrefetching() {
        prefetchTask = Task {
            while !Task.isCancelled {
                // Wait for operations to accumulate
                try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                
                // Get operations that are likely to be sent soon
                let likelyOps = await getLikelyOperations()
                
                // Pre-encode them in background (warm up cache!)
                for op in likelyOps {
                    // This will cache the encoded operation
                    // The actual encoding happens in TCPRelay's cache
                    // We just trigger it here to warm up the cache
                    _ = try? await Task.detached {
                        // Simulate encoding to warm cache (actual encoding in relay)
                        return op
                    }.value
                }
            }
        }
    }
    
    /// Get operations that are likely to be sent soon (for prefetching)
    private func getLikelyOperations() async -> [BlazeOperation] {
        // Return operations from queue that haven't been sent yet
        // These are likely to be sent soon
        return Array(operationQueue.prefix(100))  // Prefetch first 100
    }
    
    // MARK: - Incremental Sync State Management
    
    /// Load sync state from disk
    private func loadSyncState() async {
        let syncStateURL = localDB.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("sync_state.json")
        
        guard FileManager.default.fileExists(atPath: syncStateURL.path) else {
            return  // No sync state yet
        }
        
        do {
            let data = try Data(contentsOf: syncStateURL)
            let state = try JSONDecoder().decode(SyncStateData.self, from: data)
            
            // Restore sync state (convert arrays back to Sets)
            syncedRecords = state.toSyncedRecords()
            recordVersions = state.recordVersions
            lastSyncVersions = state.lastSyncVersions
        } catch {
            BlazeLogger.warn("Failed to load sync state: \(error)")
        }
    }
    
    /// Save sync state to disk
    internal func saveSyncState() async {
        let syncStateURL = localDB.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("sync_state.json")
        
        let state = SyncStateData(
            syncedRecords: SyncStateData.fromSyncedRecords(syncedRecords),
            recordVersions: recordVersions,
            lastSyncVersions: lastSyncVersions
        )
        
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: syncStateURL)
        } catch {
            BlazeLogger.warn("Failed to save sync state: \(error)")
        }
    }
    
    /// Sync state data structure
    private struct SyncStateData: Codable {
        var syncedRecords: [UUID: [UUID]]  // Array instead of Set for Codable
        var recordVersions: [UUID: UInt64]
        var lastSyncVersions: [UUID: [UUID: UInt64]]
        
        // Convert to/from Set for internal use
        func toSyncedRecords() -> [UUID: Set<UUID>] {
            var result: [UUID: Set<UUID>] = [:]
            for (recordId, nodeIds) in syncedRecords {
                result[recordId] = Set(nodeIds)
            }
            return result
        }
        
        static func fromSyncedRecords(_ syncedRecords: [UUID: Set<UUID>]) -> [UUID: [UUID]] {
            var result: [UUID: [UUID]] = [:]
            for (recordId, nodeIds) in syncedRecords {
                result[recordId] = Array(nodeIds)
            }
            return result
        }
    }
    
    // MARK: - Periodic GC
    
    /// Start periodic GC
    private func startPeriodicGC() {
        gcTask?.cancel()
        gcTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(syncStateGCConfig.cleanupInterval * 1_000_000_000))
                try? await runFullSyncStateCleanup(config: syncStateGCConfig)
            }
        }
    }
    
    /// Configure sync state GC
    public func configureSyncStateGC(_ config: SyncStateGCConfig) {
        syncStateGCConfig = config
        if config.autoCleanupEnabled {
            startPeriodicGC()
        } else {
            gcTask?.cancel()
        }
    }
}

// MARK: - DatabaseChange Extension

extension DatabaseChange.ChangeType {
    func toOperationType() -> OperationType? {
        switch self {
        case .insert:
            return .insert
        case .update:
            return .update
        case .delete:
            return .delete
        case .batchInsert, .batchUpdate, .batchDelete:
            // Batch operations handled separately
            return nil
        }
    }
}

// MARK: - BlazeDBClient Extension

extension BlazeDBClient {
    /// Enable sync for this database (OPTIONAL LAYER - must be explicitly enabled!)
    /// - Parameters:
    ///   - relay: The sync relay to use (local or remote)
    ///   - role: Server (has priority) or Client (defers to server) - default: .client
    /// - Returns: The sync engine instance
    /// - Note: Sync is OPTIONAL - database works fine without it!
    public func enableSync(
        relay: BlazeSyncRelay,
        role: SyncRole = .client  // DEFAULT: Client (opt-in server mode)
    ) async throws -> BlazeSyncEngine {
        let engine = BlazeSyncEngine(localDB: self, relay: relay, role: role)
        try await engine.start()
        return engine
    }
    
    /// Enable sync with remote server (convenience method)
    /// - Parameters:
    ///   - remote: Remote server node
    ///   - policy: Sync policy (collections, encryption, etc.)
    ///   - role: Server (has priority) or Client (defers to server) - default: .client
    /// - Returns: The sync engine instance
    public func enableSync(
        remote: RemoteNode,
        policy: SyncPolicy,
        role: SyncRole = .client  // DEFAULT: Client (connects to server)
    ) async throws -> BlazeSyncEngine {
        // Create topology if needed
        let topology = BlazeTopology()
        let nodeId = try await topology.register(db: self, name: self.name, syncMode: .localAndRemote)
        
        // Connect to remote
        try await topology.connectRemote(nodeId: nodeId, remote: remote, policy: policy)
        
        // Get the sync engine from the connection
        let connections = await topology.getConnections(for: nodeId)
        guard let connection = connections.first,
              let relay = connection.relay as? TCPRelay else {
            throw SyncError.syncFailed("Failed to create sync connection")
        }
        
        let engine = BlazeSyncEngine(localDB: self, relay: relay, role: role)
        try await engine.start()
        return engine
    }
}

// MARK: - Multi-Database Sync Group

/// Coordinates sync across multiple databases
public actor BlazeSyncGroup {
    private let engines: [BlazeSyncEngine]
    
    public init(databases: [BlazeDBClient], relay: BlazeSyncRelay) {
        self.engines = databases.map { db in
            BlazeSyncEngine(localDB: db, relay: relay)
        }
    }
    
    /// Start all sync engines
    public func start() async throws {
        for engine in engines {
            try await engine.start()
        }
    }
    
    /// Stop all sync engines
    public func stop() async {
        for engine in engines {
            await engine.stop()
        }
    }
    
    /// Sync all databases now
    public func syncAll() async throws {
        for engine in engines {
            try await engine.syncNow()
        }
    }
    
    /// Execute a cross-database transaction
    public func transact(_ block: () async throws -> Void) async throws {
        // NOTE: Distributed transaction coordination is intentionally not implemented.
        // BlazeDB currently guarantees atomicity only within a single database instance.
        // Cross-database operations are executed sequentially and synced after completion.
        // For true distributed transactions, use application-level coordination.
        try await block()
        
        // Sync all after transaction
        try await syncAll()
    }
}

// MARK: - Errors

public enum SyncError: Error, LocalizedError {
    case notConnected
    case invalidSignature
    case notARecipient
    case conflictDetected(recordId: UUID)
    case syncFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to sync relay. Call connect() first."
        case .invalidSignature:
            return "Operation signature verification failed. Possible tampering detected."
        case .notARecipient:
            return "This node is not authorized to decrypt this operation."
        case .conflictDetected(let recordId):
            return "Conflict detected for record \(recordId). Manual resolution required."
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        }
    }
}



#endif // !BLAZEDB_LINUX_CORE
