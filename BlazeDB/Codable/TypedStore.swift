import Foundation

/// A typed view over a `BlazeDBClient` that binds all CRUD and query operations to a
/// single `BlazeStorable` model type, eliminating the need to repeat `T.self` on every call.
///
/// `TypedStore` does **not** create a separate physical collection or table — BlazeDB stores
/// all records in one encrypted document collection per database file. `TypedStore` is purely
/// a convenience layer that encodes/decodes through the `BlazeStorable` (Codable) bridge.
///
/// ## Quick start
///
/// ```swift
/// struct User: BlazeStorable {
///     var id: UUID = UUID()
///     var name: String
///     var age: Int
/// }
///
/// let db = try BlazeDBClient.open(named: "myapp", password: "Secure-Password-2026!")
/// let users = db.typed(User.self)
///
/// // Insert
/// let alice = User(name: "Alice", age: 30)
/// try users.insert(alice)
///
/// // Fetch
/// let fetched = try users.fetch(alice.id)
///
/// // Query with KeyPaths
/// let seniors = try users.query()
///     .where(\.age, greaterThanOrEqual: 65)
///     .all()
///
/// // Fetch all
/// let everyone = try users.fetchAll()
/// ```
///
/// ## Nested Codable types
///
/// Nested `Codable` structs/classes are currently stored as serialized JSON strings inside
/// `BlazeDocumentField.string`. Round-tripping works, but the nested fields are **not**
/// individually queryable via KeyPath filters. If you need to query nested fields, flatten
/// them into top-level properties or use the raw `BlazeDataRecord` query API.
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

    /// Create a typed store for convenient, type-safe CRUD operations.
    ///
    /// The returned `TypedStore` binds all operations to the given `BlazeStorable` type
    /// so you never need to repeat `T.self`. This is the **recommended** API for most
    /// applications.
    ///
    /// ```swift
    /// let users = db.typed(User.self)
    /// try users.insert(User(name: "Alice", age: 30))
    /// let all = try users.fetchAll()
    /// ```
    ///
    /// > **Note:** `TypedStore` is a typed view, not a separate physical table.
    /// > All records share the same underlying encrypted collection.
    public func typed<T: BlazeStorable>(_ type: T.Type) -> TypedStore<T> {
        TypedStore<T>(db: self)
    }
}
