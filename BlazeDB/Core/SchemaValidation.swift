//
//  SchemaValidation.swift
//  BlazeDB
//
//  Runtime schema validation and enforcement
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Schema Definition

public struct FieldSchema {
    public indirect enum FieldType {
        case string
        case int
        case double
        case bool
        case date
        case uuid
        case data
        case array(FieldType)
        case dictionary
        case any  // No type restriction
    }
    
    public let name: String
    public let type: FieldType
    public let required: Bool
    public let defaultValue: BlazeDocumentField?
    public let validator: ((BlazeDocumentField) -> Bool)?
    
    public init(
        name: String,
        type: FieldType,
        required: Bool = false,
        defaultValue: BlazeDocumentField? = nil,
        validator: ((BlazeDocumentField) -> Bool)? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.validator = validator
    }
}

public struct DatabaseSchema {
    public let fields: [FieldSchema]
    public let strict: Bool  // If true, reject fields not in schema
    
    public init(fields: [FieldSchema], strict: Bool = false) {
        self.fields = fields
        self.strict = strict
    }
    
    /// Validate a record against this schema
    public func validate(_ record: BlazeDataRecord) throws {
        // Check required fields
        for field in fields where field.required {
            guard record.storage[field.name] != nil else {
                throw BlazeDBError.invalidField(
                    name: field.name,
                    expectedType: "\(field.type)",
                    actualType: "missing (required)"
                )
            }
        }
        
        // Check field types
        for field in fields {
            guard let value = record.storage[field.name] else {
                // Missing field - OK if not required
                continue
            }
            
            if !isValidType(value, expectedType: field.type) {
                throw BlazeDBError.invalidField(
                    name: field.name,
                    expectedType: "\(field.type)",
                    actualType: "\(type(of: value))"
                )
            }
            
            // Custom validator
            if let validator = field.validator, !validator(value) {
                throw BlazeDBError.invalidData(reason: "Field '\(field.name)' failed validation")
            }
        }
        
        // Strict mode: reject unknown fields
        if strict {
            let knownFields = Set(fields.map { $0.name })
            for key in record.storage.keys {
                if !knownFields.contains(key) && key != "id" {
                    throw BlazeDBError.invalidField(
                        name: key,
                        expectedType: "not in schema",
                        actualType: "unknown field"
                    )
                }
            }
        }
    }
    
    private func isValidType(_ value: BlazeDocumentField, expectedType: FieldSchema.FieldType) -> Bool {
        switch expectedType {
        case .string:
            if case .string = value { return true }
        case .int:
            if case .int = value { return true }
        case .double:
            if case .double = value { return true }
            if case .int = value { return true }  // Int can be treated as Double
        case .bool:
            if case .bool = value { return true }
        case .date:
            if case .date = value { return true }
        case .uuid:
            if case .uuid = value { return true }
        case .data:
            if case .data = value { return true }
        case .array:
            if case .array = value { return true }
        case .dictionary:
            if case .dictionary = value { return true }
        case .any:
            return true
        }
        
        return false
    }
}

// MARK: - BlazeDBClient Schema Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var schemas: [String: DatabaseSchema] = [:]
    nonisolated(unsafe) private static let schemaLock = NSLock()
    
    /// Define a schema for this database
    ///
    /// Validates all future inserts and updates against the schema.
    ///
    /// - Parameter schema: Schema definition
    ///
    /// ## Example
    /// ```swift
    /// let schema = DatabaseSchema(fields: [
    ///     FieldSchema(name: "title", type: .string, required: true),
    ///     FieldSchema(name: "priority", type: .int, required: true, validator: { field in
    ///         if case .int(let value) = field {
    ///             return value >= 1 && value <= 5
    ///         }
    ///         return false
    ///     }),
    ///     FieldSchema(name: "tags", type: .array(.string)),
    ///     FieldSchema(name: "created_at", type: .date, required: true)
    /// ], strict: true)
    ///
    /// db.defineSchema(schema)
    /// ```
    public func defineSchema(_ schema: DatabaseSchema) {
        let key = "\(name)-\(fileURL.path)"
        
        Self.schemaLock.lock()
        Self.schemas[key] = schema
        Self.schemaLock.unlock()
        
        BlazeLogger.info("📋 Schema defined for '\(name)' with \(schema.fields.count) fields")
    }
    
    /// Remove schema validation
    public func removeSchema() {
        let key = "\(name)-\(fileURL.path)"
        
        Self.schemaLock.lock()
        Self.schemas.removeValue(forKey: key)
        Self.schemaLock.unlock()
        
        BlazeLogger.info("📋 Schema removed for '\(name)'")
    }
    
    /// Validate a record against the current schema
    internal func validateAgainstSchema(_ record: BlazeDataRecord) throws {
        let key = "\(name)-\(fileURL.path)"
        
        Self.schemaLock.lock()
        let schema = Self.schemas[key]
        Self.schemaLock.unlock()
        
        try schema?.validate(record)
    }
}

