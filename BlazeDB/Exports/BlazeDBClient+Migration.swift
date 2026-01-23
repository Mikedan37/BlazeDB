//
//  BlazeDBClient+Migration.swift
//  BlazeDB
//
//  Migration APIs for BlazeDBClient
//  Uses public APIs only - no storage internals
//

import Foundation

extension BlazeDBClient {
    
    /// Get current database schema version
    ///
    /// Returns version from metadata, or nil if not set (legacy database).
    /// - Returns: Current schema version, or nil if not versioned
    /// - Throws: Error if metadata cannot be read
    public func getSchemaVersion() throws -> SchemaVersion? {
        let meta = try collection.fetchMeta()
        
        guard let majorValue = meta["schema_version_major"],
              let minorValue = meta["schema_version_minor"],
              case .int(let major) = majorValue,
              case .int(let minor) = minorValue else {
            return nil  // Legacy database without version
        }
        
        return SchemaVersion(major: major, minor: minor)
    }
    
    /// Set database schema version
    ///
    /// Used internally by migration executor.
    /// - Parameter version: Schema version to set
    /// - Throws: Error if metadata cannot be updated
    internal func setSchemaVersion(_ version: SchemaVersion) throws {
        var meta = try collection.fetchMeta()
        meta["schema_version_major"] = .int(version.major)
        meta["schema_version_minor"] = .int(version.minor)
        try collection.updateMeta(meta)
    }
    
    /// Plan migration to target schema version
    ///
    /// - Parameters:
    ///   - targetVersion: Target schema version
    ///   - migrations: Available migrations
    /// - Returns: Migration plan
    /// - Throws: Error if current version cannot be determined
    public func planMigration(
        to targetVersion: SchemaVersion,
        migrations: [BlazeDBMigration]
    ) throws -> MigrationPlan {
        let currentVersion = try getSchemaVersion() ?? SchemaVersion(major: 0, minor: 0)
        
        return MigrationPlanner.plan(
            from: currentVersion,
            to: targetVersion,
            migrations: migrations
        )
    }
    
    /// Execute migration plan
    ///
    /// - Parameters:
    ///   - plan: Migration plan (must be valid)
    ///   - dryRun: If true, validate but don't apply
    /// - Returns: Migration result
    /// - Throws: Error if plan is invalid or execution fails
    public func executeMigration(
        plan: MigrationPlan,
        dryRun: Bool = false
    ) throws -> MigrationResult {
        return try MigrationExecutor.execute(
            plan: plan,
            db: self,
            dryRun: dryRun
        )
    }
    
    /// Validate schema version matches expected version
    ///
    /// **Guardrail:** Prevents opening database with incompatible schema.
    /// Fails loudly if versions don't match.
    ///
    /// - Parameter expectedVersion: Expected schema version
    /// - Throws: Error if schema version mismatch
    ///
    /// ## Error Messages
    /// - Older database: "Database schema version (X.Y) is older than expected (A.B). Migrations required."
    /// - Newer database: "Database schema version (X.Y) is newer than expected (A.B). Application may be outdated."
    public func validateSchemaVersion(expectedVersion: SchemaVersion) throws {
        let currentVersion = try getSchemaVersion()
        
        // If no version set, assume legacy (version 0.0)
        let dbVersion = currentVersion ?? SchemaVersion(major: 0, minor: 0)
        
        if dbVersion < expectedVersion {
            // Database is older - migrations required
            throw BlazeDBError.migrationFailed(
                "Database schema version (\(dbVersion)) is older than expected (\(expectedVersion)). Migrations required.",
                underlyingError: nil
            )
        } else if dbVersion > expectedVersion {
            // Database is newer - version mismatch
            throw BlazeDBError.migrationFailed(
                "Database schema version (\(dbVersion)) is newer than expected (\(expectedVersion)). Application may be outdated.",
                underlyingError: nil
            )
        }
        
        // Versions match - OK
    }
}
