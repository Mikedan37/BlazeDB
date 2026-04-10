import Foundation

/// An **optional** typed view over a `BlazeDBClient` that binds CRUD and query operations
/// to a single `BlazeStorable` model type, so you don't have to repeat `T.self` on every call.
///
/// > **Tip:** For most code, calling methods directly on ``BlazeDBClient`` is simpler:
/// >
/// > ```swift
/// > try db.insert(user)
/// > let u = try db.fetch(User.self, id: userId)
/// > ```
/// >
/// > Use `TypedStore` when you want a scoped handle — e.g. passing a "users"
/// > store to a view model or service layer.
///
/// `TypedStore` does **not** create a separate physical collection or table — BlazeDB stores
/// all records in one encrypted document collection per database file. `TypedStore` is purely
/// a convenience layer that encodes/decodes through the `BlazeStorable` (Codable) bridge.
///
/// ## Usage
///
/// ```swift
/// let users = db.typed(User.self)
///
/// try users.insert(alice)
/// let fetched = try users.fetch(alice.id)
///
/// let seniors = try users.query()
///     .where(\.age, greaterThanOrEqual: 65)
///     .all()
/// ```
///
/// ## Nested Codable types
///
/// Nested `Codable` structs/classes are stored as serialized JSON strings inside
/// `BlazeDocumentField.string`. Round-tripping works, but nested fields are **not**
/// individually queryable via KeyPath filters. Flatten them into top-level properties
/// or use the raw `BlazeDataRecord` query API if you need per-field queries.
public struct TypedStore<T: BlazeStorable>: Sendable {
    private let db: BlazeDBClient

    internal init(db: BlazeDBClient) {
        self.db = db
    }

    // MARK: - Insert

    /// Insert a typed object into the database.
    @discardableResult
    public func insert(_ object: T) throws -> UUID {
        try db.insert(object)
    }

    /// Insert multiple typed objects.
    @discardableResult
    public func insertMany(_ objects: [T]) throws -> [UUID] {
        try db.insertMany(objects)
    }

    // MARK: - Fetch

    /// Fetch a single object by its ID, returning `nil` if not found.
    public func fetch(_ id: UUID) throws -> T? {
        try db.fetch(T.self, id: id)
    }

    /// Fetch all objects of this type.
    public func fetchAll() throws -> [T] {
        try db.fetchAll(T.self)
    }

    // MARK: - Update

    /// Update an existing object (matched by its `id`).
    public func update(_ object: T) throws {
        try db.update(object)
    }

    /// Update many objects.
    public func updateMany(_ objects: [T]) throws {
        try db.updateMany(objects)
    }

    // MARK: - Upsert

    /// Insert or update an object (matched by its `id`).
    @discardableResult
    public func upsert(_ object: T) throws -> Bool {
        try db.upsert(object)
    }

    // MARK: - Delete

    /// Delete an object by ID.
    public func delete(_ id: UUID) throws {
        try db.delete(id: id)
    }

    // MARK: - Query

    /// Start a typed KeyPath query.
    ///
    /// ```swift
    /// let results = try users.query()
    ///     .where(\.name, equals: "Alice")
    ///     .orderBy(\.age, descending: true)
    ///     .all()
    /// ```
    public func query() -> TypeSafeQueryBuilder<T> {
        db.query(T.self)
    }

    // MARK: - Count

    /// Count all objects of this type in the database.
    public func count() throws -> Int {
        try db.fetchAll(T.self).count
    }
}

// MARK: - BlazeDBClient entry point

extension BlazeDBClient {

    /// Create a scoped, typed handle for CRUD operations on a single model type.
    ///
    /// Use this when you want to pass a type-bound store to a view model or
    /// service layer. For simple one-off operations, calling `insert(_:)`,
    /// `fetch(_:id:)`, etc. directly on `BlazeDBClient` is simpler.
    ///
    /// ```swift
    /// let users = db.typed(User.self)
    /// try users.insert(User(name: "Alice", age: 30))
    /// ```
    public func typed<T: BlazeStorable>(_ type: T.Type) -> TypedStore<T> {
        TypedStore<T>(db: self)
    }
}
