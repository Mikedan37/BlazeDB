//
//  MigrationPlan.swift
//  BlazeDB
//
//  Migration planning and execution
//  Validates migrations before applying
//

import Foundation

/// Migration plan result
public struct MigrationPlan {
    /// Current database version
    public let currentVersion: SchemaVersion
    
    /// Target schema version
    public let targetVersion: SchemaVersion
    
    /// Ordered list of migrations to apply
    public let migrations: [BlazeDBMigration]
    
    /// Whether plan is valid
    public let isValid: Bool
    
    /// Validation errors (if any)
    public let errors: [String]
    
    /// Human-readable plan description
    public var description: String {
        var desc = "Migration Plan: \(currentVersion) → \(targetVersion)\n"
        desc += "Migrations to apply: \(migrations.count)\n"
        
        if migrations.isEmpty {
            desc += "No migrations needed.\n"
        } else {
            for (index, migration) in migrations.enumerated() {
                desc += "  \(index + 1). \(migration.from) → \(migration.to)\n"
            }
        }
        
        if !isValid {
            desc += "\nErrors:\n"
            for error in errors {
                desc += "  - \(error)\n"
            }
        }
        
        return desc
    }
}

/// Migration planner
///
/// Validates migration continuity and computes upgrade plans.
public struct MigrationPlanner {
    
    /// Plan migration from current version to target version
    ///
    /// - Parameters:
    ///   - currentVersion: Current database version
    ///   - targetVersion: Target schema version
    ///   - availableMigrations: All available migrations
    /// - Returns: Migration plan with validation results
    public static func plan(
        from currentVersion: SchemaVersion,
        to targetVersion: SchemaVersion,
        migrations: [BlazeDBMigration]
    ) -> MigrationPlan {
        var errors: [String] = []
        
        // If versions match, no migration needed
        if currentVersion == targetVersion {
            return MigrationPlan(
                currentVersion: currentVersion,
                targetVersion: targetVersion,
                migrations: [],
                isValid: true,
                errors: []
            )
        }
        
        // Validate direction
        if currentVersion > targetVersion {
            errors.append("Downgrade not supported: \(currentVersion) → \(targetVersion)")
            return MigrationPlan(
                currentVersion: currentVersion,
                targetVersion: targetVersion,
                migrations: [],
                isValid: false,
                errors: errors
            )
        }
        
        // Find migrations in range
        let relevantMigrations = migrations
            .filter { $0.from >= currentVersion && $0.to <= targetVersion }
            .sorted { $0.from < $1.from }
        
        // Validate continuity
        var expectedVersion = currentVersion
        var orderedMigrations: [BlazeDBMigration] = []
        
        for migration in relevantMigrations {
            // Check if migration starts from expected version
            if migration.from != expectedVersion {
                errors.append("Missing migration: gap between \(expectedVersion) and \(migration.from)")
                break
            }
            
            orderedMigrations.append(migration)
            expectedVersion = migration.to
            
            // Check if we've reached target
            if expectedVersion >= targetVersion {
                break
            }
        }
        
        // Check if we reached target
        if expectedVersion < targetVersion {
            errors.append("Missing migration: gap between \(expectedVersion) and \(targetVersion)")
        }
        
        return MigrationPlan(
            currentVersion: currentVersion,
            targetVersion: targetVersion,
            migrations: orderedMigrations,
            isValid: errors.isEmpty,
            errors: errors
        )
    }
}
