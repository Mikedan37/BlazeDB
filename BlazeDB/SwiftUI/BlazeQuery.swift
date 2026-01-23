//
//  BlazeQuery.swift
//  BlazeDB
//
//  SwiftUI property wrapper for reactive database queries.
//  Automatically updates views when data changes, with zero boilerplate.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI
import Combine

// MARK: - BlazeQuery Property Wrapper

/// A SwiftUI property wrapper that automatically executes and updates database queries.
///
/// Use `@BlazeQuery` to declaratively fetch and observe database records in SwiftUI views.
/// The wrapper automatically updates the view when the underlying data changes.
///
/// Example:
/// ```swift
/// struct BugListView: View {
///     @BlazeQuery(
///         db: myDatabase,
///         where: "status", equals: .string("open"),
///         sortBy: "priority", descending: true
///     )
///     var openBugs
///
///     var body: some View {
///         List(openBugs, id: \.id) { bug in
///             Text(bug["title"]?.stringValue ?? "")
///         }
///     }
/// }
/// ```
@propertyWrapper
@MainActor
public struct BlazeQuery: DynamicProperty {
    @StateObject private var observer: BlazeQueryObserver
    
    /// The fetched records, automatically updated
    public var wrappedValue: [BlazeDataRecord] {
        observer.results
    }
    
    /// Access to the underlying observer for advanced use cases
    public var projectedValue: BlazeQueryObserver {
        observer
    }
    
    // MARK: - Type-Safe Variant
    
    /// The fetched records as a specific type (use with `as` parameter)
    public func typed<T: BlazeDocument>(as type: T.Type) throws -> [T] {
        return try observer.results.map { try T(from: $0) }
    }
    
    // MARK: - Initializers
    
    /// Create a query that fetches all records
    public init(db: BlazeDBClient) {
        _observer = StateObject(wrappedValue: BlazeQueryObserver(
            db: db,
            filters: [],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        ))
    }
    
    /// Create a query with a single filter
    @MainActor
    public init(
        db: BlazeDBClient,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryObserver(
            db: db,
            filters: [(field, .equals, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
    
    /// Create a query with a comparison filter
    @MainActor
    public init(
        db: BlazeDBClient,
        where field: String,
        _ comparison: BlazeQueryComparison,
        _ value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryObserver(
            db: db,
            filters: [(field, comparison, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
    
    /// Create a query with multiple filters
    @MainActor
    public init(
        db: BlazeDBClient,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeQueryObserver(
            db: db,
            filters: filters,
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
}

// MARK: - Query Comparison Types

/// Comparison operators for BlazeQuery filters
public enum BlazeQueryComparison {
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case greaterThanOrEqual
    case lessThanOrEqual
    case contains // For strings
}

// MARK: - BlazeQuery Observer

/// Observable object that manages query execution and result updates
@MainActor
public final class BlazeQueryObserver: ObservableObject {
    // MARK: - Published Properties
    
    /// The current query results
    @Published public private(set) var results: [BlazeDataRecord] = []
    
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
    
    /// Wait for the query to load (for testing)
    public func waitForLoad() async throws {
        refresh()
        // Wait for the refresh task to complete
        await refreshTask?.value
    }
    
    /// Manually refresh the query results
    public func refresh() {
        // Cancel any existing refresh
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
                
                // Execute async
                let result = try await query.execute()
                let records = try result.records
                
                BlazeLogger.debug("@BlazeQuery fetched \(records.count) records")
                
                // Update results on main thread
                self.results = records
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
    
    /// Get a specific record by ID
    public func record(withID id: UUID) -> BlazeDataRecord? {
        return results.first { record in
            if let recordID = record.storage["id"] {
                switch recordID {
                case .uuid(let uuid):
                    return uuid == id
                case .string(let str):
                    return UUID(uuidString: str) == id
                default:
                    return false
                }
            }
            return false
        }
    }
    
    /// Filter results in memory (doesn't affect the database query)
    public func filtered(by predicate: (BlazeDataRecord) -> Bool) -> [BlazeDataRecord] {
        return results.filter(predicate)
    }
}

// MARK: - Convenience Extensions

extension BlazeQuery {
    /// Create a query that fetches records with a specific status
    public static func withStatus(
        _ status: String,
        db: BlazeDBClient,
        sortBy: String = "createdAt",
        descending: Bool = true,
        limit: Int? = nil
    ) -> BlazeQuery {
        return BlazeQuery(
            db: db,
            where: "status",
            equals: .string(status),
            sortBy: sortBy,
            descending: descending,
            limit: limit
        )
    }
    
    /// Create a query that fetches high-priority records
    public static func highPriority(
        db: BlazeDBClient,
        threshold: Int = 5,
        sortBy: String = "priority",
        descending: Bool = true,
        limit: Int? = nil
    ) -> BlazeQuery {
        return BlazeQuery(
            db: db,
            where: "priority",
            .greaterThanOrEqual,
            .int(threshold),
            sortBy: sortBy,
            descending: descending,
            limit: limit
        )
    }
}

// MARK: - SwiftUI View Extensions

extension View {
    /// Trigger a refresh of a BlazeQuery when this view appears
    public func refreshOnAppear(_ query: BlazeQueryObserver) -> some View {
        self.onAppear {
            query.refresh()
        }
    }
    
    /// Enable pull-to-refresh for a BlazeQuery
    @available(iOS 15.0, macOS 12.0, *)
    public func refreshable(query: BlazeQueryObserver) -> some View {
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

#endif // canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

