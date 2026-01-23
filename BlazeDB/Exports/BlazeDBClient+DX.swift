//
//  BlazeDBClient+DX.swift
//  BlazeDB
//
//  Developer Experience improvements: Happy path APIs
//  Convenience methods that reduce friction without changing core behavior
//

import Foundation

extension BlazeDBClient {
    
    // MARK: - Convenience Entry Points
    
    /// Open database or create if it doesn't exist
    ///
    /// Convenience method that handles the common case of "open if exists, create if not".
    /// Automatically creates directory if needed.
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Encryption password
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened or created
    ///
    /// ## Example
    /// ```swift
    /// // Opens existing DB or creates new one
    /// let db = try BlazeDB.openOrCreate(name: "mydb", password: "secure-password")
    /// ```
    public static func openOrCreate(
        name: String,
        password: String
    ) throws -> BlazeDBClient {
        // Try to open existing database
        do {
            return try openDefault(name: name, password: password)
        } catch {
            // If it doesn't exist, create it
            // openDefault already creates directories, so this should work
            return try openDefault(name: name, password: password)
        }
    }
    
    /// Open temporary database for testing or sandboxing
    ///
    /// Creates a database in a temporary directory that can be easily cleaned up.
    /// Perfect for tests, experiments, or temporary data.
    ///
    /// - Parameters:
    ///   - name: Optional database name (defaults to UUID)
    ///   - password: Encryption password (can be simple for tests)
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be created
    ///
    /// ## Example
    /// ```swift
    /// // Temporary database for testing
    /// let db = try BlazeDB.openTemporary(password: "test-password")
    /// defer { try? FileManager.default.removeItem(at: db.fileURL) }
    /// ```
    public static func openTemporary(
        name: String? = nil,
        password: String = "temp-password"
    ) throws -> BlazeDBClient {
        return try openForTesting(name: name, password: password)
    }
    
    /// Execute block with database, auto-closing if needed
    ///
    /// Convenience helper for scoped database usage.
    /// Database is automatically flushed on deinit, so this is mainly for clarity.
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Encryption password
    ///   - block: Block to execute with database
    /// - Returns: Result from block
    /// - Throws: Error from database operations or block
    ///
    /// ## Example
    /// ```swift
    /// try BlazeDB.withDatabase(name: "mydb", password: "pass") { db in
    ///     try db.insert(record)
    ///     return try db.query().execute().records
    /// }
    /// ```
    public static func withDatabase<T>(
        name: String,
        password: String,
        _ block: (BlazeDBClient) throws -> T
    ) throws -> T {
        let db = try openDefault(name: name, password: password)
        return try block(db)
    }
    
    // MARK: - Batch Operations
    
    // Note: insertMany() already exists in BlazeDBClient.swift
    // This file provides other DX convenience methods
}
