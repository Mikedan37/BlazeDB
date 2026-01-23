//
//  MigrationPlan+PrettyPrint.swift
//  BlazeDB
//
//  Human-readable migration plan output
//  Makes dry-run output deterministic and understandable
//

import Foundation

extension MigrationPlan {
    
    /// Human-readable description of migration plan
    ///
    /// Provides formatted output showing:
    /// - Current and target schema versions
    /// - Ordered list of migrations
    /// - Destructive operations flag
    /// - Estimated time (if available)
    ///
    /// - Returns: Formatted string describing the migration plan
    public func prettyDescription() -> String {
        var output = "Migration Plan\n"
        output += "═══════════════\n\n"
        
        // Versions
        output += "Current Version: \(currentVersion)\n"
        output += "Target Version:  \(targetVersion)\n\n"
        
        // Migrations
        if migrations.isEmpty {
            output += "No migrations required.\n"
            output += "Database is already at target version.\n"
        } else {
            output += "Migrations to Apply (\(migrations.count)):\n"
            output += "─────────────────────────────────────\n"
            
            for (index, migration) in migrations.enumerated() {
                let step = index + 1
                let migrationName = String(describing: type(of: migration))
                output += "\n\(step). \(migrationName)\n"
                
                // Check if migration is destructive
                if let destructive = migration.isDestructive, destructive {
                    output += "   ⚠️  DESTRUCTIVE OPERATION\n"
                }
                
                // Summary if available
                if let summary = migration.summary, !summary.isEmpty {
                    output += "   📝 \(summary)\n"
                }
                
                // Version info
                output += "   Version: \(migration.from) → \(migration.to)\n"
            }
            
            output += "\n"
        }
        
        // Destructive operations summary
        let hasDestructive = migrations.contains { $0.isDestructive == true }
        if hasDestructive {
            output += "⚠️  WARNING: This plan includes destructive operations.\n"
            output += "   Data may be lost or modified. Review migrations carefully.\n"
        } else {
            output += "✅ No destructive operations detected.\n"
        }
        
        // Estimated time (not available in MigrationPlan, show as unknown)
        output += "\nEstimated Time: Unknown\n"
        
        return output
    }
    
    /// Format time duration for display
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        } else {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

extension BlazeDBMigration {
    
    /// Whether this migration performs destructive operations
    ///
    /// Defaults to `nil` (unknown). Override in migration implementations to mark destructive operations.
    /// 
    /// ## Example
    /// ```swift
    /// struct DropOldFields: BlazeDBMigration {
    ///     var isDestructive: Bool? { return true }
    ///     var summary: String? { return "Removes deprecated fields" }
    ///     // ... migration implementation
    /// }
    /// ```
    public var isDestructive: Bool? {
        return nil  // Default: unknown (conservative)
    }
    
    /// Human-readable summary of what this migration does
    ///
    /// Defaults to `nil` (no summary). Override in migration implementations to provide context.
    ///
    /// ## Example
    /// ```swift
    /// struct AddEmailField: BlazeDBMigration {
    ///     var summary: String? { return "Adds email field to all user records" }
    ///     // ... migration implementation
    /// }
    /// ```
    public var summary: String? {
        return nil  // Default: no summary
    }
    
    /// Migration name for display (defaults to type name)
    public var name: String {
        return String(describing: type(of: self))
    }
}
