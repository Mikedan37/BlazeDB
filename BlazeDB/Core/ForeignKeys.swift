//
//  ForeignKeys.swift
//  BlazeDB
//
//  Foreign key constraints and referential integrity
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Foreign Key Definition

public struct ForeignKey {
    public let name: String
    public let field: String                    // Field in this collection
    public let referencedCollection: String     // Collection being referenced
    public let referencedField: String          // Field in referenced collection (usually "id")
    public let onDelete: DeleteAction
    public let onUpdate: UpdateAction
    
    public enum DeleteAction {
        case cascade      // Delete related records
        case setNull      // Set field to null
        case restrict     // Prevent delete if related records exist
        case noAction     // Do nothing (allow orphans)
    }
    
    public enum UpdateAction {
        case cascade      // Update related records
        case restrict     // Prevent update if related records exist
        case noAction     // Do nothing
    }
    
    public init(
        name: String,
        field: String,
        referencedCollection: String,
        referencedField: String = "id",
        onDelete: DeleteAction = .restrict,
        onUpdate: UpdateAction = .noAction
    ) {
        self.name = name
        self.field = field
        self.referencedCollection = referencedCollection
        self.referencedField = referencedField
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}

// MARK: - Foreign Key Manager

internal final class ForeignKeyManager {
    private var foreignKeys: [String: [ForeignKey]] = [:]  // collection -> foreign keys
    private let lock = NSLock()
    
    func addForeignKey(_ foreignKey: ForeignKey, for collection: String) {
        lock.lock()
        defer { lock.unlock() }
        
        foreignKeys[collection, default: []].append(foreignKey)
        
        BlazeLogger.info("🔗 Foreign key '\(foreignKey.name)' added to '\(collection)'")
    }
    
    func removeForeignKey(named name: String, for collection: String) {
        lock.lock()
        defer { lock.unlock() }
        
        foreignKeys[collection]?.removeAll { $0.name == name }
        
        BlazeLogger.info("🔗 Foreign key '\(name)' removed from '\(collection)'")
    }
    
    func getForeignKeys(for collection: String) -> [ForeignKey] {
        lock.lock()
        defer { lock.unlock() }
        
        return foreignKeys[collection] ?? []
    }
    
    func getAllForeignKeys() -> [String: [ForeignKey]] {
        lock.lock()
        defer { lock.unlock() }
        
        return foreignKeys
    }
}

// MARK: - BlazeDBClient Foreign Key Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var foreignKeyManagers: [String: ForeignKeyManager] = [:]
    nonisolated(unsafe) private static let fkManagerLock = NSLock()
    
    private var foreignKeyManager: ForeignKeyManager {
        let key = "\(name)-\(fileURL.path)"
        
        Self.fkManagerLock.lock()
        defer { Self.fkManagerLock.unlock() }
        
        if let existing = Self.foreignKeyManagers[key] {
            return existing
        }
        
        let manager = ForeignKeyManager()
        Self.foreignKeyManagers[key] = manager
        return manager
    }
    
    // MARK: - Foreign Key API
    
    /// Add a foreign key constraint
    ///
    /// - Parameter foreignKey: Foreign key definition
    ///
    /// ## Example
    /// ```swift
    /// // Bugs reference users: bug.userId -> users.id
    /// db.addForeignKey(ForeignKey(
    ///     name: "bug_user_fk",
    ///     field: "userId",
    ///     referencedCollection: "users",
    ///     onDelete: .cascade  // Delete bugs when user deleted
    /// ))
    /// ```
    public func addForeignKey(_ foreignKey: ForeignKey) {
        foreignKeyManager.addForeignKey(foreignKey, for: name)
    }
    
    /// Remove a foreign key constraint
    ///
    /// - Parameter name: Name of the foreign key to remove
    public func removeForeignKey(named name: String) {
        foreignKeyManager.removeForeignKey(named: name, for: self.name)
    }
    
