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
    
}
