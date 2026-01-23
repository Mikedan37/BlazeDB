import Foundation

// MARK: - Data Seeding & Fixtures

extension BlazeDBClient {
    
    // MARK: - Seed Data
    
    /// Generate and insert test data
    ///
    /// Example:
    /// ```swift
    /// let bugs = try db.seed(Bug.self, count: 100) { i in
    ///     Bug(
    ///         id: UUID(),
    ///         title: "Bug \(i)",
    ///         priority: Int.random(in: 1...10),
    ///         status: ["open", "closed"].randomElement()!
    ///     )
    /// }
    /// ```
    @discardableResult
    public func seed<T: BlazeStorable>(
        _ type: T.Type,
        count: Int,
        generator: (Int) throws -> T
    ) throws -> [T] {
        var objects: [T] = []
        
        for i in 0..<count {
            let object = try generator(i)
            objects.append(object)
        }
        
        _ = try self.insertMany(objects)
        return objects
    }
    
    /// Seed async
    @discardableResult
    public func seed<T: BlazeStorable>(
        _ type: T.Type,
        count: Int,
        generator: (Int) throws -> T
    ) async throws -> [T] {
        var objects: [T] = []
        
        for i in 0..<count {
            let object = try generator(i)
            objects.append(object)
        }
        
        _ = try await self.insertMany(objects)
        return objects
    }
    
    /// Seed with BlazeDataRecord
    @discardableResult
    public func seed(
        count: Int,
        generator: (Int) throws -> BlazeDataRecord
    ) throws -> [UUID] {
        var records: [BlazeDataRecord] = []
        
        for i in 0..<count {
            let record = try generator(i)
            records.append(record)
        }
        
        return try self.insertMany(records)
    }
    
    /// Seed BlazeDataRecord async
    @discardableResult
    public func seed(
        count: Int,
        generator: (Int) throws -> BlazeDataRecord
    ) async throws -> [UUID] {
        var records: [BlazeDataRecord] = []
        
        for i in 0..<count {
            let record = try generator(i)
            records.append(record)
        }
        
        return try await self.insertMany(records)
    }
    
    // MARK: - Factories
    
    /// Register a factory for a type
    ///
    /// Example:
    /// ```swift
    /// db.factory(Bug.self) { i in
    ///     Bug(id: UUID(), title: "Bug \(i)", priority: 5, status: "open")
    /// }
    ///
    /// let bugs = try db.create(Bug.self, count: 10)
    /// ```
    @MainActor
    public func factory<T: BlazeStorable>(
        _ type: T.Type,
        generator: @escaping (Int) -> T
    ) {
        FactoryRegistry.shared.register(type, generator: generator)
    }
    
    /// Create objects using registered factory
    @discardableResult
    @MainActor
    public func create<T: BlazeStorable>(
        _ type: T.Type,
        count: Int = 1
    ) throws -> [T] {
        guard let generator = FactoryRegistry.shared.get(type) else {
            throw BlazeDBError.transactionFailed("No factory registered for \(T.self)")
        }
        
        return try self.seed(type, count: count, generator: generator)
    }
    
    /// Create async
    @discardableResult
    public func create<T: BlazeStorable>(
        _ type: T.Type,
        count: Int = 1
    ) async throws -> [T] {
        guard let generator = await FactoryRegistry.shared.get(type) else {
            throw BlazeDBError.transactionFailed("No factory registered for \(T.self)")
        }
        
        return try await self.seed(type, count: count, generator: generator)
    }
    