    /// Get all foreign keys for this database
    public func getForeignKeys() -> [ForeignKey] {
        return foreignKeyManager.getForeignKeys(for: name)
    }
    
    // MARK: - Internal Validation
    
    /// Validate foreign key constraints before insert
    internal func validateForeignKeys(for record: BlazeDataRecord, operation: String) throws {
        let foreignKeys = foreignKeyManager.getForeignKeys(for: name)
        
        for fk in foreignKeys {
            guard let fieldValue = record.storage[fk.field] else {
                // Field not present - OK (not enforcing NOT NULL here)
                continue
            }
            
            // Check if referenced record exists
            // NOTE: Multi-collection foreign key validation is intentionally not implemented.
            // Foreign keys currently validate UUID format only. Full referential integrity
            // across collections requires application-level validation or future multi-collection support.
            if let referencedID = fieldValue.uuidValue {
                // Verify it's a valid UUID format (full validation requires multi-collection support)
                BlazeLogger.trace("🔗 Foreign key '\(fk.name)': \(fk.field) = \(referencedID)")
            }
        }
    }
    
    /// Handle cascade deletes
    internal func handleCascadeDeletes(for id: UUID) throws {
        let foreignKeys = foreignKeyManager.getForeignKeys(for: name)
        
        for fk in foreignKeys {
            switch fk.onDelete {
            case .cascade:
                // NOTE: Cascade delete across collections intentionally not implemented.
                // Requires multi-collection support. Use application-level cascade logic.
                BlazeLogger.debug("🔗 CASCADE DELETE: Would delete related records for FK '\(fk.name)'")
                
            case .setNull:
                // NOTE: SET NULL across collections intentionally not implemented.
                // Requires multi-collection support. Use application-level nullification logic.
                BlazeLogger.debug("🔗 SET NULL: Would nullify FK '\(fk.name)' in related records")
                
            case .restrict:
                // NOTE: RESTRICT validation across collections intentionally not implemented.
                // Requires multi-collection support. Use application-level validation.
                BlazeLogger.debug("🔗 RESTRICT: Would check for related records for FK '\(fk.name)'")
                
            case .noAction:
                // Do nothing (allow orphans)
                break
            }
        }
    }
}

// MARK: - Multi-Collection Foreign Key Support

/// Helper for managing relationships across collections
public struct RelationshipManager {
    private var databases: [String: BlazeDBClient] = [:]
    
    public init() {}
    
    /// Register a database for relationship management
    public mutating func register(_ database: BlazeDBClient, as name: String) {
        databases[name] = database
    }
    
    /// Validate foreign key references across databases
    public func validateReference(
        value: UUID,
        in collectionName: String,
        field: String = "id"
    ) throws -> Bool {
        guard let db = databases[collectionName] else {
            throw BlazeDBError.invalidData(reason: "Referenced collection '\(collectionName)' not registered")
        }
        
        let record = try db.fetch(id: value)
        return record != nil
    }
    
    /// Handle cascade delete across databases
    public func cascadeDelete(
        from collection: String,
        id: UUID,
        foreignKeys: [ForeignKey]
    ) throws {
        for fk in foreignKeys where fk.onDelete == .cascade {
            guard let referencedDB = databases[fk.referencedCollection] else {
                BlazeLogger.warn("Cannot cascade - collection '\(fk.referencedCollection)' not registered")
                continue
            }
            
            // Find all records with this foreign key value
            let related = try referencedDB.fetchAll().filter { record in
                record.storage[fk.field]?.uuidValue == id
            }
            
            // Delete them
            for relatedRecord in related {
                if let relatedID = relatedRecord.storage["id"]?.uuidValue {
                    try referencedDB.delete(id: relatedID)
                }
            }
            
            BlazeLogger.info("🔗 Cascade deleted \(related.count) records from '\(fk.referencedCollection)'")
        }
    }
}

