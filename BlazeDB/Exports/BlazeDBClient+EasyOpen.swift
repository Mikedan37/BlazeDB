//
//  BlazeDBClient+EasyOpen.swift
//  BlazeDB
//
//  Easy entrypoint API with opinionated defaults
//  Zero configuration for basic use cases
//

import Foundation

extension BlazeDBClient {
    
    /// Open database with default settings (zero configuration)
    ///
    /// This is the simplest way to use BlazeDB. It provides:
    /// - Safe default data directory (platform-specific)
    /// - Encryption enabled by default
    /// - Automatic directory creation
    /// - Zero configuration required
    ///
    /// - Parameters:
    ///   - name: Database name (used as filename)
    ///   - password: Encryption password (required for security)
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// // Simplest possible usage
    /// let db = try BlazeDB.openDefault(name: "mydb", password: "secure-password")
    /// try db.insert(BlazeDataRecord(["name": .string("Alice")]))
    /// ```
    ///
    /// ## Platform Defaults
    /// - **macOS:** ~/Library/Application Support/BlazeDB/{name}.blazedb
    /// - **Linux:** ~/.local/share/blazedb/{name}.blazedb
    public static func openDefault(
        name: String,
        password: String
    ) throws -> BlazeDBClient {
        // Get default directory
        let baseDirectory = try PathResolver.defaultDatabaseDirectory()
        
        // Construct database path
        let dbURL = baseDirectory.appendingPathComponent("\(name).blazedb")
        
        // Validate path
        try PathResolver.validateDatabasePath(dbURL)
        
        // Open with defaults
        return try BlazeDBClient(name: name, fileURL: dbURL, password: password)
    }
    
    /// Open database with custom path (advanced)
    ///
    /// Use this when you need to specify a custom location.
    /// Still provides safe defaults for other settings.
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - path: Custom database path (relative or absolute)
    ///   - password: Encryption password
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// // Custom path
    /// let db = try BlazeDB.open(name: "mydb", path: "./data/mydb.blazedb", password: "secure-password")
    /// ```
    public static func open(
        name: String,
        path: String,
        password: String
    ) throws -> BlazeDBClient {
        // Resolve path
        let dbURL = try PathResolver.resolveDatabasePath(path)
        
        // Validate path
        try PathResolver.validateDatabasePath(dbURL)
        
        // Open
        return try BlazeDBClient(name: name, fileURL: dbURL, password: password)
    }
}
