import Foundation

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

/// SwiftUI live-query wrapper for a ``BlazeStorable`` model.
///
/// Use this when your UI should stay in sync with database writes for one model type.
///
/// ```swift
/// @BlazeStorableQuery(
///     db: db,
///     kind: Bug.self,
///     where: "status",
///     equals: .string("open")
/// )
/// var bugs: [Bug]
/// ```
@propertyWrapper
@MainActor
public struct BlazeStorableQuery<T: BlazeStorable>: DynamicProperty {
    @StateObject private var observer: BlazeStorableQueryObserver<T>

    public var wrappedValue: [T] { observer.results }
    public var projectedValue: BlazeStorableQueryObserver<T> { observer }

    public init(db: BlazeDBClient, kind: T.Type) {
        _observer = StateObject(wrappedValue: BlazeStorableQueryObserver(
            db: db,
            filters: [],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        ))
    }

    public init(
        db: BlazeDBClient,
        kind: T.Type,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        _observer = StateObject(wrappedValue: BlazeStorableQueryObserver(
            db: db,
            filters: [(field, .equals, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
}

@MainActor
public final class BlazeStorableQueryObserver<T: BlazeStorable>: ObservableObject {
    @Published public private(set) var results: [T] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?

    private let db: BlazeDBClient
    private let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    private let sortField: String?
    private let sortDescending: Bool
    private let limitCount: Int?
    private var refreshTask: Task<Void, Never>?
    private var changeObserverToken: ObserverToken?

    fileprivate init(
        db: BlazeDBClient,
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
        refresh()
        self.changeObserverToken = db.observe { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func refresh() {
        refreshTask?.cancel()
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
