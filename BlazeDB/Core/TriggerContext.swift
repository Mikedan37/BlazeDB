//
//  TriggerContext.swift
//  BlazeDB
//
//  Enhanced trigger context with database operations
//  Like Firebase Functions but local and offline
//
import Foundation

/// Context provided to trigger handlers
/// Allows triggers to perform database operations
public class TriggerContext {
    private weak var collection: DynamicCollection?
    private weak var client: BlazeDBClient?
    private var executingTriggers: Set<String> = []
    private let lock = NSLock()
    
    internal init(collection: DynamicCollection?, client: BlazeDBClient?) {
        self.collection = collection
        self.client = client
    }
    
    /// Check if trigger is currently executing (recursion guard)
    internal func isExecutingTrigger(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return executingTriggers.contains(key)
    }
    
    /// Mark trigger as executing
    internal func markTriggerExecuting(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        executingTriggers.insert(key)
    }
    
    /// Unmark trigger as executing
    internal func unmarkTriggerExecuting(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        executingTriggers.remove(key)
    }
    
    /// The mutable record being modified (set by the trigger executor for BEFORE triggers)
    internal var pendingRecord: BlazeDataRecord?

    /// Update fields on the record being modified.
    /// Only works in BEFORE triggers. Merges the provided fields into the pending record.
    public func update(fields: [String: BlazeDocumentField]) {
        guard var record = pendingRecord else {
            BlazeLogger.warn("TriggerContext.update(fields:) called outside a BEFORE trigger; no record to modify")
            return
        }
        for (key, value) in fields {
            record.storage[key] = value
        }
        self.pendingRecord = record
    }
    
    /// Rebuild spatial index
    #if !BLAZEDB_LINUX_CORE
    public func rebuildSpatialIndex() throws {
        try client?.rebuildSpatialIndex()
    }
    #endif
    
    /// Rebalance ordering index
    /// - Note: Not yet implemented. Calling this method logs a warning and returns without effect.
    // TODO: Not yet implemented - requires OrderingIndex integration
    public func rebalanceOrderIndex() throws {
        BlazeLogger.warn("TriggerContext.rebalanceOrderIndex() is not yet implemented")
    }

    /// Update search index
    /// - Note: Not yet implemented. Calling this method logs a warning and returns without effect.
    // TODO: Not yet implemented - requires SearchIndex integration
    public func updateSearchIndex() throws {
        BlazeLogger.warn("TriggerContext.updateSearchIndex() is not yet implemented")
    }
    
    /// Insert a new record (for cascading inserts)
    public func insert(_ record: BlazeDataRecord) throws -> UUID {
        guard let client = client else {
            throw BlazeDBError.transactionFailed("Client not available in trigger context")
        }
        return try client.insert(record)
    }
    
    /// Update another record
    public func update(id: UUID, with fields: [String: BlazeDocumentField]) throws {
        guard let client = client else {
            throw BlazeDBError.transactionFailed("Client not available in trigger context")
        }
        try client.updateFields(id: id, fields: fields)
    }
    
    /// Delete another record
    public func delete(id: UUID) throws {
        guard let client = client else {
            throw BlazeDBError.transactionFailed("Client not available in trigger context")
        }
        try client.delete(id: id)
    }
}

/// Enhanced trigger handler with context
public typealias EnhancedTriggerHandler = (BlazeDataRecord, inout BlazeDataRecord?, TriggerContext) throws -> Void

/// Enhanced trigger with context support
public struct EnhancedTrigger {
    public let name: String
    public let event: TriggerEvent
    public let handler: EnhancedTriggerHandler
    public let collectionName: String?
    
    public init(name: String, event: TriggerEvent, collectionName: String? = nil, handler: @escaping EnhancedTriggerHandler) {
        self.name = name
        self.event = event
        self.collectionName = collectionName
        self.handler = handler
    }
}

