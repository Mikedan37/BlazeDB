//
//  BlazeDocument.swift
//  BlazeDB
//
//  Type-safe document protocol and Field property wrapper.
//  Provides compile-time safety while maintaining BlazeDB's dynamic flexibility.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import Foundation

// MARK: - BlazeDocument Protocol

/// Protocol for manual typed model support.
///
/// For most use cases, prefer ``BlazeStorable`` which provides automatic
/// Codable-based serialization and KeyPath query support. Use `BlazeDocument`
/// only when you need manual control over how your model maps to and from
/// `BlazeDataRecord` storage.
///
/// Example:
/// ```swift
/// struct Bug: BlazeDocument {
///     var id: UUID
///     var title: String
///     var priority: Int
///     var status: String
///     var assignee: String?
///     var tags: [String] = []
///     var createdAt: Date = Date()
///
///     func toStorage() throws -> BlazeDataRecord { ... }
///     init(from storage: BlazeDataRecord) throws { ... }
/// }
/// ```
public protocol BlazeDocument: Codable, Identifiable where ID == UUID {
    var id: UUID { get set }
    
    /// Access to underlying storage for dynamic fields
    var storage: BlazeDataRecord { get set }
    
    /// Convert this document to a BlazeDataRecord for storage
    func toStorage() throws -> BlazeDataRecord
    
    /// Initialize from a BlazeDataRecord
    init(from storage: BlazeDataRecord) throws
}

// Default implementations
extension BlazeDocument {
    /// Default implementation provides access to storage
    public var storage: BlazeDataRecord {
        get {
            do {
                return try toStorage()
            } catch {
                BlazeLogger.error("Failed to convert document to storage: \(error)")
                return BlazeDataRecord([:])
            }
        }
        set {
            // Storage is read-only by default
            // Individual fields should be set via their property wrappers
        }
    }
}

// MARK: - Field Property Wrapper

/// Property wrapper for type-safe fields in BlazeDocument models.
///
/// Automatically handles conversion between Swift types and BlazeDocumentField values.
///
/// Supported types:
/// - String
/// - Int, Int8, Int16, Int32, Int64
/// - UInt, UInt8, UInt16, UInt32, UInt64
/// - Double, Float
/// - Bool
/// - Date
/// - UUID
/// - Data
/// - Array<T> where T is a supported type
/// - Dictionary<String, T> where T is a supported type
/// - Optional<T> where T is a supported type
///
/// Example:
/// ```swift
/// struct Bug {
///     @Field var title: String
///     @Field var priority: Int
///     @Field var assignee: String?
///     @Field var tags: [String] = []
/// }
/// ```
@available(*, unavailable, message: "Macro support is not implemented. Use BlazeStorable (Codable-based) or BlazeDocument protocol for typed models.")
@propertyWrapper
public struct Field<Value> {
    // experiment/field-trap-removal: fatalError traps replaced with no-op stubs
    // to test whether Linux test discovery hits these inits via reflection.
    private var _storage: Value?

    public var wrappedValue: Value {
        get { _storage! }
        set { _storage = newValue }
    }

    public init(wrappedValue: Value) {
        self._storage = wrappedValue
    }

    public init(_ key: String) {
        self._storage = nil
    }

    public init(_ key: String, defaultValue: Value) {
        self._storage = defaultValue
    }
}

// MARK: - BlazeDocument Macro (Manual Implementation)

/// Macro to generate BlazeDocument conformance.
///
/// This is a placeholder for a proper Swift macro. For now, users need to manually
/// implement the protocol methods, or we provide a code generator.
///
/// Example manual implementation:
/// ```swift
/// struct Bug: BlazeDocument {
///     var id: UUID = UUID()
///     var title: String
///     var priority: Int
///     var assignee: String?
///
///     func toStorage() throws -> BlazeDataRecord {
///         return BlazeDataRecord([
///             "id": .uuid(id),
///             "title": .string(title),
///             "priority": .int(priority),
///             "assignee": assignee.map { .string($0) }
///         ])
///     }
///
///     init(from storage: BlazeDataRecord) throws {
///         guard let id = storage["id"]?.uuidValue else {
///             throw BlazeDBError.transactionFailed("Missing or invalid id")
///         }
///         guard let title = storage["title"]?.stringValue else {
///             throw BlazeDBError.transactionFailed("Missing or invalid title")
///         }
///         guard let priority = storage["priority"]?.intValue else {
///             throw BlazeDBError.transactionFailed("Missing or invalid priority")
///         }
///
///         self.id = id
///         self.title = title
///         self.priority = priority
///         self.assignee = storage["assignee"]?.stringValue
///     }
/// }
/// ```

