//
//  BlazeDBClient+EasyOpen.swift
//  BlazeDB
//
//  Easy entrypoint API with opinionated defaults
//  Zero configuration for basic use cases
//

import Foundation

extension BlazeDBClient {
    
    // MARK: - Primary API (Use This)

    /// Open a database by name.
    ///
    /// For most app code, prefer ``BlazeDB/open(name:password:)``.
    /// This method remains the underlying client-level opener.
    ///
    /// BlazeDB always encrypts data. You must provide a password.
    ///
    /// ```swift
    /// let db = try BlazeDBClient.open(named: "myapp", password: "my-secure-password-123")
    /// ```
    ///
    /// - Parameters:
    ///   - name: Database name (becomes the filename)
    ///   - password: Encryption password (`PasswordStrengthValidator.Requirements.recommended`; see `Docs/GettingStarted/PASSWORD_POLICY.md`)
    /// - Returns: Ready-to-use database client
    ///
    /// Database is stored in the platform default location:
    /// - macOS: `~/Library/Application Support/BlazeDB/`
    /// - iOS: app sandbox `Library/Application Support/BlazeDB/` (see ``PathResolver`` / `Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md`)
    /// - Linux: `~/.local/share/blazedb/`
    public static func open(
        named name: String,
        password: String
    ) throws -> BlazeDBClient {
        let baseDirectory = try PathResolver.defaultDatabaseDirectory()
        let dbURL = baseDirectory.appendingPathComponent("\(name).blazedb")
        try PathResolver.validateDatabasePath(dbURL)
        return try BlazeDBClient(name: name, fileURL: dbURL, password: password)
    }

    /// Open a database at a specific file URL.
    ///
    /// For most app code, prefer ``BlazeDB/open(at:password:)``.
    /// This method remains the underlying client-level opener.
    ///
    /// Opens or creates an encrypted database at the given location.
    ///
    /// ```swift
    /// let url = URL(fileURLWithPath: "/path/to/my.blazedb")
    /// let db = try BlazeDBClient.open(at: url, password: "my-secure-password-123")
    /// ```
    ///
    /// - Parameters:
    ///   - url: File URL for the database
    ///   - password: Encryption password (`PasswordStrengthValidator.Requirements.recommended`; see `Docs/GettingStarted/PASSWORD_POLICY.md`)
    /// - Returns: Ready-to-use database client
    public static func open(
        at url: URL,
        password: String
    ) throws -> BlazeDBClient {
        try PathResolver.validateDatabasePath(url)
        let name = url.deletingPathExtension().lastPathComponent
        return try BlazeDBClient(name: name, fileURL: url, password: password)
    }

    // MARK: - Legacy API (Still Supported)

    /// Open database with explicit password.
    ///
    /// Use `open(named:password:)` instead for new code.
    @available(*, deprecated, message: "Use open(named:password:). Behavior is identical.")
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
    @available(*, deprecated, message: "Use open(at:password:) for custom paths.")
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
    @available(*, deprecated, message: "Use open(named:password:) for production, openForTesting() for tests.")
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
    @available(*, deprecated, message: "Use open(named:password:) for production, openForTesting() for tests.")
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
    ///   - password: Encryption password (**same strength rules as production**; default satisfies `PasswordStrengthValidator.Requirements.recommended`)
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
        password: String = "TestPass-123!"
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
