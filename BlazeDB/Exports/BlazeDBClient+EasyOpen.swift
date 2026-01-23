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
    
    // MARK: - Preset Configurations
    
    /// Open database optimized for CLI tools
    ///
    /// Safe defaults for command-line applications:
    /// - Uses default data directory
    /// - Encryption enabled
    /// - Suitable for single-user CLI tools
    ///
    /// **When to use:** CLI tools, scripts, one-off utilities
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Encryption password
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// // CLI tool
    /// let db = try BlazeDB.openForCLI(name: "mytool", password: "secure-password")
    /// ```
    public static func openForCLI(
        name: String,
        password: String
    ) throws -> BlazeDBClient {
        // CLI tools use default directory with standard settings
        return try openDefault(name: name, password: password)
    }
    
    /// Open database optimized for daemon/server processes
    ///
    /// Safe defaults for long-running server processes:
    /// - Uses default data directory
    /// - Encryption enabled
    /// - Suitable for embedded database in server applications
    ///
    /// **When to use:** Vapor servers, daemons, background services
    ///
    /// **Important:** BlazeDB is single-process only. Do not share database files
    /// between multiple processes. Each server instance should have its own database.
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Encryption password
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// // Server application
    /// let db = try BlazeDB.openForDaemon(name: "myserver", password: "secure-password")
    /// ```
    public static func openForDaemon(
        name: String,
        password: String
    ) throws -> BlazeDBClient {
        // Daemons use default directory with standard settings
        // No special configuration needed - defaults are server-safe
        return try openDefault(name: name, password: password)
    }
    
    /// Open database optimized for testing
    ///
    /// Safe defaults for test environments:
    /// - Uses temporary directory (cleaned up after tests)
    /// - Encryption enabled (for realistic testing)
    /// - Suitable for unit and integration tests
    ///
    /// **When to use:** XCTest, integration tests, test fixtures
    ///
    /// **Note:** Database files are created in a temporary directory.
    /// Clean up after tests using `FileManager.default.removeItem(at:)` if needed.
    ///
    /// - Parameters:
    ///   - name: Database name (optional, defaults to UUID)
    ///   - password: Encryption password (can be simple for tests)
    /// - Returns: Configured BlazeDB client
    /// - Throws: Error if database cannot be opened
    ///
    /// ## Example
    /// ```swift
    /// // Test
    /// let db = try BlazeDB.openForTesting(name: "testdb", password: "test-password")
    /// defer { try? FileManager.default.removeItem(at: db.fileURL) }
    /// ```
    public static func openForTesting(
        name: String? = nil,
        password: String = "test-password"
    ) throws -> BlazeDBClient {
        // Use temporary directory for tests
        let tempDir = FileManager.default.temporaryDirectory
        let dbName = name ?? UUID().uuidString
        let dbURL = tempDir.appendingPathComponent("\(dbName).blazedb")
        
        // Validate path
        try PathResolver.validateDatabasePath(dbURL)
        
        // Open with test settings
        return try BlazeDBClient(name: dbName, fileURL: dbURL, password: password)
    }
}
