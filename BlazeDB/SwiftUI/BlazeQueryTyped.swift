//
//  BlazeQueryTyped.swift
//  BlazeDB
//
//  Type-safe variant of @BlazeQuery for compile-time safety.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

// MARK: - Type-Safe BlazeQuery

/// Type-safe SwiftUI property wrapper for database queries.
///
/// Use `@BlazeQueryTyped` when you want compile-time type safety for your models.
///
/// Example:
/// ```swift
/// struct BugListView: View {
///     @BlazeQueryTyped(
///         db: myDatabase,
///         type: Bug.self,
///         where: "status", equals: .string("open"),
///         sortBy: "priority", descending: true
///     )
///     var openBugs: [Bug]  // Type-safe! ✅
///
///     var body: some View {
///         List(openBugs) { bug in
///             Text(bug.title)  // Direct access! ✅
///             Text("P\(bug.priority)")  // No .intValue! ✅
///         }
///     }
/// }
/// ```
@propertyWrapper
@MainActor
public struct BlazeQueryTyped<T: BlazeDocument>: DynamicProperty {
    @StateObject private var observer: BlazeQueryTypedObserver<T>
    
    /// The fetched documents, automatically updated
    public var wrappedValue: [T] {
        observer.results
    }
    
    /// Access to the underlying observer for advanced use cases
    public var projectedValue: BlazeQueryTypedObserver<T> {
        observer
    }
    
    // MARK: - Initializers
    
    /// Create a type-safe query that fetches all records
    public init(db: BlazeDBClient, type: T.Type) {
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<T>(
            db: db,
            filters: [],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        ))
    }
    
    /// Create a type-safe query with a single filter
    public init(
        db: BlazeDBClient,
        type: T.Type,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<T>(
            db: db,
            filters: [(field, .equals, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
    
    /// Create a type-safe query with a comparison filter
    public init(
        db: BlazeDBClient,
        type: T.Type,
        where field: String,
        _ comparison: BlazeQueryComparison,
        _ value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<T>(
            db: db,
            filters: [(field, comparison, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
    
    /// Create a type-safe query with multiple filters
    public init(
        db: BlazeDBClient,
        type: T.Type,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<T>(
            db: db,
            filters: filters,
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
}

// MARK: - Type-Safe Query Observer

/// Observable object that manages type-safe query execution and result updates
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
    
    private let db: BlazeDBClient
    private let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    private let sortField: String?
    private let sortDescending: Bool
    private let limitCount: Int?
    
    private var refreshTask: Task<Void, Never>?
    @MainActor private var autoRefreshTimer: Timer?
    
    // MARK: - Initialization
    
    internal init(
        db: BlazeDBClient,
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
        
        // Initial fetch
        refresh()
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
                
                BlazeLogger.debug("@BlazeQueryTyped fetched \(typed.count) documents of type \(T.self)")
                
                // Update results on main thread
                self.results = typed
                self.isLoading = false
                
            } catch {
                BlazeLogger.error("@BlazeQueryTyped fetch failed: \(error)")
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
            query.refresh()
        }
    }
    
    /// Enable pull-to-refresh for a type-safe BlazeQuery
    @available(iOS 15.0, macOS 12.0, *)
    public func refreshable<T: BlazeDocument>(query: BlazeQueryTypedObserver<T>) -> some View {
        self.refreshable {
            await withCheckedContinuation { continuation in
                query.refresh()
                // Wait for loading to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    continuation.resume()
                }
            }
        }
    }
}

#endif // canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
