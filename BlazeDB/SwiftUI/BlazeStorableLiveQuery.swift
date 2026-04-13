import Foundation

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

// MARK: - Change notification (same pattern as ``BlazeQueryTypedObserver``)

@MainActor
fileprivate protocol BlazeStorableQueryRefreshable: AnyObject {
    func refresh()
}

extension BlazeStorableQueryObserver: BlazeStorableQueryRefreshable {}

private final class BlazeStorableQueryRefreshSink: @unchecked Sendable {
    private weak var target: (any BlazeStorableQueryRefreshable)?

    func attach(_ o: any BlazeStorableQueryRefreshable) {
        target = o
    }

    func notifyChange() {
        guard let t = target else { return }
        Task { @MainActor in
            t.refresh()
        }
    }
}

/// SwiftUI live-query wrapper for a ``BlazeStorable`` model (namespace-filtered decode).
///
/// **Relationship to other wrappers:** Prefer ``BlazeQuery`` when your model conforms to
/// ``BlazeDocument`` (typed manual mapping). Use ``BlazeStorableQuery`` when you rely on
/// ``BlazeStorable`` / Codable only and do not want ``BlazeDocument``. For raw
/// ``BlazeDataRecord`` rows, use ``BlazeDataQuery``.
///
/// Pass ``BlazeDBClient`` with `db:` **or** inject ``EnvironmentValues/blazeDBClient`` from an ancestor
/// (same as ``BlazeQuery``). If `db` is omitted, results stay empty until the environment provides a client.
///
/// ```swift
/// RootView().blazeDBEnvironment(app.db)
///
/// @BlazeStorableQuery(kind: Bug.self) var bugs: [Bug]
/// ```
@propertyWrapper
@MainActor
public struct BlazeStorableQuery<T: BlazeStorable>: DynamicProperty {
    private let explicitDB: BlazeDBClient?

    @Environment(\.blazeDBClient) private var environmentDB
    @StateObject private var observer: BlazeStorableQueryObserver<T>

    public var wrappedValue: [T] {
        observer.bindDatabaseIfNeeded(explicitDB ?? environmentDB)
        return observer.results
    }

    public var projectedValue: BlazeStorableQueryObserver<T> {
        observer.bindDatabaseIfNeeded(explicitDB ?? environmentDB)
        return observer
    }

    /// - Parameter db: Pass `nil` (default) to resolve the client from ``EnvironmentValues/blazeDBClient``.
    public init(db: BlazeDBClient? = nil, kind: T.Type) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeStorableQueryObserver(
            db: db,
            filters: [],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        ))
    }

    /// - Parameter db: Pass `nil` (default) to resolve the client from ``EnvironmentValues/blazeDBClient``.
    public init(
        db: BlazeDBClient? = nil,
        kind: T.Type,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeStorableQueryObserver(
            db: db,
            filters: [(field, .equals, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
}

/// Alias for ``BlazeStorableQuery`` when you want a name that signals environment-driven resolution.
public typealias BlazeStorableEnvironmentQuery<T: BlazeStorable> = BlazeStorableQuery<T>

@MainActor
public final class BlazeStorableQueryObserver<T: BlazeStorable>: ObservableObject {
    @Published public private(set) var results: [T] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?

    private var db: BlazeDBClient?
    private let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    private let sortField: String?
    private let sortDescending: Bool
    private let limitCount: Int?
    private var refreshTask: Task<Void, Never>?
    private var changeObserverToken: ObserverToken?
    private let refreshSink = BlazeStorableQueryRefreshSink()

    fileprivate init(
        db: BlazeDBClient?,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortField: String?,
        sortDescending: Bool,
        limitCount: Int?
    ) {
        self.db = db
        let kindValue: BlazeDocumentField = .string(BlazeRecordKind.normalizedName(for: T.self))
        self.filters = [(BlazeRecordKind.storageKey, .equals, kindValue)] + filters
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

    public func refresh() {
        refreshTask?.cancel()

        guard let db else {
            isLoading = false
            return
        }

        refreshTask = Task { @MainActor in
            isLoading = true
            error = nil
            do {
                var query = db.query()
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
                if let sortField {
                    query = await query.orderBy(sortField, descending: sortDescending)
                }
                if let limitCount {
                    query = query.limit(limitCount)
                }
                let result = try await query.execute()
                let records = try result.records
                results = records.compactMap { try? T.fromBlazeRecord($0) }
                isLoading = false
            } catch {
                self.error = error
                isLoading = false
            }
        }
    }
}

#endif
