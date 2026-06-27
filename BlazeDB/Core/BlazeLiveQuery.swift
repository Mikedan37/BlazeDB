//
//  BlazeLiveQuery.swift
//  BlazeDB
//
//  Platform-agnostic live query: observe → refresh → decode.
//  SwiftUI property wrappers, Android Flow adapters, and CLI callbacks
//  should compose this type instead of reimplementing observation logic.
//

import Foundation

/// Live query for a ``BlazeStorable`` model type.
///
/// Wires ``BlazeDBClient/observe(_:)`` to a typed namespace query and delivers
/// refreshed results through a callback. This is the reusable core behind
/// ``BlazeStorableQuery`` on Apple platforms.
///
/// ```swift
/// let live = BlazeLiveQuery<Todo>(
///     db: db,
///     where: "isDone",
///     equals: .bool(false),
///     sortBy: "title"
/// )
/// live.onResults = { result in
///     switch result {
///     case .success(let todos): ...
///     case .failure(let error): ...
///     }
/// }
/// live.start()
/// defer { live.stop() }
/// ```
///
/// ## Public API contract
///
/// ``BlazeLiveQuery`` is a supported core API. Adapters (SwiftUI, ViewModels, JNI)
/// should depend on these semantics rather than reimplementing observation.
///
/// ### Lifecycle
///
/// - ``start()`` registers exactly one ``ObserverToken`` (replacing any prior token) and
///   synchronously calls ``refresh()`` once for an initial snapshot.
/// - ``stop()`` invalidates the token. Safe to call repeatedly. After ``stop()``, database
///   changes do **not** trigger ``refresh()``.
/// - ``deinit`` calls ``stop()``. No observer callbacks after deallocation.
/// - Manual ``refresh()`` remains valid after ``stop()``; it re-runs the query and invokes
///   ``onResults`` but does not re-register an observer.
///
/// ### Threading
///
/// - ``runQuery()`` executes on the thread that calls ``refresh()`` (usually the main queue
///   after a batched change notification).
/// - ``onResults`` is always invoked on the **main queue** (synchronously if already on main,
///   otherwise via ``DispatchQueue.main.async``).
/// - Non-UI callers (CLI, tests) must pump ``RunLoop.main`` to receive observer-driven
///   callbacks within a bounded time (~150ms after writes is typical).
///
/// ### Callback ordering
///
/// - ``start()`` produces one initial ``onResults`` call before any write occurs.
/// - After writes, delivery follows ``ChangeNotificationManager`` batching (~50ms), then
///   ``refresh()`` → ``onResults``. Callback order matches commit order of batched flushes,
///   not individual sub-millisecond writes.
/// - There is no guarantee that intermediate query states are delivered when writes arrive
///   faster than the batch window; the last refresh reflects storage at query time.
///
/// ### Coalescing
///
/// - ``ChangeNotificationManager`` coalesces **change notifications** within ~50ms into one
///   observer callback → one ``refresh()`` per flush.
/// - ``BlazeLiveQuery`` does **not** coalesce overlapping ``refresh()`` calls. Slow queries
///   or writes across multiple batch windows may produce multiple ``onResults`` deliveries.
/// - Each delivery is a full re-query of authoritative storage (not an incremental diff).
///
/// ### ``stop()`` guarantees
///
/// - Observer unregistered; no further observer-driven ``refresh()``.
/// - In-flight ``refresh()`` started before ``stop()`` may still complete and deliver.
/// - Setting ``onResults`` to `nil` suppresses delivery; the handler is read under lock at
///   delivery time.
///
/// ## Lifecycle / observer ownership
///
/// ``BlazeLiveQuery`` owns the ``ObserverToken`` registered by ``start()``.
/// Call ``stop()`` to unregister early, or rely on ``deinit`` (which calls ``stop()``).
/// Do not call ``start()`` without a matching ``stop()`` or deallocation — leaked
/// observers are prevented by explicit ``stop()`` / deinit, not by garbage collection alone.
public final class BlazeLiveQuery<T: BlazeStorable>: @unchecked Sendable {
    public typealias ResultsHandler = (Result<[T], Error>) -> Void

