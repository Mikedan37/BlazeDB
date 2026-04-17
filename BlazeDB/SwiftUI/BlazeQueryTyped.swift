//
//  BlazeQueryTyped.swift
//  BlazeDB
//
//  ``BlazeQueryTypedObserver`` powers typed SwiftUI queries (facade only).
//  Use the ``BlazeQuery`` property wrapper for the preferred API.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

// MARK: - Type-Safe Query Observer

@MainActor
fileprivate protocol BlazeQueryTypedRefreshable: AnyObject {
    func refresh()
}

extension BlazeQueryTypedObserver: BlazeQueryTypedRefreshable {}

/// Non-generic so `@Sendable` `observe` does not close over `T.Type` (#SendableMetatypes).
private final class BlazeQueryTypedRefreshSink: @unchecked Sendable {
    private weak var target: (any BlazeQueryTypedRefreshable)?

    func attach(_ o: any BlazeQueryTypedRefreshable) {
        target = o
    }

    func notifyChange() {
        guard let t = target else { return }
        Task { @MainActor in
            t.refresh()
        }
    }
}

/// Observable object that manages type-safe query execution and result updates for ``BlazeQuery``.
@MainActor
public final class BlazeQueryTypedObserver<T: BlazeDocument>: ObservableObject {
    // MARK: - Published Properties

    /// The current query results (type-safe!)
    @Published public private(set) var results: [T] = []

    /// Whether the query is currently loading
    @Published public private(set) var isLoading: Bool = false

    /// The last error that occurred, if any
    @Published public private(set) var error: Error?

    /// The number of results
    public var count: Int {
        results.count
    }

    /// Whether there are no results
    public var isEmpty: Bool {
        results.isEmpty
    }

    // MARK: - Private Properties

    private var db: BlazeDBClient?
    private let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    private let sortField: String?
    private let sortDescending: Bool
    private let limitCount: Int?

    private var refreshTask: Task<Void, Never>?
    private var changeObserverToken: ObserverToken?
    @MainActor private var autoRefreshTimer: Timer?
    private let refreshSink = BlazeQueryTypedRefreshSink()

    // MARK: - Initialization

    /// - Parameter db: Pass `nil` when the database will be supplied later via ``bindDatabaseIfNeeded(_:)`` (SwiftUI environment).
    internal init(
        db: BlazeDBClient?,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortField: String?,
        sortDescending: Bool,
        limitCount: Int?
    ) {
        self.db = db
        self.filters = filters
        self.sortField = sortField
        self.sortDescending = sortDescending
        self.limitCount = limitCount

        refreshSink.attach(self)

        if let db {
            subscribeToChanges(db: db)
            refresh()
        }
    }

    /// Binds a ``BlazeDBClient`` from SwiftUI environment (or explicit injection) the first time it becomes available.
    internal func bindDatabaseIfNeeded(_ client: BlazeDBClient?) {
        guard db == nil, let client else { return }
        db = client
        subscribeToChanges(db: client)
        refresh()
    }

    private func subscribeToChanges(db: BlazeDBClient) {
        changeObserverToken = db.observe { [refreshSink] _ in
            refreshSink.notifyChange()
        }
    }
    
    deinit {
        refreshTask?.cancel()
        // Timer cleanup - autoRefreshTimer is @MainActor, will be cleaned up automatically
        // No explicit cleanup needed in deinit
    }
    
    // MARK: - Public Methods
    
    /// Manually refresh the query results
    public func refresh() {
        refreshTask?.cancel()

        guard let db else {
            isLoading = false
            return
        }

        refreshTask = Task { @MainActor in
            self.isLoading = true
            self.error = nil

            do {
                // Build query
                var query = db.query()
                
                // Apply filters
                for filter in filters {
                    switch filter.comparison {
                    case .equals:
                        query = await query.where(filter.field, equals: filter.value)
                    case .notEquals:
                        query = await query.where(filter.field, notEquals: filter.value)
                    case .greaterThan:
                        query = await query.where(filter.field, greaterThan: filter.value)
                    case .lessThan:
                        query = await query.where(filter.field, lessThan: filter.value)
                    case .greaterThanOrEqual:
                        query = query.where(filter.field, greaterThanOrEqual: filter.value)
                    case .lessThanOrEqual:
                        query = query.where(filter.field, lessThanOrEqual: filter.value)
                    case .contains:
                        if let stringValue = filter.value.stringValue {
                            query = query.where(filter.field, contains: stringValue)
                        }
                    }
                }
                
                // Apply sorting
                if let sortField = sortField {
                    query = await query.orderBy(sortField, descending: sortDescending)
                }
                
                // Apply limit
                if let limit = limitCount {
                    query = query.limit(limit)
                }
                
                // Execute and convert to type
                let result = try await query.execute()
                let records = try result.records
                let typed = try records.map { try T(from: $0) }
                
                BlazeLogger.debug("@BlazeQuery fetched \(typed.count) documents of type \(T.self)")

                // Update results on main thread
                self.results = typed
                self.isLoading = false

            } catch {
                BlazeLogger.error("@BlazeQuery fetch failed: \(error)")
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    /// Enable auto-refresh at the specified interval
    /// - Parameter interval: Time interval between refreshes in seconds
    @MainActor
    public func enableAutoRefresh(interval: TimeInterval = 5.0) {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
    
    /// Disable auto-refresh
    @MainActor
    public func disableAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }
    
    /// Get a specific document by ID
    public func document(withID id: UUID) -> T? {
        return results.first { $0.id == id }
    }
    
    /// Filter results in memory
    public func filtered(by predicate: (T) -> Bool) -> [T] {
        return results.filter(predicate)
    }
}

// MARK: - SwiftUI View Extensions for Type-Safe Queries

extension View {
    /// Trigger a refresh of a type-safe BlazeQuery when this view appears
    public func refreshOnAppear<T: BlazeDocument>(_ query: BlazeQueryTypedObserver<T>) -> some View {
        self.onAppear {
            Task { @MainActor in
                query.refresh()
            }
        }
    }
    
    /// Enable pull-to-refresh for a type-safe BlazeQuery
    public func refreshable<T: BlazeDocument>(query: BlazeQueryTypedObserver<T>) -> some View {
        self.refreshable {
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    query.refresh()
                }
                // Wait for loading to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
        }
    }
}

#endif // canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
