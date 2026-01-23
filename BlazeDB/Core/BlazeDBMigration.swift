//
//  BlazeDBMigration.swift
//  BlazeDB
//
//  Explicit migration protocol for schema evolution
//  Uses public APIs only - no storage internals
//

import Foundation

/// Migration protocol for schema evolution
///
/// Migrations must be explicit, ordered, and reversible where possible.
/// Each migration declares its from/to versions explicitly.
///
/// ## Example
/// ```swift
/// struct AddEmailField: BlazeDBMigration {
///     var from: SchemaVersion { SchemaVersion(major: 1, minor: 0) }
///     var to: SchemaVersion { SchemaVersion(major: 1, minor: 1) }
///
///     func up(db: BlazeDBClient) throws {
///         // Add email field to all records
///         let records = try db.fetchAll()
///         for record in records {
///             if let id = record.id {
///                 var updated = record.storage
///                 updated["email"] = .string("")
///                 try db.update(id: id, with: BlazeDataRecord(updated))
///             }
///         }
///     }
///
///     func down(db: BlazeDBClient) throws {
///         // Remove email field
///         let records = try db.fetchAll()
///         for record in records {
///             if let id = record.id {
///                 var updated = record.storage
///                 updated.removeValue(forKey: "email")
///                 try db.update(id: id, with: BlazeDataRecord(updated))
///             }
///         }
///     }
/// }
/// ```
public protocol BlazeDBMigration {
    /// Source version (before migration)
    var from: SchemaVersion { get }
    
    /// Target version (after migration)
    var to: SchemaVersion { get }
    
    /// Apply migration (upgrade)
    /// - Parameter db: Database client (use public APIs only)
    /// - Throws: Error if migration fails
    func up(db: BlazeDBClient) throws
    
    /// Reverse migration (downgrade)
    /// - Parameter db: Database client (use public APIs only)
    /// - Throws: Error if reverse migration fails
    /// - Note: Optional - not all migrations are reversible
    func down(db: BlazeDBClient) throws
}

// MARK: - Default Implementation

extension BlazeDBMigration {
    /// Default implementation: down() throws by default
    /// Override if migration is reversible
    public func down(db: BlazeDBClient) throws {
        throw BlazeDBError.migrationFailed(
            "Migration from \(from) to \(to) is not reversible",
            underlyingError: nil
        )
    }
}
