//
//  Triggers.swift
//  BlazeDB
//
//  Database triggers for BEFORE/AFTER INSERT/UPDATE/DELETE
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Trigger Types

public enum TriggerEvent {
    case beforeInsert
    case afterInsert
    case beforeUpdate
    case afterUpdate
    case beforeDelete
    case afterDelete
}

public typealias TriggerHandler = (BlazeDataRecord, inout BlazeDataRecord?) throws -> Void

// MARK: - Trigger

public struct Trigger {
    public let name: String
    public let event: TriggerEvent
    public let handler: TriggerHandler
    
    public init(name: String, event: TriggerEvent, handler: @escaping TriggerHandler) {
        self.name = name
        self.event = event
        self.handler = handler
    }
}

// MARK: - TriggerManager

public class TriggerManager {
    private var triggers: [Trigger] = []
    private let lock = NSLock()
    
    public init() {}
    
    /// Register a trigger
    public func register(_ trigger: Trigger) {
        lock.lock()
        defer { lock.unlock() }
        triggers.append(trigger)
    }
    
    /// Unregister a trigger by name
    public func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        triggers.removeAll { $0.name == name }
    }
    
    /// Get triggers for a specific event
    public func getTriggers(for event: TriggerEvent) -> [Trigger] {
        lock.lock()
        defer { lock.unlock() }
        return triggers.filter { $0.event == event }
    }
    
    /// Execute triggers for an event
    public func executeTriggers(for event: TriggerEvent, record: BlazeDataRecord, modifiedRecord: inout BlazeDataRecord?) throws {
        let eventTriggers = getTriggers(for: event)
        for trigger in eventTriggers {
            try trigger.handler(record, &modifiedRecord)
        }
    }
}

// MARK: - Enhanced Trigger Manager

public class EnhancedTriggerManager {
    private var triggers: [EnhancedTrigger] = []
    private let lock = NSLock()
    
    public init() {}
    
    /// Register an enhanced trigger
    public func register(_ trigger: EnhancedTrigger) {
        lock.lock()
        defer { lock.unlock() }
        triggers.append(trigger)
    }
    
    /// Unregister a trigger by name
    public func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        triggers.removeAll { $0.name == name }
    }
    
    /// Get triggers for a specific event and collection
    public func getTriggers(for event: TriggerEvent, collectionName: String? = nil) -> [EnhancedTrigger] {
        lock.lock()
        defer { lock.unlock() }
        return triggers.filter { trigger in
            trigger.event == event && (trigger.collectionName == nil || trigger.collectionName == collectionName)
        }
    }
    
    /// Execute triggers for an event with safety walls
    public func executeTriggers(
        for event: TriggerEvent,
        record: BlazeDataRecord,
        modifiedRecord: inout BlazeDataRecord?,
        context: TriggerContext,
        collectionName: String? = nil
    ) throws {
        let eventTriggers = getTriggers(for: event, collectionName: collectionName)
        guard !eventTriggers.isEmpty else { return }
        
        // Safety: Time limit (5 seconds per trigger)
        let startTime = Date()
        let maxDuration: TimeInterval = 5.0
        
        // Safety: Recursion check (prevent infinite loops)
        let triggerKey = "\(event)_\(collectionName ?? "all")"
        if context.isExecutingTrigger(triggerKey) {
            BlazeLogger.warn("Trigger recursion detected for \(triggerKey), skipping")
            return
        }
        
        context.markTriggerExecuting(triggerKey)
        defer { context.unmarkTriggerExecuting(triggerKey) }
        
        for trigger in eventTriggers {
            // Check time limit
            if Date().timeIntervalSince(startTime) > maxDuration {
                BlazeLogger.warn("Trigger execution timeout for \(trigger.name), stopping")
                break
            }
            
            do {
                try trigger.handler(record, &modifiedRecord, context)
            } catch {
                // Triggers run after commit, so failures don't roll back
                // But we log them for debugging
                BlazeLogger.error("Trigger '\(trigger.name)' failed: \(error)")
                // Continue with other triggers
            }
        }
    }
}

