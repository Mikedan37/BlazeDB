//
//  BlazeStorableLiveQuery.swift
//  BlazeDB
//
//  SwiftUI integration composes ``BlazeLiveQuery`` (core) with
//  ``@Published`` state and environment injection (Apple-only ergonomics).
//

import Foundation

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

/// SwiftUI live-query wrapper for a ``BlazeStorable`` model (namespace-filtered decode).
///
/// **Relationship to other wrappers:** Prefer ``BlazeQuery`` when your model conforms to
/// ``BlazeDocument`` (typed manual mapping). Use ``BlazeStorableQuery`` when you rely on
/// ``BlazeStorable`` / Codable only and do not want ``BlazeDocument``. For raw
/// ``BlazeDataRecord`` rows, use ``BlazeDataQuery``.
///
/// Under the hood this composes ``BlazeLiveQuery`` — the same observe → refresh → decode
/// pipeline used outside SwiftUI.
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
    private var liveQuery: BlazeLiveQuery<T>?

    fileprivate init(
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

        if let db {
            attachLiveQuery(db: db)
        }
    }

    /// Binds a ``BlazeDBClient`` from SwiftUI environment (or explicit injection) the first time it becomes available.
    internal func bindDatabaseIfNeeded(_ client: BlazeDBClient?) {
        guard db == nil, let client else { return }
        db = client
        attachLiveQuery(db: client)
    }

    private func attachLiveQuery(db: BlazeDBClient) {
        liveQuery?.stop()
        let query = BlazeLiveQuery<T>(
            db: db,
            filters: filters,
            sortBy: sortField,
            descending: sortDescending,
            limit: limitCount
        )
        query.onResults = { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let rows):
                self.results = rows
                self.error = nil
            case .failure(let error):
                self.error = error
            }
        }
        liveQuery = query
        isLoading = true
        query.start()
    }

    public func refresh() {
        isLoading = true
        liveQuery?.refresh()
    }
}

#endif
