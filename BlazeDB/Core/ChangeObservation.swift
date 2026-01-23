//
//  ChangeObservation.swift
//  BlazeDB
//
//  Real-time change observation and notifications
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Database Change Types

/// Represents a change to the database
public struct DatabaseChange {
    public enum ChangeType {
        case insert(UUID)
        case update(UUID)
        case delete(UUID)
        case batchInsert(count: Int)
        case batchUpdate(count: Int)
        case batchDelete(count: Int)
    }
    
    public let type: ChangeType
    public let collectionName: String?
    public let timestamp: Date
    public let recordID: UUID?
    
    public init(type: ChangeType, collectionName: String? = nil, timestamp: Date = Date()) {
        self.type = type
        self.collectionName = collectionName
        self.timestamp = timestamp
        
        // Extract record ID from change type
        switch type {
        case .insert(let id), .update(let id), .delete(let id):
            self.recordID = id
        default:
            self.recordID = nil
        }
    }
}

// MARK: - Observer Closure Type

public typealias ChangeObserver = @Sendable ([DatabaseChange]) -> Void

// MARK: - Observer Token

/// Token representing an active observer registration
/// Automatically unregisters when deallocated
public final class ObserverToken {
    private let id: UUID
    private let unregister: (UUID) -> Void
    
    init(id: UUID, unregister: @escaping (UUID) -> Void) {
        self.id = id
        self.unregister = unregister
    }
    
    deinit {
        unregister(id)
    }
    
    public func invalidate() {
        unregister(id)
    }
}

// MARK: - Change Notification Manager

/// Internal class managing change observers
/// Thread-safe: Uses NSLock for synchronization (legacy pattern, acceptable for notification system)
internal final class ChangeNotificationManager: @unchecked Sendable {
    
    private var observers: [UUID: ChangeObserver] = [:]
    private let lock = NSLock()
    private var pendingChanges: [DatabaseChange] = []
    private var batchNotificationTimer: Timer?
    private let batchDelay: TimeInterval = 0.05  // 50ms batching
    
    /// Thread-safe singleton (caller must ensure thread safety)
    nonisolated(unsafe) static let shared = ChangeNotificationManager()
    
    private init() {}
    
    /// Register an observer
    func registerObserver(_ observer: @escaping ChangeObserver) -> UUID {
        let id = UUID()
        
        lock.lock()
        observers[id] = observer
        lock.unlock()
        
        BlazeLogger.debug("Observer registered: \(id)")
        return id
    }
    
    /// Unregister an observer
    func unregisterObserver(id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
        
        BlazeLogger.debug("Observer unregistered: \(id)")
    }
    
    /// Notify observers of changes (batched for performance)
    func notifyChanges(_ changes: [DatabaseChange]) {
        guard !changes.isEmpty else { return }
        
        lock.lock()
        pendingChanges.append(contentsOf: changes)
        
        // Schedule batch notification if not already scheduled
        if batchNotificationTimer == nil {
            let manager = self
            batchNotificationTimer = Timer.scheduledTimer(
                withTimeInterval: batchDelay,
                repeats: false
            ) { _ in
                manager.flushPendingChanges()
            }
        }
        lock.unlock()
    }
    
    /// Immediately flush pending changes to observers
    private func flushPendingChanges() {
        lock.lock()
        let changesToNotify = pendingChanges
        let currentObservers = observers
        pendingChanges.removeAll()
        batchNotificationTimer = nil
        lock.unlock()
        
        guard !changesToNotify.isEmpty && !currentObservers.isEmpty else { return }
        
        BlazeLogger.trace("Notifying \(currentObservers.count) observers of \(changesToNotify.count) changes")
        
        // Copy observers to avoid data race
        let observersCopy = Array(currentObservers.values)
        let changesCopy = changesToNotify
        
        // Notify on main thread for UI safety
        DispatchQueue.main.async {
            for observer in observersCopy {
                observer(changesCopy)
            }
        }
    }
    
    /// Get observer count (for testing)
    var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }
}

// MARK: - BlazeDBClient Observation Extension

extension BlazeDBClient {
    
    // MARK: - Public Observation API
    
