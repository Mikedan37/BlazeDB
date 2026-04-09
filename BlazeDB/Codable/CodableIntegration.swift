import Foundation
import CoreFoundation

// MARK: - Direct Codable Support for BlazeDB

/// The recommended protocol for typed model support.
///
/// Conform to `BlazeStorable` to get automatic Codable serialization,
/// type-safe KeyPath queries, and access to the ergonomic `TypedStore` API.
///
/// ```swift
/// struct Task: BlazeStorable {
///     var id: UUID = UUID()
///     var title: String
///     var priority: Int
///     var isComplete: Bool
/// }
///
/// let tasks = db.typed(Task.self)
/// try tasks.insert(Task(title: "Ship v3", priority: 9, isComplete: false))
///
/// let urgent = try tasks.query()
///     .where(\.priority, greaterThanOrEqual: 7)
///     .all()
/// ```
///
/// ## When to use BlazeDocument instead
/// - You need manual control over storage mapping
/// - Your type cannot conform to Codable
/// - You need custom field translation logic
public protocol BlazeStorable: Codable, Identifiable where ID == UUID {
    var id: UUID { get set }
}

// MARK: - Automatic Conversion Helpers

extension BlazeStorable {
    
    /// Convert any Codable to BlazeDataRecord
    internal func toBlazeRecord() throws -> BlazeDataRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(self)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        guard let jsonObject = jsonObject else {
            throw BlazeDBError.invalidData(reason: "Failed to convert Codable to JSON")
        }
        
        var storage: [String: BlazeDocumentField] = [:]
        
        for (key, value) in jsonObject {
            storage[key] = try convertToBlazeField(value)
        }
        
        return BlazeDataRecord(storage)
    }
    
    /// Convert BlazeDataRecord back to Codable.
    ///
    /// Uses a two-pass strategy:
    /// 1. Primary path treats `.string(...)` values as literal strings (correct
    ///    for data written after the issue-#80 fix and for any plain-String field).
    /// 2. Legacy fallback re-parses `.string(...)` values as JSON for databases
    ///    that stored nested Codable objects as `.string(json)` before the fix.
    internal static func fromBlazeRecord(_ record: BlazeDataRecord) throws -> Self {
        BlazeLogger.debug("fromBlazeRecord: Converting \(record.storage.count) fields")

        // Primary path — strings stay as strings
        if let result = try? decodeRecord(record, legacyJSONStringParsing: false) {
            return result
        }

        // Legacy fallback — parse .string(...) as JSON for old nested-object storage
        return try decodeRecord(record, legacyJSONStringParsing: true)
    }

    private static func decodeRecord(
        _ record: BlazeDataRecord,
        legacyJSONStringParsing: Bool
    ) throws -> Self {
        var jsonObject: [String: Any] = [:]

        for (key, field) in record.storage {
            BlazeLogger.debug("  Processing field '\(key)': \(String(describing: field).prefix(100))...")
            jsonObject[key] = try convertToJSON(field, legacyJSONStringParsing: legacyJSONStringParsing)
        }

        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: jsonData)
    }
}

// MARK: - Conversion Helpers

private func convertToBlazeField(_ value: Any) throws -> BlazeDocumentField {
    switch value {
    case let str as String:
        return .string(str)
    case let number as NSNumber:
        // JSONSerialization bridges numbers/bools through NSNumber.
        // Distinguish true booleans from numeric values explicitly.
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        let decimal = Decimal(string: number.stringValue) ?? Decimal(number.doubleValue)
        if NSDecimalNumber(decimal: decimal).doubleValue.rounded(.towardZero) == number.doubleValue {
            return .int(number.intValue)
        }
        return .double(number.doubleValue)
    case let date as Date:
        return .date(date)
    case let uuid as UUID:
        return .uuid(uuid)
    case let data as Data:
        return .data(data)
    case let array as [Any]:
        let fields = try array.map { try convertToBlazeField($0) }
        return .array(fields)
    case let dict as [String: Any]:
        var fields: [String: BlazeDocumentField] = [:]
        for (k, v) in dict {
            fields[k] = try convertToBlazeField(v)
        }
        return .dictionary(fields)
    default:
        // Handle ISO8601 date strings
        if let str = value as? String, let date = ISO8601DateFormatter().date(from: str) {
            return .date(date)
        }
        throw BlazeDBError.invalidData(reason: "Unsupported type during Codable conversion: \(type(of: value))")
    }
}

