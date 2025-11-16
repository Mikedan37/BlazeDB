import Foundation

// MARK: - Developer Experience Improvements

/// Cleaner field access - no more optional hell!
extension BlazeDataRecord {
    
    // MARK: - Cleaner Field Access (Non-Throwing with Defaults)
    // Note: Throwing versions exist in BlazeDocument.swift
    // These are convenience wrappers with sensible defaults
    
    /// Get string value with default (non-throwing)
    public func string(_ key: String, default defaultValue: String = "") -> String {
        self.storage[key]?.stringValue ?? defaultValue
    }
    
    /// Get int value with default (non-throwing)
    public func int(_ key: String, default defaultValue: Int = 0) -> Int {
        self.storage[key]?.intValue ?? defaultValue
    }
    
    /// Get double value with default (non-throwing)
    public func double(_ key: String, default defaultValue: Double = 0.0) -> Double {
        self.storage[key]?.doubleValue ?? defaultValue
    }
    
    /// Get bool value with default (non-throwing)
    public func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        self.storage[key]?.boolValue ?? defaultValue
    }
    
    /// Get date value with default (non-throwing)
    public func date(_ key: String, default defaultValue: Date = Date()) -> Date {
        self.storage[key]?.dateValue ?? defaultValue
    }
    
    /// Get UUID value with default (non-throwing)
    public func uuid(_ key: String, default defaultValue: UUID = UUID()) -> UUID {
        self.storage[key]?.uuidValue ?? defaultValue
    }
    
    /// Get array value with default (non-throwing)
    public func array(_ key: String, default defaultValue: [BlazeDocumentField] = []) -> [BlazeDocumentField] {
        self.storage[key]?.arrayValue ?? defaultValue
    }
    
    /// Get data value with default (non-throwing)
    public func data(_ key: String, default defaultValue: Data = Data()) -> Data {
        self.storage[key]?.dataValue ?? defaultValue
    }
    
    // MARK: - Fluent Builder Pattern
    
    /// Set a field value (fluent interface)
    @discardableResult
    public func set(_ key: String, to value: BlazeDocumentField) -> BlazeDataRecord {
        var copy = self
        copy.storage[key] = value
        return copy
    }
    
    /// Set a string field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: String) -> BlazeDataRecord {
        set(key, to: .string(value))
    }
    
    /// Set an int field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: Int) -> BlazeDataRecord {
        set(key, to: .int(value))
    }
    
    /// Set a double field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: Double) -> BlazeDataRecord {
        set(key, to: .double(value))
    }
    
    /// Set a bool field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: Bool) -> BlazeDataRecord {
        set(key, to: .bool(value))
    }
    
    /// Set a date field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: Date) -> BlazeDataRecord {
        set(key, to: .date(value))
    }
    
    /// Set a UUID field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: UUID) -> BlazeDataRecord {
        set(key, to: .uuid(value))
    }
    
    /// Set a data field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: Data) -> BlazeDataRecord {
        set(key, to: .data(value))
    }
    
    /// Set an array field (auto-wraps)
    @discardableResult
    public func set(_ key: String, to value: [BlazeDocumentField]) -> BlazeDataRecord {
        set(key, to: .array(value))
    }
    
    // MARK: - Convenience Initializers
    
    /// Create record with builder pattern
    public static func build(_ builder: (inout BlazeDataRecord) -> Void) -> BlazeDataRecord {
        var record = BlazeDataRecord([:])  // Empty storage dictionary
        builder(&record)
        return record
    }
}

// MARK: - Query Result Convenience

extension QueryResult {
    /// Get records directly (no try needed if you know it's .records)
    public var recordsOrEmpty: [BlazeDataRecord] {
        (try? self.records) ?? []
    }
    
    /// Get joined records directly
    public var joinedOrEmpty: [JoinedRecord] {
        (try? self.joined) ?? []
    }
    
