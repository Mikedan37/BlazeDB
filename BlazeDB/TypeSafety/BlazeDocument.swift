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

/// Protocol for type-safe document models.
///
/// Conform to this protocol to get compile-time type safety for your database models
/// while maintaining BlazeDB's flexibility and zero-migration philosophy.
///
/// Example:
/// ```swift
/// @BlazeDocument
/// struct Bug: Identifiable {
///     @Field var id: UUID = UUID()
///     @Field var title: String
///     @Field var priority: Int
///     @Field var status: String
///     @Field var assignee: String?
///     @Field var tags: [String] = []
///     @Field var createdAt: Date = Date()
///
///     var isHighPriority: Bool {
///         priority >= 7
///     }
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
@propertyWrapper
public struct Field<Value> {
    private let key: String
    private var defaultValue: Value?
    
    public var wrappedValue: Value {
        get {
            // Log error and return default value instead of crashing
            BlazeLogger.error("@Field can only be used within a @BlazeDocument struct. This indicates a programming error.")
            if let defaultValue = defaultValue {
                return defaultValue
            }
            // If no default, use preconditionFailure (better than fatalError - can be caught in debug)
            preconditionFailure("@Field can only be used within a @BlazeDocument struct. Provide a default value or use @BlazeDocument.")
        }
        set {
            // Log error instead of crashing
            BlazeLogger.error("@Field can only be used within a @BlazeDocument struct. Attempted to set value: \(newValue). This indicates a programming error.")
            // Property setters can't throw, so we log and do nothing
            // The value won't be stored, but the app won't crash
        }
    }
    
    public init(wrappedValue: Value) {
        self.key = ""
        self.defaultValue = wrappedValue
    }
    
    public init() where Value: ExpressibleByNilLiteral {
        self.key = ""
        self.defaultValue = nil
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let uuid = value.uuidValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a UUID")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let string = value.stringValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a String")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let int = value.intValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not an Int")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let double = value.doubleValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a Double")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let bool = value.boolValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a Bool")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let date = value.dateValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a Date")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let data = value.dataValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not Data")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let array = value.arrayValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not an Array")
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
            throw BlazeDBError.transactionFailed("Missing field: \(key)")
        }
        guard let dict = value.dictionaryValue else {
            throw BlazeDBError.transactionFailed("Field '\(key)' is not a Dictionary")
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