private func convertToJSON(
    _ field: BlazeDocumentField,
    legacyJSONStringParsing: Bool = false
) throws -> Any {
    switch field {
    case .string(let str):
        // After issue-#80 fix, nested objects are stored as .dictionary(...)
        // so plain .string values are always literal strings.
        // Legacy fallback: re-parse .string as JSON for databases written
        // before the fix that stored nested Codable objects as .string(json).
        if legacyJSONStringParsing,
           let data = str.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        return str
    case .int(let num):
        return num
    case .double(let num):
        return num
    case .bool(let bool):
        return bool
    case .date(let date):
        return ISO8601DateFormatter().string(from: date)
    case .uuid(let uuid):
        return uuid.uuidString
    case .data(let data):
        return data.base64EncodedString()
    case .array(let array):
        return try array.map { try convertToJSON($0, legacyJSONStringParsing: legacyJSONStringParsing) }
    case .dictionary(let dict):
        var jsonDict: [String: Any] = [:]
        for (key, value) in dict {
            jsonDict[key] = try convertToJSON(value, legacyJSONStringParsing: legacyJSONStringParsing)
        }
        return jsonDict
    case .vector(let vector):
        return vector.map { $0 }
    case .null:
        return NSNull()
    }
}

// MARK: - BlazeDBClient Codable Extensions

extension BlazeDBClient {
    
    // MARK: - Insert
    
    /// Insert any Codable type directly
    ///
    /// Example:
    /// ```swift
    /// struct Bug: Codable, Identifiable {
    ///     var id: UUID
    ///     var title: String
    ///     var priority: Int
    /// }
    ///
    /// let bug = Bug(id: UUID(), title: "Login broken", priority: 5)
    /// try db.insert(bug)
    /// ```
    public func insert<T: BlazeStorable>(_ object: T) throws -> UUID {
        let record = try object.toBlazeRecord()
        return try self.insert(record)
    }
    
    /// Insert Codable async
    public func insert<T: BlazeStorable>(_ object: T) async throws -> UUID {
        let record = try object.toBlazeRecord()
        return try await self.insert(record)
    }
    
    /// Insert many Codable objects
    public func insertMany<T: BlazeStorable>(_ objects: [T]) throws -> [UUID] {
        let records = try objects.map { try $0.toBlazeRecord() }
        return try self.insertMany(records)
    }
    
    /// Insert many async
    public func insertMany<T: BlazeStorable>(_ objects: [T]) async throws -> [UUID] {
        let records = try objects.map { try $0.toBlazeRecord() }
        return try await self.insertMany(records)
    }
    
    // MARK: - Fetch
    
    /// Fetch Codable type by ID
    ///
    /// Example:
    /// ```swift
    /// let bug = try db.fetch(Bug.self, id: bugID)
    /// print(bug?.title)
    /// ```
    public func fetch<T: BlazeStorable>(_ type: T.Type, id: UUID) throws -> T? {
        guard let record = try self.fetch(id: id) else {
            return nil
        }
        return try T.fromBlazeRecord(record)
    }
    
    /// Fetch async
    public func fetch<T: BlazeStorable>(_ type: T.Type, id: UUID) async throws -> T? {
        guard let record = try await self.fetch(id: id) else {
            return nil
        }
        return try T.fromBlazeRecord(record)
    }
    
    /// Fetch all as Codable type
    public func fetchAll<T: BlazeStorable>(_ type: T.Type) throws -> [T] {
        let records = try self.fetchAll()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    /// Fetch all async
    public func fetchAll<T: BlazeStorable>(_ type: T.Type) async throws -> [T] {
        let records = try await self.fetchAll()
        return try records.map { try T.fromBlazeRecord($0) }
    }
    
    // MARK: - Update
    
    /// Update Codable object
    public func update<T: BlazeStorable>(_ object: T) throws {
        let record = try object.toBlazeRecord()
        try self.update(id: object.id, with: record)
    }
    
    /// Update async
    public func update<T: BlazeStorable>(_ object: T) async throws {
        let record = try object.toBlazeRecord()
        try await self.update(id: object.id, data: record)
    }
    
    /// Update many Codable objects
    public func updateMany<T: BlazeStorable>(_ objects: [T]) throws {
        for object in objects {
            try self.update(object)
        }
    }
    
    /// Update many async
    public func updateMany<T: BlazeStorable>(_ objects: [T]) async throws {
        for object in objects {
            try await self.update(object)
        }
    }
    
    // Note: Type-safe query builder is defined in QueryBuilderKeyPath.swift
    // This avoids duplication and uses the KeyPath-enabled builder
}

