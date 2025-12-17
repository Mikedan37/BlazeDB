//
//  UniqueConstraints.swift
//  BlazeDB
//
//  Unique constraint enforcement at database level
//  Optimized with index-based lookups
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Unique Constraint Manager

public class UniqueConstraintManager {
    private var uniqueFields: Set<String> = []
    private var uniqueCompoundFields: Set<String> = []  // "field1+field2"
    private let lock = NSLock()
    
    public init() {}
    
    /// Mark field as unique
    public func addUniqueField(_ field: String) {
        lock.lock()
        defer { lock.unlock() }
        uniqueFields.insert(field)
        BlazeLogger.info("Added unique constraint on field '\(field)'")
    }
    
    /// Mark compound fields as unique
    public func addUniqueCompoundFields(_ fields: [String]) {
        lock.lock()
        defer { lock.unlock() }
        let key = fields.joined(separator: "+")
        uniqueCompoundFields.insert(key)
        BlazeLogger.info("Added unique constraint on compound fields '\(key)'")
    }
    
    /// Remove unique constraint
    public func removeUniqueField(_ field: String) {
        lock.lock()
        defer { lock.unlock() }
        uniqueFields.remove(field)
        BlazeLogger.info("Removed unique constraint on field '\(field)'")
    }
    
    /// Check if field is unique
    public func isUniqueField(_ field: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return uniqueFields.contains(field)
    }
    
    /// Check if compound fields are unique
    public func isUniqueCompoundFields(_ fields: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = fields.joined(separator: "+")
        return uniqueCompoundFields.contains(key)
    }
    
    /// Validate unique constraint before insert
    public func validateUnique(collection: DynamicCollection, record: BlazeDataRecord, excludeId: UUID? = nil) throws {
        // Check single-field unique constraints
        for field in uniqueFields {
            guard let value = record.storage[field] else { continue }
            
            // Check if another record has this value
            // Use query instead of direct index fetch (more reliable)
            let queryBuilder = QueryBuilder(collection: collection)
            queryBuilder.where(field, equals: value)
            let existing = try queryBuilder.execute()
            let records = try existing.records
            let conflicting = records.filter { record in
                guard let recordId = record.storage["id"]?.uuidValue else { return false }
                return recordId != excludeId
            }
            
            if !conflicting.isEmpty {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: field,
                    value: value,
                    message: "Duplicate value '\(value)' for unique field '\(field)'"
                )
            }
        }
        
        // Check compound unique constraints
        for compoundKey in uniqueCompoundFields {
            let fields = compoundKey.components(separatedBy: "+")
            guard fields.allSatisfy({ record.storage[$0] != nil }) else { continue }
            
            // Build compound key
            let values = fields.compactMap { record.storage[$0] }
            guard values.count == fields.count else { continue }
            
            // Check for duplicates using compound index query
            let queryBuilder = QueryBuilder(collection: collection)
            for (index, field) in fields.enumerated() {
                queryBuilder.where(field, equals: values[index])
            }
            let existing = try queryBuilder.execute()
            let records = try existing.records
            let conflicting = records.filter { record in
                guard let recordId = record.storage["id"]?.uuidValue else { return false }
                return recordId != excludeId
            }
            
            if !conflicting.isEmpty {
                throw BlazeDBError.uniqueConstraintViolation(
                    field: compoundKey,
                    value: nil,
                    message: "Duplicate values for unique compound fields '\(compoundKey)'"
                )
            }
        }
    }
}

// MARK: - BlazeDBClient Unique Constraints Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var uniqueConstraintManagerKey: UInt8 = 0
    
    private var uniqueConstraintManager: UniqueConstraintManager {
        #if canImport(ObjectiveC)
        if let manager = objc_getAssociatedObject(self, &Self.uniqueConstraintManagerKey) as? UniqueConstraintManager {
            return manager
        }
        let manager = UniqueConstraintManager()
        objc_setAssociatedObject(self, &Self.uniqueConstraintManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
        #else
        if let manager: UniqueConstraintManager = AssociatedObjects.get(self, key: &Self.uniqueConstraintManagerKey) {
            return manager
        }
        let manager = UniqueConstraintManager()
        AssociatedObjects.set(self, key: &Self.uniqueConstraintManagerKey, value: manager)
        return manager
        #endif
    }
    
    /// Create unique index (enforces uniqueness)
    public func createUniqueIndex(on field: String) throws {
        // Create index first
        try collection.createIndex(on: field)
        
        // Mark as unique
        uniqueConstraintManager.addUniqueField(field)
        
        BlazeLogger.info("Created unique index on field '\(field)'")
    }
    
    /// Create unique compound index
    public func createUniqueCompoundIndex(on fields: [String]) throws {
        // Create compound index first
        try collection.createIndex(on: fields)
        
        // Mark as unique
        uniqueConstraintManager.addUniqueCompoundFields(fields)
        
        BlazeLogger.info("Created unique compound index on fields '\(fields.joined(separator: ", "))'")
    }
    
    /// Validate unique constraints before insert/update
    internal func validateUniqueConstraints(in record: BlazeDataRecord, excludeId: UUID? = nil) throws {
        try uniqueConstraintManager.validateUnique(collection: collection, record: record, excludeId: excludeId)
    }
}

// MARK: - BlazeDBError Unique Constraint Extension

extension BlazeDBError {
    public static func uniqueConstraintViolation(field: String, value: BlazeDocumentField?, message: String) -> BlazeDBError {
        var msg = "Unique constraint violation on '\(field)'"
        if let value = value {
            msg += " with value '\(value)'"
        }
        msg += ": \(message)"
        return .transactionFailed(msg)
    }
}