    /// Create single object
    @discardableResult
    @MainActor
    public func create<T: BlazeStorable>(_ type: T.Type) throws -> T {
        guard let first = try self.create(type, count: 1).first else {
            throw NSError(domain: "DataSeeding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create test record of type \(type)"])
        }
        return first
    }
    
    /// Create single async
    @discardableResult
    public func create<T: BlazeStorable>(_ type: T.Type) async throws -> T {
        guard let first = try await self.create(type, count: 1).first else {
            throw NSError(domain: "DataSeeding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create test record of type \(type)"])
        }
        return first
    }
    
    // MARK: - Fixtures from JSON
    
    /// Load fixtures from JSON file
    ///
    /// Example JSON:
    /// ```json
    /// [
    ///   {"id": "...", "title": "Bug 1", "priority": 5},
    ///   {"id": "...", "title": "Bug 2", "priority": 3}
    /// ]
    /// ```
    public func loadFixtures<T: BlazeStorable>(
        _ type: T.Type,
        from fileURL: URL
    ) throws -> [T] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let objects = try decoder.decode([T].self, from: data)
        _ = try self.insertMany(objects)
        
        return objects
    }
    
    /// Load fixtures async
    public func loadFixtures<T: BlazeStorable>(
        _ type: T.Type,
        from fileURL: URL
    ) async throws -> [T] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let objects = try decoder.decode([T].self, from: data)
        _ = try await self.insertMany(objects)
        
        return objects
    }
    
    /// Load BlazeDataRecord fixtures
    public func loadFixtures(from fileURL: URL) throws -> [UUID] {
        let data = try Data(contentsOf: fileURL)
        let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        
        guard let jsonArray = jsonArray else {
            throw BlazeDBError.transactionFailed("Invalid JSON format for fixtures")
        }
        
        var records: [BlazeDataRecord] = []
        
        for jsonObject in jsonArray {
            var storage: [String: BlazeDocumentField] = [:]
            
            for (key, value) in jsonObject {
                storage[key] = try convertJSONValue(value)
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        return try self.insertMany(records)
    }
    
    // MARK: - Snapshots
    
    /// Create a snapshot of current database state
    ///
    /// Example:
    /// ```swift
    /// let snapshot = try db.snapshot()
    /// // ... run tests ...
    /// try db.restore(snapshot)  // Restore to original state
    /// ```
    public func snapshot() throws -> DatabaseSnapshot {
        let records = try self.fetchAll()
        return DatabaseSnapshot(records: records)
    }
    
    /// Restore from snapshot
    public func restore(_ snapshot: DatabaseSnapshot) throws {
        // Clear current data
        let currentRecords = try self.fetchAll()
        for record in currentRecords {
            if let id = record.storage["id"]?.uuidValue {
                try self.delete(id: id)
            }
        }
        
        // Restore snapshot data
        _ = try self.insertMany(snapshot.records)
    }
    
    /// Snapshot async
    public func snapshot() async throws -> DatabaseSnapshot {
        let records = try await self.fetchAll()
        return DatabaseSnapshot(records: records)
    }
    
    /// Restore async
    public func restore(_ snapshot: DatabaseSnapshot) async throws {
        let currentRecords = try await self.fetchAll()
        for record in currentRecords {
            if let id = record.storage["id"]?.uuidValue {
                try await self.delete(id: id)
            }
        }
        
        _ = try await self.insertMany(snapshot.records)
    }
}

// MARK: - Factory Registry

/// Thread-safe factory registry using MainActor isolation
@MainActor
internal class FactoryRegistry {
    static let shared = FactoryRegistry()
    
    private var factories: [String: Any] = [:]
    
    func register<T: BlazeStorable>(_ type: T.Type, generator: @escaping (Int) -> T) {
        let key = String(describing: type)
        factories[key] = generator
    }
    
    func get<T: BlazeStorable>(_ type: T.Type) -> (@Sendable (Int) -> T)? {
        let key = String(describing: type)
        return factories[key] as? @Sendable (Int) -> T
    }
    
    func clear() {
        factories.removeAll()
    }
}

// MARK: - Database Snapshot

public struct DatabaseSnapshot {
    let records: [BlazeDataRecord]
    let timestamp: Date
    
    internal init(records: [BlazeDataRecord]) {
        self.records = records
        self.timestamp = Date()
    }
}

// MARK: - JSON Conversion Helper

private func convertJSONValue(_ value: Any) throws -> BlazeDocumentField {
    switch value {
    case let str as String:
        // Try to parse as UUID
        if let uuid = UUID(uuidString: str) {
            return .uuid(uuid)
        }
        // Try to parse as ISO8601 date
        if let date = ISO8601DateFormatter().date(from: str) {
            return .date(date)
        }
        return .string(str)
    case let num as Int:
        return .int(num)
    case let num as Double:
        return .double(num)
    case let bool as Bool:
        return .bool(bool)
    case let array as [Any]:
        let fields = try array.map { try convertJSONValue($0) }
        return .array(fields)
    case let dict as [String: Any]:
        var dictFields: [String: BlazeDocumentField] = [:]
        for (key, val) in dict {
            dictFields[key] = try convertJSONValue(val)
        }
        return .dictionary(dictFields)
    default:
        throw BlazeDBError.transactionFailed("Unsupported JSON type: \(type(of: value))")
    }
}

// MARK: - Batch Seeding Helpers

extension BlazeDBClient {
    
    /// Seed with realistic random data
    public func seedRandom(
        count: Int,
        fields: [String: () -> BlazeDocumentField]
    ) throws -> [UUID] {
        var records: [BlazeDataRecord] = []
        
        for _ in 0..<count {
            var storage: [String: BlazeDocumentField] = [:]
            
            for (key, generator) in fields {
                storage[key] = generator()
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        return try self.insertMany(records)
    }
    
    /// Seed random async
    public func seedRandom(
        count: Int,
        fields: [String: () -> BlazeDocumentField]
    ) async throws -> [UUID] {
        var records: [BlazeDataRecord] = []
        
        for _ in 0..<count {
            var storage: [String: BlazeDocumentField] = [:]
            
            for (key, generator) in fields {
                storage[key] = generator()
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        return try await self.insertMany(records)
    }
}

// MARK: - Random Data Generators

public struct RandomData {
    
    /// Random title from common bug patterns
    public static func bugTitle() -> String {
        let prefixes = ["Login", "Signup", "Payment", "Profile", "Settings", "Dashboard"]
        let issues = ["broken", "not working", "crashes", "slow", "error", "glitch"]
        return "\(prefixes.randomElement()!) \(issues.randomElement()!)"
    }
    
    /// Random status
    public static func status() -> String {
        ["open", "in_progress", "closed", "archived"].randomElement()!
    }
    
    /// Random priority
    public static func priority() -> Int {
        Int.random(in: 1...10)
    }
    
    /// Random name
    public static func name() -> String {
        ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank"].randomElement()!
    }
    
    /// Random email
    public static func email() -> String {
        let name = RandomData.name().lowercased()
        let domains = ["example.com", "test.com", "demo.com"]
        return "\(name)@\(domains.randomElement()!)"
    }
    
    /// Random past date (within last N days)
    public static func pastDate(days: Int = 30) -> Date {
        let secondsInDay = 86400.0
        let randomSeconds = Double.random(in: 0...(Double(days) * secondsInDay))
        return Date().addingTimeInterval(-randomSeconds)
    }
    
    /// Random tags
    public static func tags(count: Int = 3) -> [String] {
        let allTags = ["critical", "ui", "backend", "frontend", "bug", "feature", "enhancement", "documentation"]
        return Array(allTags.shuffled().prefix(count))
    }
}