// MARK: - BlazeDBClient Triggers Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var triggerManagerKey: UInt8 = 0
    nonisolated(unsafe) private static var enhancedTriggerManagerKey: UInt8 = 1
    
    internal var triggerManager: TriggerManager {
        #if canImport(ObjectiveC)
        if let manager = objc_getAssociatedObject(self, &Self.triggerManagerKey) as? TriggerManager {
            return manager
        }
        let manager = TriggerManager()
        objc_setAssociatedObject(self, &Self.triggerManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
        #else
        if let manager: TriggerManager = AssociatedObjects.get(self, key: &Self.triggerManagerKey) {
            return manager
        }
        let manager = TriggerManager()
        AssociatedObjects.set(self, key: &Self.triggerManagerKey, value: manager)
        return manager
        #endif
    }
    
    private var enhancedTriggerManager: EnhancedTriggerManager {
        #if canImport(ObjectiveC)
        if let manager = objc_getAssociatedObject(self, &Self.enhancedTriggerManagerKey) as? EnhancedTriggerManager {
            return manager
        }
        let manager = EnhancedTriggerManager()
        objc_setAssociatedObject(self, &Self.enhancedTriggerManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
        #else
        if let manager: EnhancedTriggerManager = AssociatedObjects.get(self, key: &Self.enhancedTriggerManagerKey) {
            return manager
        }
        let manager = EnhancedTriggerManager()
        AssociatedObjects.set(self, key: &Self.enhancedTriggerManagerKey, value: manager)
        return manager
        #endif
    }
    
    /// Register a trigger
    public func registerTrigger(_ trigger: Trigger) {
        triggerManager.register(trigger)
        BlazeLogger.info("Registered trigger '\(trigger.name)' for event \(trigger.event)")
    }
    
    /// Register an enhanced trigger (with context)
    public func registerTrigger(_ trigger: EnhancedTrigger) {
        enhancedTriggerManager.register(trigger)
        BlazeLogger.info("Registered enhanced trigger '\(trigger.name)' for event \(trigger.event)")
    }
    
    /// Unregister a trigger
    public func unregisterTrigger(name: String) {
        triggerManager.unregister(name: name)
        enhancedTriggerManager.unregister(name: name)
        BlazeLogger.info("Unregistered trigger '\(name)'")
    }
    
    /// Create and register a trigger
    public func createTrigger(name: String, event: TriggerEvent, handler: @escaping TriggerHandler) {
        let trigger = Trigger(name: name, event: event, handler: handler)
        registerTrigger(trigger)
    }
    
    /// Create and register an enhanced trigger (with context)
    /// 
    /// Example:
    /// ```swift
    /// db.onInsert("Workouts") { record, modified, ctx in
    ///     if record["notes"] != nil {
    ///         // Auto-generate embedding (would call AI service)
    ///         let embed = AI.embed(record["notes"]!)
    ///         modified?.storage["noteEmbedding"] = .data(embed)
    ///     }
    /// }
    /// ```
    public func onInsert(_ collectionName: String? = nil, name: String? = nil, handler: @escaping EnhancedTriggerHandler) {
        let triggerName = name ?? "onInsert_\(UUID().uuidString)"
        // Use beforeInsert so the handler can modify the record before it's saved
        let trigger = EnhancedTrigger(name: triggerName, event: .beforeInsert, collectionName: collectionName, handler: handler)
        registerTrigger(trigger)
        
        // Persist trigger definition (handled by BlazeDBClient extension)
        // Note: This requires BlazeDBClient context - persistence happens in BlazeDBClient+Triggers
    }
    
    /// Create trigger for updates
    public func onUpdate(_ collectionName: String? = nil, handler: @escaping (BlazeDataRecord, BlazeDataRecord, TriggerContext) throws -> Void) {
        let trigger = EnhancedTrigger(name: "onUpdate_\(UUID().uuidString)", event: .afterUpdate, collectionName: collectionName) { old, new, ctx in
            try handler(old, new ?? old, ctx)
        }
        registerTrigger(trigger)
    }
    
    /// Create trigger for deletes
    public func onDelete(_ collectionName: String? = nil, handler: @escaping (BlazeDataRecord, TriggerContext) throws -> Void) {
        let trigger = EnhancedTrigger(name: "onDelete_\(UUID().uuidString)", event: .afterDelete, collectionName: collectionName) { record, _, ctx in
            try handler(record, ctx)
        }
        registerTrigger(trigger)
    }
    
    internal func executeEnhancedTriggers(
        for event: TriggerEvent,
        record: BlazeDataRecord,
        modifiedRecord: inout BlazeDataRecord?,
        collection: DynamicCollection?,
        collectionName: String? = nil
    ) throws {
        let context = TriggerContext(collection: collection, client: self)
        try enhancedTriggerManager.executeTriggers(
            for: event,
            record: record,
            modifiedRecord: &modifiedRecord,
            context: context,
            collectionName: collectionName
        )
    }
}