    /// Get search results directly
    public var searchResultsOrEmpty: [FullTextSearchResult] {
        (try? self.searchResults) ?? []
    }
    
    // Note: .isEmpty and .count already exist on QueryResult in QueryResult.swift
}

// MARK: - BlazeDBClient Convenience

extension BlazeDBClient {
    
    /// Insert with builder pattern
    public func insert(_ builder: (inout BlazeDataRecord) -> Void) throws -> UUID {
        let record = BlazeDataRecord.build(builder)
        return try self.insert(record)
    }
    
    /// Insert async with builder pattern
    public func insertAsync(_ builder: (inout BlazeDataRecord) -> Void) async throws -> UUID {
        let record = BlazeDataRecord.build(builder)
        // Wrap sync call in async context
        return try await Task {
            try self.insert(record)
        }.value
    }
    
    /// Quick query - just get records
    public func find(where predicate: @escaping (BlazeDataRecord) -> Bool) throws -> [BlazeDataRecord] {
        try self.query()
            .where(predicate)
            .execute()
            .records
    }
    
    /// Quick query async
    public func find(where predicate: @escaping (BlazeDataRecord) -> Bool) async throws -> [BlazeDataRecord] {
        try await self.query()
            .where(predicate)
            .execute()
            .records
    }
    
    /// Find one record
    public func findOne(where predicate: @escaping (BlazeDataRecord) -> Bool) throws -> BlazeDataRecord? {
        try self.query()
            .where(predicate)
            .limit(1)
            .execute()
            .records
            .first
    }
    
    /// Find one async
    public func findOne(where predicate: @escaping (BlazeDataRecord) -> Bool) async throws -> BlazeDataRecord? {
        try await self.query()
            .where(predicate)
            .limit(1)
            .execute()
            .records
            .first
    }
    
    /// Quick count with filter
    public func count(where predicate: @escaping (BlazeDataRecord) -> Bool) throws -> Int {
        try self.query()
            .where(predicate)
            .count()
            .execute()
            .aggregation
            .count ?? 0
    }
    
    /// Quick count async
    public func count(where predicate: @escaping (BlazeDataRecord) -> Bool) async throws -> Int {
        try await self.query()
            .where(predicate)
            .count()
            .execute()
            .aggregation
            .count ?? 0
    }
    
    /// Update with builder
    public func update(id: UUID, _ builder: (inout BlazeDataRecord) -> Void) throws {
        guard let existing = try self.fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        var updated = existing
        builder(&updated)
        try self.update(id: id, with: updated)
    }
    
    /// Update async with builder
    public func updateAsync(id: UUID, _ builder: (inout BlazeDataRecord) -> Void) async throws {
        guard let existing = try await self.fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        var updated = existing
        builder(&updated)
        
        // Wrap sync call in async context
        try await Task {
            try self.update(id: id, with: updated)
        }.value
    }
}

// MARK: - QueryBuilder Convenience

extension QueryBuilder {
    
    /// Get records directly (shortcut)
    public func all() throws -> [BlazeDataRecord] {
        try self.execute().records
    }
    
    /// Get records async (shortcut)
    public func all() async throws -> [BlazeDataRecord] {
        try await self.execute().records
    }
    
    /// Get first record
    public func first() throws -> BlazeDataRecord? {
        try self.limit(1).execute().records.first
    }
    
    /// Get first async
    public func first() async throws -> BlazeDataRecord? {
        try await self.limit(1).execute().records.first
    }
    
    /// Check if any records match
    public func exists() throws -> Bool {
        try self.limit(1).execute().records.isEmpty == false
    }
    
    /// Check if any records match async
    public func exists() async throws -> Bool {
        try await self.limit(1).execute().records.isEmpty == false
    }
    
    /// Quick count
    public func quickCount() throws -> Int {
        try self.count().execute().aggregation.count ?? 0
    }
    
    /// Quick count async
    public func quickCount() async throws -> Int {
        try await self.count().execute().aggregation.count ?? 0
    }
}