    private final class RefreshBridge: @unchecked Sendable {
        private weak var query: BlazeLiveQuery<T>?
        func attach(_ query: BlazeLiveQuery<T>) { self.query = query }
        func notify() { query?.refresh() }
    }

    private let db: BlazeDBClient
    private let filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)]
    private let sortField: String?
    private let sortDescending: Bool
    private let limitCount: Int?

    private var observerToken: ObserverToken?
    private var resultsHandler: ResultsHandler?
    private let handlerLock = NSLock()
    private let refreshBridge = RefreshBridge()

    /// - Parameters:
    ///   - db: Database client to observe and query.
    ///   - field: Optional field filter (`.equals` only when using this initializer).
    ///   - value: Value paired with `field`.
    ///   - sortBy: Optional sort field name.
    ///   - descending: Sort direction when `sortBy` is set.
    ///   - limit: Optional maximum number of rows.
    public init(
        db: BlazeDBClient,
        where field: String? = nil,
        equals value: BlazeDocumentField? = nil,
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.db = db
        if let field, let value {
            self.filters = [(field, .equals, value)]
        } else {
            self.filters = []
        }
        self.sortField = sortBy
        self.sortDescending = descending
        self.limitCount = limit
        refreshBridge.attach(self)
    }

    /// Advanced initializer mirroring ``BlazeStorableQueryObserver`` filter tuples.
    public init(
        db: BlazeDBClient,
        filters: [(field: String, comparison: BlazeQueryComparison, value: BlazeDocumentField)],
        sortBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) {
        self.db = db
        self.filters = filters
        self.sortField = sortBy
        self.sortDescending = descending
        self.limitCount = limit
        refreshBridge.attach(self)
    }

    deinit {
        stop()
    }

    /// Called whenever ``refresh()`` completes (including after change notifications).
    public var onResults: ResultsHandler? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return resultsHandler
        }
        set {
            handlerLock.lock()
            resultsHandler = newValue
            handlerLock.unlock()
        }
    }

    /// Subscribe to database changes and run an initial refresh.
    ///
    /// Idempotent: replaces any existing observer. Registers exactly one ``ObserverToken``,
    /// then synchronously calls ``refresh()`` for an initial snapshot.
    public func start() {
        stop()
        observerToken = db.observe { [refreshBridge] _ in
            refreshBridge.notify()
        }
        refresh()
    }

    /// Unregister the change observer.
    ///
    /// Idempotent. After ``stop()``, database changes no longer trigger ``refresh()``.
    /// Manual ``refresh()`` still runs the query and invokes ``onResults``.
    public func stop() {
        observerToken?.invalidate()
        observerToken = nil
    }

    /// Re-run the typed query and invoke ``onResults``.
    public func refresh() {
        do {
            let rows = try runQuery()
            deliver(.success(rows))
        } catch {
            deliver(.failure(error))
        }
    }

    private func runQuery() throws -> [T] {
        let namespace = BlazeRecordKind.normalizedName(for: T.self)
        var query = db.query().where {
            BlazeRecordKind.recordMatchesNamespace($0, normalizedNamespace: namespace)
        }

        for filter in filters {
            switch filter.comparison {
            case .equals:
                query = query.where(filter.field, equals: filter.value)
            case .notEquals:
                query = query.where(filter.field, notEquals: filter.value)
            case .greaterThan:
                query = query.where(filter.field, greaterThan: filter.value)
            case .lessThan:
                query = query.where(filter.field, lessThan: filter.value)
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
            query = query.orderBy(sortField, descending: sortDescending)
        }
        if let limitCount {
            query = query.limit(limitCount)
        }

        let result = try query.execute()
        let records = try result.records
        var rows: [T] = []
        for record in records {
            if let row = try? T.fromBlazeRecord(record) {
                rows.append(row)
            }
        }
        return rows
    }

    private struct ResultBox: @unchecked Sendable {
        let value: Result<[T], Error>
    }

    private func deliver(_ result: Result<[T], Error>) {
        handlerLock.lock()
        let handler = resultsHandler
        handlerLock.unlock()
        guard let handler else { return }

        let box = ResultBox(value: result)
        if Thread.isMainThread {
            handler(box.value)
        } else {
            DispatchQueue.main.async {
                handler(box.value)
            }
        }
    }
}
