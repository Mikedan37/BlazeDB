import Foundation

// MARK: - Modern Swift DSL for Record Creation

/// Result builder for creating BlazeDataRecords with clean syntax
@resultBuilder
public struct RecordBuilder {
    public static func buildBlock(_ components: RecordField...) -> [RecordField] {
        components
    }
    
    public static func buildOptional(_ component: [RecordField]?) -> [RecordField] {
        component ?? []
    }
    
    public static func buildEither(first component: [RecordField]) -> [RecordField] {
        component
    }
    
    public static func buildEither(second component: [RecordField]) -> [RecordField] {
        component
    }
    
    public static func buildArray(_ components: [[RecordField]]) -> [RecordField] {
        components.flatMap { $0 }
    }
}

/// Field in a record
public struct RecordField {
    let key: String
    let value: BlazeDocumentField
    
    public init(_ key: String, _ value: BlazeDocumentField) {
        self.key = key
        self.value = value
    }
    
    // Convenience initializers for auto-wrapping
    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = .string(value)
    }
    
    public init(_ key: String, _ value: Int) {
        self.key = key
        self.value = .int(value)
    }
    
    public init(_ key: String, _ value: Double) {
        self.key = key
        self.value = .double(value)
    }
    
    public init(_ key: String, _ value: Bool) {
        self.key = key
        self.value = .bool(value)
    }
    
    public init(_ key: String, _ value: Date) {
        self.key = key
        self.value = .date(value)
    }
    
    public init(_ key: String, _ value: UUID) {
        self.key = key
        self.value = .uuid(value)
    }
    
    public init(_ key: String, _ value: Data) {
        self.key = key
        self.value = .data(value)
    }
    
    public init(_ key: String, _ value: [BlazeDocumentField]) {
        self.key = key
        self.value = .array(value)
    }
    
    public init(_ key: String, _ value: [String]) {
        self.key = key
        self.value = .array(value.map { .string($0) })
    }
}

/// Custom operator for cleaner field syntax
infix operator =>: AssignmentPrecedence

public func => (key: String, value: String) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: Int) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: Double) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: Bool) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: Date) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: UUID) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: Data) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: [BlazeDocumentField]) -> RecordField {
    RecordField(key, value)
}

public func => (key: String, value: [String]) -> RecordField {
    RecordField(key, value)
}

// MARK: - BlazeDataRecord DSL Extension

extension BlazeDataRecord {
    
    /// Create record with DSL syntax
    ///
    /// Example:
    /// ```swift
    /// let bug = BlazeDataRecord {
    ///     "title" => "Login broken"
    ///     "priority" => 3
    ///     "status" => "open"
    ///     "createdAt" => Date()
    /// }
    /// ```
    public init(@RecordBuilder _ builder: () -> [RecordField]) {
        let fields = builder()
        var storage: [String: BlazeDocumentField] = [:]
        
        for field in fields {
            storage[field.key] = field.value
        }
        
        self.init(storage)
    }
    
    /// Create record with mixed DSL and dictionary
    public init(id: UUID? = nil, @RecordBuilder _ builder: () -> [RecordField]) {
        let fields = builder()
        var storage: [String: BlazeDocumentField] = [:]
        
        if let id = id {
            storage["id"] = .uuid(id)
        }
        
        for field in fields {
            storage[field.key] = field.value
        }
        
        self.init(storage)
    }
}

// MARK: - Quick Record Creation

extension BlazeDataRecord {
    
    /// Create record from key-value pairs (Swift 5.9+ dictionary literal)
    public static func from(_ pairs: (String, BlazeDocumentField)...) -> BlazeDataRecord {
        var storage: [String: BlazeDocumentField] = [:]
        for (key, value) in pairs {
            storage[key] = value
        }
        return BlazeDataRecord(storage)
    }
    
    /// Create with string values
    public static func strings(_ pairs: (String, String)...) -> BlazeDataRecord {
        var storage: [String: BlazeDocumentField] = [:]
        for (key, value) in pairs {
            storage[key] = .string(value)
        }
        return BlazeDataRecord(storage)
    }
}

// MARK: - QueryBuilder Field Shortcuts

extension QueryBuilder {
    
    /// Where clause with auto-wrapping
    @discardableResult
    public func `where`(_ field: String, equals value: String) -> QueryBuilder {
        self.where(field, equals: .string(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, equals value: Int) -> QueryBuilder {
        self.where(field, equals: .int(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, equals value: Double) -> QueryBuilder {
        self.where(field, equals: .double(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, equals value: Bool) -> QueryBuilder {
        self.where(field, equals: .bool(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, equals value: Date) -> QueryBuilder {
        self.where(field, equals: .date(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, equals value: UUID) -> QueryBuilder {
        self.where(field, equals: .uuid(value))
    }
    
    // Greater than with auto-wrapping
    @discardableResult
    public func `where`(_ field: String, greaterThan value: Int) -> QueryBuilder {
        self.where(field, greaterThan: .int(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, greaterThan value: Double) -> QueryBuilder {
        self.where(field, greaterThan: .double(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, greaterThan value: Date) -> QueryBuilder {
        self.where(field, greaterThan: .date(value))
    }
    
    // Less than with auto-wrapping
    @discardableResult
    public func `where`(_ field: String, lessThan value: Int) -> QueryBuilder {
        self.where(field, lessThan: .int(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, lessThan value: Double) -> QueryBuilder {
        self.where(field, lessThan: .double(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, lessThan value: Date) -> QueryBuilder {
        self.where(field, lessThan: .date(value))
    }
    
    // Not equals with auto-wrapping
    @discardableResult
    public func `where`(_ field: String, notEquals value: String) -> QueryBuilder {
        self.where(field, notEquals: .string(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, notEquals value: Int) -> QueryBuilder {
        self.where(field, notEquals: .int(value))
    }
    
    @discardableResult
    public func `where`(_ field: String, notEquals value: Bool) -> QueryBuilder {
        self.where(field, notEquals: .bool(value))
    }
}

