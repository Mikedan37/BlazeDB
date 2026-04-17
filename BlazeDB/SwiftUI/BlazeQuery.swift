//
//  BlazeQuery.swift
//  BlazeDB
//
//  Preferred SwiftUI property wrapper for typed, reactive BlazeDB queries (facade only).
//

import Foundation

#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

// MARK: - Field encoding helpers (facade)

private enum BlazeQueryValueEncoding {
    static func field(_ value: String) -> BlazeDocumentField { .string(value) }
    static func field(_ value: Bool) -> BlazeDocumentField { .bool(value) }
    static func field(_ value: Int) -> BlazeDocumentField { .int(value) }
    static func field(_ value: Double) -> BlazeDocumentField { .double(value) }
    static func field(_ value: UUID) -> BlazeDocumentField { .uuid(value) }
    static func field(_ value: Date) -> BlazeDocumentField { .date(value) }
}

// MARK: - BlazeQuery (typed)

/// The default SwiftUI-facing query wrapper for ``BlazeDocument`` models.
///
/// Document type is inferred from the wrapped property (`[Document]`), so you do not pass `type: Document.self`.
/// Provide a database explicitly with `db:` **or** inject ``EnvironmentValues/blazeDBClient`` from an ancestor view.
///
/// ```swift
/// MyRootView()
///     .environment(\.blazeDBClient, app.db)
///
/// struct TodosView: View {
///     @BlazeQuery var items: [TodoItem]
///
///     var body: some View {
///         List(items) { Text($0.title) }
///     }
/// }
/// ```
///
/// This type is a thin facade over ``BlazeQueryTypedObserver``; it does not change storage, SQL, or engine semantics.
///
/// ### Environment-only database
/// If you omit `db:` and rely on ``EnvironmentValues/blazeDBClient``, the observer is bound on first access to
/// ``wrappedValue`` / ``projectedValue`` after SwiftUI has injected the environment. Until then, ``wrappedValue``
/// is empty and this is **not** a failed query—there is no client yet. Prefer setting
/// ``EnvironmentValues/blazeDBClient`` on an ancestor (e.g. root) so the first read already has a database.
///
/// ### Binding from `wrappedValue`
/// ``BlazeQueryTypedObserver/bindDatabaseIfNeeded(_:)`` runs when the wrapped value (or projected observer) is read,
/// avoiding a separate `DynamicProperty.update()` entry point that tripped Swift 6 actor isolation for this wrapper.
/// Exercise navigation, previews, and environment changes in your app if you customize injection heavily.
@propertyWrapper
@MainActor
public struct BlazeQuery<Document: BlazeDocument>: DynamicProperty {
    private let explicitDB: BlazeDBClient?

    @Environment(\.blazeDBClient) private var environmentDB
    @StateObject private var observer: BlazeQueryTypedObserver<Document>

    /// Fetched documents, updated automatically from change notifications and query refresh.
    public var wrappedValue: [Document] {
        observer.bindDatabaseIfNeeded(explicitDB ?? environmentDB)
        return observer.results
    }

    /// Advanced control (manual refresh, loading state, in-memory filtering).
    public var projectedValue: BlazeQueryTypedObserver<Document> {
        observer.bindDatabaseIfNeeded(explicitDB ?? environmentDB)
        return observer
    }

    // MARK: - All documents

    /// Fetches every stored document decoded as `Document`.
    ///
    /// - Parameter db: Pass `nil` (default) to resolve the client from ``EnvironmentValues/blazeDBClient``.
    public init(
        db: BlazeDBClient? = nil,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<Document>(
            db: db,
            filters: [],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }

    // MARK: - Single filter (BlazeDocumentField)

    /// Filter where a field equals a ``BlazeDocumentField`` value.
    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<Document>(
            db: db,
            filters: [(field, .equals, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }

    // MARK: - Single filter (common Swift scalars)

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: String,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: Bool,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: Int,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: Double,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: UUID,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        equals value: Date,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: BlazeQueryValueEncoding.field(value), sortBy: sortBy, descending: descending, limit: limit)
    }

    // MARK: - Comparison + BlazeDocumentField

    public init(
        db: BlazeDBClient? = nil,
        where field: String,
        _ comparison: BlazeQueryComparison,
        _ value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<Document>(
            db: db,
            filters: [(field, comparison, value)],
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }

    // MARK: - Multiple filters

    public init(
        db: BlazeDBClient? = nil,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.explicitDB = db
        _observer = StateObject(wrappedValue: BlazeQueryTypedObserver<Document>(
            db: db,
            filters: filters,
            sortField: sortBy,
            sortDescending: descending,
            limitCount: limit
        ))
    }
}

// MARK: - Legacy `type:` initializers (source-compatible)

extension BlazeQuery {
    /// Deprecated: `Document` is inferred from the wrapped `[Document]` property type.
    @available(*, deprecated, message: "Remove `type:`; the document type is inferred from `[Document]`.")
    public init(db: BlazeDBClient, type: Document.Type, sortBy: String? = nil, descending: Bool = false, limit: Int? = nil) {
        self.init(db: db, sortBy: sortBy, descending: descending, limit: limit)
    }

    @available(*, deprecated, message: "Remove `type:`; the document type is inferred from `[Document]`.")
    public init(
        db: BlazeDBClient,
        type: Document.Type,
        where field: String,
        equals value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, equals: value, sortBy: sortBy, descending: descending, limit: limit)
    }

    @available(*, deprecated, message: "Remove `type:`; the document type is inferred from `[Document]`.")
    public init(
        db: BlazeDBClient,
        type: Document.Type,
        where field: String,
        _ comparison: BlazeQueryComparison,
        _ value: BlazeDocumentField,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, where: field, comparison, value, sortBy: sortBy, descending: descending, limit: limit)
    }

    @available(*, deprecated, message: "Remove `type:`; the document type is inferred from `[Document]`.")
    public init(
        db: BlazeDBClient,
        type: Document.Type,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.init(db: db, filters: filters, sortBy: sortBy, descending: descending, limit: limit)
    }
}

/// Legacy alias for ``BlazeQuery`` kept for source compatibility.
public typealias BlazeQueryTyped<Document: BlazeDocument> = BlazeQuery<Document>

#endif
