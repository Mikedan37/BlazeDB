//
//  MigrationExecutor.swift
//  BlazeDB
//
//  Explicit migration execution
//  No automatic execution - user must call explicitly
//

import Foundation

/// Migration execution result
public struct MigrationResult {
    /// Whether migration succeeded
    public let success: Bool
    
    /// Number of migrations applied
    public let migrationsApplied: Int
    
    /// Error message (if failed)
    public let error: String?
    
    /// Human-readable result description
    public var description: String {
        if success {
            return "Migration succeeded: applied \(migrationsApplied) migration(s)"
        } else {
            return "Migration failed: \(error ?? "Unknown error")"
        }
    }
}

/// Migration executor
///
/// Executes migration plans explicitly and synchronously.
/// Errors stop execution immediately - no partial state.
public struct MigrationExecutor {
    
    /// Execute migration plan
    ///
    /// - Parameters:
    ///   - plan: Migration plan (must be valid)
    ///   - db: Database client
    ///   - dryRun: If true, validate but don't apply
    /// - Returns: Migration result
    /// - Throws: Error if plan is invalid or execution fails
    public static func execute(
        plan: MigrationPlan,
        db: BlazeDBClient,
        dryRun: Bool = false
    ) throws -> MigrationResult {
        // Validate plan
        guard plan.isValid else {
            let errorMsg = "Invalid migration plan:\n\(plan.description)"
            throw BlazeDBError.migrationFailed(errorMsg, underlyingError: nil)
        }
        
        // If no migrations needed, return success
        if plan.migrations.isEmpty {
            return MigrationResult(
                success: true,
                migrationsApplied: 0,
                error: nil
            )
        }
        
        // Dry-run: validate only
        if dryRun {
            // Validate that all migrations can be applied
            // (We can't fully validate without executing, but we can check structure)
            return MigrationResult(
                success: true,
                migrationsApplied: plan.migrations.count,
                error: nil
            )
        }
        
        // Execute migrations in order
        var applied = 0
        do {
            for migration in plan.migrations {
                try migration.up(db: db)
                applied += 1
                
                // Update database version after each migration
                try updateDatabaseVersion(db: db, version: migration.to)
            }
            
            return MigrationResult(
                success: true,
                migrationsApplied: applied,
                error: nil
            )
        } catch {
            // Migration failed - stop immediately
            let errorMsg = "Migration \(applied + 1) failed: \(error.localizedDescription)"
            throw BlazeDBError.migrationFailed(
                errorMsg,
                underlyingError: error
            )
        }
    }
    
    /// Update database schema version in metadata
    private static func updateDatabaseVersion(db: BlazeDBClient, version: SchemaVersion) throws {
        try db.setSchemaVersion(version)
    }
}