    /// Observe all changes to the database
    ///
    /// Receives notifications when records are inserted, updated, or deleted.
    /// Observer runs on the main thread for safe UI updates.
    ///
    /// - Parameter observer: Closure called when changes occur
    /// - Returns: Token to manage observer lifetime
    ///
    /// ## Example
    /// ```swift
    /// let token = db.observe { changes in
    ///     for change in changes {
    ///         switch change.type {
    ///         case .insert(let id):
    ///             print("New record: \(id)")
    ///             refreshUI()
    ///         case .update(let id):
    ///             print("Updated: \(id)")
    ///             refreshUI()
    ///         case .delete(let id):
    ///             print("Deleted: \(id)")
    ///             refreshUI()
    ///         default:
    ///             break
    ///         }
    ///     }
    /// }
    /// // Observer automatically unregisters when token is deallocated
    /// ```
    ///
    /// ## SwiftUI Example
    /// ```swift
    /// struct BugListView: View {
    ///     @State private var bugs: [BlazeDataRecord] = []
    ///     @State private var observerToken: ObserverToken?
    ///
    ///     var body: some View {
    ///         List(bugs) { bug in
    ///             BugRow(bug: bug)
    ///         }
    ///         .onAppear {
    ///             observerToken = db.observe { _ in
    ///                 bugs = try? db.fetchAll() ?? []
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    @discardableResult
    public func observe(_ observer: @escaping ChangeObserver) -> ObserverToken {
        let id = ChangeNotificationManager.shared.registerObserver(observer)
        
        BlazeLogger.info("📡 Database observer registered")
        
        return ObserverToken(id: id) { id in
            ChangeNotificationManager.shared.unregisterObserver(id: id)
            BlazeLogger.info("📡 Database observer unregistered")
        }
    }
    
    /// Observe specific queries (filtered changes)
    ///
    /// Only notifies when changes affect records matching the predicate.
    ///
    /// - Parameters:
    ///   - predicate: Filter for relevant changes
    ///   - observer: Closure called when matching changes occur
    /// - Returns: Token to manage observer lifetime
    ///
    /// ## Example
    /// ```swift
    /// // Only observe high-priority bugs
    /// let token = db.observe(
    ///     where: { $0.storage["priority"]?.intValue == 5 },
    ///     changes: { changes in
    ///         print("High-priority bug changed!")
    ///     }
    /// )
    /// ```
    @discardableResult
    public func observe(
        where predicate: @escaping @Sendable (BlazeDataRecord) -> Bool,
        changes observer: @escaping ChangeObserver
    ) -> ObserverToken {
        // Filtered observer: only notify if change matches predicate
        let filteredObserver: ChangeObserver = { [weak self] changes in
            guard let self = self else { return }
            
            var relevantChanges: [DatabaseChange] = []
            
            for change in changes {
                // Check if this change affects matching records
                if case .insert(let id) = change.type,
                   let record = try? self.fetch(id: id),
                   predicate(record) {
                    relevantChanges.append(change)
                }
                else if case .update(let id) = change.type,
                        let record = try? self.fetch(id: id),
                        predicate(record) {
                    relevantChanges.append(change)
                }
                else if case .delete(let id) = change.type {
                    // Can't check deleted record, include all deletes
                    relevantChanges.append(change)
                }
            }
            
            if !relevantChanges.isEmpty {
                observer(relevantChanges)
            }
        }
        
        let id = ChangeNotificationManager.shared.registerObserver(filteredObserver)
        
        BlazeLogger.info("📡 Filtered database observer registered")
        
        return ObserverToken(id: id) { id in
            ChangeNotificationManager.shared.unregisterObserver(id: id)
        }
    }
    
    // MARK: - Internal Notification Methods
    
    /// Notify observers of a single insert
    internal func notifyInsert(id: UUID) {
        ChangeNotificationManager.shared.notifyChanges([
            DatabaseChange(type: .insert(id), collectionName: name)
        ])
    }
    
    /// Notify observers of a single update
    internal func notifyUpdate(id: UUID) {
        ChangeNotificationManager.shared.notifyChanges([
            DatabaseChange(type: .update(id), collectionName: name)
        ])
    }
    
    /// Notify observers of a single delete
    internal func notifyDelete(id: UUID) {
        ChangeNotificationManager.shared.notifyChanges([
            DatabaseChange(type: .delete(id), collectionName: name)
        ])
    }
    
    /// Notify observers of batch changes
    internal func notifyBatchChanges(_ changes: [DatabaseChange]) {
        ChangeNotificationManager.shared.notifyChanges(changes)
    }
}