// MARK: - Convenience Initializers

extension BlazeDocument {
    /// Initialize from a dictionary of field values
    public init(fields: [String: BlazeDocumentField]) throws {
        let record = BlazeDataRecord(fields)
        try self.init(from: record)
    }
}

// MARK: - Type Conversion Helpers

extension BlazeDataRecord {
    /// Extract a UUID value for a given key
    public func uuid(_ key: String) throws -> UUID {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let uuid = value.uuidValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a UUID")
        }
        return uuid
    }
    
    /// Extract an optional UUID value
    public func uuidOptional(_ key: String) -> UUID? {
        return self.storage[key]?.uuidValue
    }
    
    /// Extract a String value
    public func string(_ key: String) throws -> String {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let string = value.stringValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a String")
        }
        return string
    }
    
    /// Extract an optional String value
    public func stringOptional(_ key: String) -> String? {
        return self.storage[key]?.stringValue
    }
    
    /// Extract an Int value
    public func int(_ key: String) throws -> Int {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let int = value.intValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not an Int")
        }
        return int
    }
    
    /// Extract an optional Int value
    public func intOptional(_ key: String) -> Int? {
        return self.storage[key]?.intValue
    }
    
    /// Extract a Double value
    public func double(_ key: String) throws -> Double {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let double = value.doubleValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a Double")
        }
        return double
    }
    
    /// Extract an optional Double value
    public func doubleOptional(_ key: String) -> Double? {
        return self.storage[key]?.doubleValue
    }
    
    /// Extract a Bool value
    public func bool(_ key: String) throws -> Bool {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let bool = value.boolValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a Bool")
        }
        return bool
    }
    
    /// Extract an optional Bool value
    public func boolOptional(_ key: String) -> Bool? {
        return self.storage[key]?.boolValue
    }
    
    /// Extract a Date value
    public func date(_ key: String) throws -> Date {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let date = value.dateValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a Date")
        }
        return date
    }
    
    /// Extract an optional Date value
    public func dateOptional(_ key: String) -> Date? {
        return self.storage[key]?.dateValue
    }
    
    /// Extract a Data value
    public func data(_ key: String) throws -> Data {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let data = value.dataValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not Data")
        }
        return data
    }
    
    /// Extract an optional Data value
    public func dataOptional(_ key: String) -> Data? {
        return self.storage[key]?.dataValue
    }
    
    /// Extract an Array value
    public func array(_ key: String) throws -> [BlazeDocumentField] {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let array = value.arrayValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not an Array")
        }
        return array
    }
    
    /// Extract an optional Array value
    public func arrayOptional(_ key: String) -> [BlazeDocumentField]? {
        return self.storage[key]?.arrayValue
    }
    
    /// Extract a Dictionary value
    public func dictionary(_ key: String) throws -> [String: BlazeDocumentField] {
        guard let value = self.storage[key] else {
            throw BlazeDBError.invalidData(reason: "Missing field: \(key)")
        }
        guard let dict = value.dictionaryValue else {
            throw BlazeDBError.invalidData(reason: "Field '\(key)' is not a Dictionary")
        }
        return dict
    }
    
    /// Extract an optional Dictionary value
    public func dictionaryOptional(_ key: String) -> [String: BlazeDocumentField]? {
        return self.storage[key]?.dictionaryValue
    }
}

// MARK: - Array Helper Extensions

extension Array where Element == BlazeDocumentField {
    /// Convert array of BlazeDocumentField to array of String
    public var stringValues: [String] {
        return compactMap { field in
            // Try string first
            if let str = field.stringValue {
                return str
            }
            // If stored as Data, try to decode as UTF-8 string
            if case .data(let data) = field, let str = String(data: data, encoding: .utf8) {
                return str
            }
            return nil
        }
    }
    
    /// Convert array of BlazeDocumentField to array of Int
    public var intValues: [Int] {
        return compactMap { $0.intValue }
    }
    
    /// Convert array of BlazeDocumentField to array of Double
    public var doubleValues: [Double] {
        return compactMap { $0.doubleValue }
    }
}

// MARK: - Dictionary Helper Extensions

extension Dictionary where Key == String, Value == BlazeDocumentField {
    /// Convert dictionary of BlazeDocumentField to dictionary of String
    public var stringValues: [String: String] {
        return compactMapValues { $0.stringValue }
    }
    
    /// Convert dictionary of BlazeDocumentField to dictionary of Int
    public var intValues: [String: Int] {
        return compactMapValues { $0.intValue }
    }
}

