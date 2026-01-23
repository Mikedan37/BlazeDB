//
//  BlazeDBClient+Guardrails.swift
//  BlazeDB
//
//  Explicit guardrails to prevent common mistakes
//  Fails loudly with actionable error messages
//

import Foundation

extension BlazeDBClient {
    
    /// Open database with schema version validation
    ///
    /// Validates that database schema matches expected version.
    /// Fails loudly if schema is newer (app outdated) or older (migrations needed).
    ///
    /// **Use this when:** Your application declares a schema version and you want
    /// to ensure database compatibility at open time.
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Encryption password
    ///   - expectedVersion: Expected schema version
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if schema version mismatch or database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// struct MyAppSchema: BlazeSchema {
    ///     static var version = SchemaVersion(major: 1, minor: 0)
    /// }
    ///
    /// let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")
    /// try db.validateSchemaVersion(expectedVersion: MyAppSchema.version)
    /// ```
    public static func openWithSchemaValidation(
        name: String,
        password: String,
        expectedVersion: SchemaVersion
    ) throws -> BlazeDBClient {
        let db = try openDefault(name: name, password: password)
        try db.validateSchemaVersion(expectedVersion: expectedVersion)
        return db
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
                "Database schema version (\(dbVersion)) is older than expected (\(expectedVersion)). Migrations required. Use db.planMigration() to see what migrations are needed.",
                underlyingError: nil
            )
        } else if dbVersion > expectedVersion {
            // Database is newer - version mismatch
            throw BlazeDBError.migrationFailed(
                "Database schema version (\(dbVersion)) is newer than expected (\(expectedVersion)). Application may be outdated. Update your application or downgrade the database.",
                underlyingError: nil
            )
        }
        
        // Versions match - OK
    }
}
