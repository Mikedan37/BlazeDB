import Foundation

public enum BlazeDB {
    /// Default app entrypoint: open an encrypted database by name in the platform default directory.
    ///
    /// Use this for most app code. The returned handle is where you call `put`, `get`, and `query(_:)`.
    ///
    /// ```swift
    /// let db = try BlazeDB.open(name: "demo", password: "pass-123")
    /// ```
    public static func open(name: String, password: String) throws -> BlazeDBClient {
        try BlazeDBClient.open(named: name, password: password)
    }

    /// Open or create an encrypted database at an exact file URL.
    ///
    /// Use this when you already manage the database file path yourself.
    ///
    /// ```swift
    /// let dbURL = URL(fileURLWithPath: "/tmp/demo.blazedb")
    /// let db = try BlazeDB.open(at: dbURL, password: "pass-123")
    /// ```
    public static func open(at url: URL, password: String) throws -> BlazeDBClient {
        try BlazeDBClient.open(at: url, password: password)
    }
}

public final class BlazeNamespaceQueryBuilder: @unchecked Sendable {
    private var builder: QueryBuilder

    fileprivate init(db: BlazeDBClient, namespace: String) {
        let norm = namespace.lowercased()
        self.builder = db.query().where { BlazeRecordKind.recordMatchesNamespace($0, normalizedNamespace: norm) }
    }

    @discardableResult
    public func `where`(_ field: String, equals value: BlazeDocumentField) -> Self {
        builder = builder.where(field, equals: value)
        return self
    }

    @discardableResult
    public func `where`(_ field: String, equals string: String) -> Self {
        `where`(field, equals: .string(string))
    }

    @discardableResult
    public func `where`(_ field: String, _ match: BlazeNamespaceQueryPredicate) -> Self {
        switch match {
        case .equals(let value):
            return `where`(field, equals: value)
        }
    }

    @discardableResult
    public func orderBy(_ field: String, descending: Bool = false) -> Self {
        builder = builder.orderBy(field, descending: descending)
        return self
    }

    @discardableResult
    public func limit(_ count: Int) -> Self {
        builder = builder.limit(count)
        return self
    }

    /// Execute and decode all matching rows as a typed array.
    ///
    /// ```swift
    /// let openBugs: [Bug] = try db.query("bug")
    ///     .where("status", equals: "open")
    ///     .all()
    /// ```
    public func all<T: BlazeStorable>() throws -> [T] {
        try builder.all().compactMap { try? T.fromBlazeRecord($0) }
    }

    public func all<T: BlazeStorable>() async throws -> [T] {
        try await builder.all().compactMap { try? T.fromBlazeRecord($0) }
    }

    /// Execute and decode the first matching row, or `nil`.
    public func first<T: BlazeStorable>() throws -> T? {
        try builder.limit(1).all().compactMap { try? T.fromBlazeRecord($0) }.first
    }

    public func first<T: BlazeStorable>() async throws -> T? {
        try await builder.limit(1).all().compactMap { try? T.fromBlazeRecord($0) }.first
    }
}

public enum BlazeNamespaceQueryPredicate {
    case equals(BlazeDocumentField)
    public static func equals(_ text: String) -> BlazeNamespaceQueryPredicate { .equals(.string(text)) }
}

private enum BlazeRecordKeyParser {
    static func parse(_ key: String) throws -> (namespace: String?, id: UUID) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw BlazeDBError.invalidInput(reason: "Record key cannot be empty")
        }
        if let u = UUID(uuidString: trimmed) {
            return (nil, u)
        }
        guard let colon = trimmed.lastIndex(of: ":") else {
            throw BlazeDBError.invalidInput(reason: "Key must be a UUID or \"namespace:UUID\" (got: \(key))")
        }
        let idPart = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let nsPart = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: idPart), !nsPart.isEmpty else {
            throw BlazeDBError.invalidInput(reason: "Key must be a UUID or \"namespace:UUID\" (got: \(key))")
        }
        return (String(nsPart), id)
    }
}

extension BlazeDBClient {
    /// Default write API: store one model value.
    @discardableResult
    public func put<T: BlazeStorable>(_ value: T) throws -> Bool {
        try upsert(value)
    }

    public func put<T: BlazeStorable>(_ values: [T]) throws {
        for v in values {
            try upsert(v)
        }
    }

    /// Default read API: fetch one typed value by key (`UUID` or `namespace:UUID`).
    ///
    /// ```swift
    /// let bug: Bug? = try db.get("bug:\(id.uuidString)")
    /// ```
    public func get<T: BlazeStorable>(_ key: String) throws -> T? {
        let (ns, id) = try BlazeRecordKeyParser.parse(key)
        guard let record = try fetch(id: id) else { return nil }
        if let ns {
            let want = ns.lowercased()
            if let have = record.storage[BlazeRecordKind.storageKey]?.stringValue?.lowercased(), have != want {
                return nil
            }
        }
        return try T.fromBlazeRecord(record)
    }

    public func query(_ namespace: String) -> BlazeNamespaceQueryBuilder {
        BlazeNamespaceQueryBuilder(db: self, namespace: namespace)
    }
}
