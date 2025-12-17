//
//  BlazeDBClient+Convenience.swift
//  BlazeDB
//
//  Convenience initializers for easier database creation
//  Uses Application Support by default, just provide a name!
//
//  Created: 2025-01-XX
//

import Foundation

extension BlazeDBClient {
    
    // MARK: - Convenience Initializers
    
    /// Create or open a database by name (uses Application Support by default)
    ///
    /// This is the easiest way to create a database - just provide a name!
    /// The database will be stored in `~/Library/Application Support/BlazeDB/`
    ///
    /// - Parameters:
    ///   - name: Database name (e.g., "MyApp", "UserData", "Cache")
    ///   - password: Password for encryption (must be 8+ characters)
    ///   - project: Optional project namespace (defaults to "Default")
    /// - Returns: A BlazeDBClient instance
    /// - Throws: BlazeDBError if initialization fails
    ///
    /// ## Example
    /// ```swift
    /// // Super simple - just a name!
    /// let db = try BlazeDBClient(name: "MyApp", password: "secure-password-123")
    ///
    /// // Database is automatically stored in:
    /// // ~/Library/Application Support/BlazeDB/MyApp.blazedb
    /// ```
    public convenience init(name: String, password: String, project: String = "Default") throws {
        let url = try Self.defaultDatabaseURL(for: name)
        try self.init(name: name, fileURL: url, password: password, project: project)
    }
    
    /// Create or open a database by name (failable, no try-catch needed)
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - password: Password for encryption
    ///   - project: Optional project namespace
    /// - Returns: A BlazeDBClient instance, or `nil` if initialization failed
    ///
    /// ## Example
    /// ```swift
    /// guard let db = BlazeDBClient(name: "MyApp", password: "secure-password-123") else {
    ///     print("Failed to initialize database")
    ///     return
    /// }
    /// ```
    public static func create(name: String, password: String, project: String = "Default") -> BlazeDBClient? {
        do {
            let url = try defaultDatabaseURL(for: name)
            return try BlazeDBClient(name: name, fileURL: url, password: password, project: project)
        } catch {
            BlazeLogger.error("❌ Failed to create BlazeDB '\(name)': \(error)")
            return nil
        }
    }
    
    // MARK: - Default Database Location
    
    /// Get the default database URL for a given name
    ///
    /// Databases are stored in: `~/Library/Application Support/BlazeDB/`
    ///
    /// - Parameter name: Database name
    /// - Returns: URL to the database file
    /// - Throws: BlazeDBError if Application Support directory cannot be accessed
    public static func defaultDatabaseURL(for name: String) throws -> URL {
        let fileManager = FileManager.default
        
        // Get Application Support directory
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BlazeDBError.permissionDenied(
                operation: "access Application Support",
                path: nil
            )
        }
        
        // Create BlazeDB subdirectory
        let blazeDBDir = appSupport.appendingPathComponent("BlazeDB", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: blazeDBDir.path) {
            try fileManager.createDirectory(
                at: blazeDBDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]  // Secure permissions
            )
            BlazeLogger.info("Created BlazeDB directory: \(blazeDBDir.path)")
        }
        
        // Return database file URL
        let dbName = name.hasSuffix(".blazedb") ? name : "\(name).blazedb"
        return blazeDBDir.appendingPathComponent(dbName)
    }
    
    /// Get the default database directory
    ///
    /// Returns: `~/Library/Application Support/BlazeDB/`
    public static var defaultDatabaseDirectory: URL {
        get throws {
            let fileManager = FileManager.default
            guard let appSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw BlazeDBError.permissionDenied(
                    operation: "access Application Support",
                    path: nil
                )
            }
            
            let blazeDBDir = appSupport.appendingPathComponent("BlazeDB", isDirectory: true)
            
            // Create if needed
            if !fileManager.fileExists(atPath: blazeDBDir.path) {
                try fileManager.createDirectory(
                    at: blazeDBDir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            
            return blazeDBDir
        }
    }
    
    // MARK: - Database Discovery
    
    /// Discover all databases in the default location
    ///
    /// Scans `~/Library/Application Support/BlazeDB/` for all `.blazedb` files
    ///
    /// - Returns: Array of discovered database information
    /// - Throws: BlazeDBError if discovery fails
    ///
    /// ## Example
    /// ```swift
    /// let databases = try BlazeDBClient.discoverDatabases()
    /// for db in databases {
    ///     print("Found: \(db.name) at \(db.path)")
    /// }
    /// ```
    public static func discoverDatabases() throws -> [DatabaseDiscoveryInfo] {
        let directory = try defaultDatabaseDirectory
        return try discoverDatabases(in: directory)
    }
    
    /// Discover databases by name in the default location
    ///
    /// - Parameter name: Database name (with or without .blazedb extension)
    /// - Returns: Database information if found, `nil` otherwise
    ///
    /// ## Example
    /// ```swift
    /// if let db = try BlazeDBClient.findDatabase(named: "MyApp") {
    ///     print("Found: \(db.name) at \(db.path)")
    /// }
    /// ```
    public static func findDatabase(named name: String) throws -> DatabaseDiscoveryInfo? {
        let databases = try discoverDatabases()
        let searchName = name.hasSuffix(".blazedb") ? name : "\(name).blazedb"
        return databases.first { $0.path.hasSuffix(searchName) }
    }
    
    /// Check if a database exists by name
    ///
    /// - Parameter name: Database name
    /// - Returns: `true` if database exists, `false` otherwise
    ///
    /// ## Example
    /// ```swift
    /// if BlazeDBClient.databaseExists(named: "MyApp") {
    ///     print("Database exists!")
    /// }
    /// ```
    public static func databaseExists(named name: String) -> Bool {
        do {
            let url = try defaultDatabaseURL(for: name)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }
    
    // MARK: - Database Registry
    
    /// Register a database in the global registry (for easy lookup)
    ///
    /// This allows you to find databases by name across your app
    ///
    /// - Parameters:
    ///   - name: Database name
    ///   - client: The BlazeDBClient instance
    public static func registerDatabase(name: String, client: BlazeDBClient) {
        DatabaseRegistry.shared.register(name: name, client: client)
    }
    
    /// Get a registered database by name
    ///
    /// - Parameter name: Database name
    /// - Returns: BlazeDBClient if registered, `nil` otherwise
    public static func getRegisteredDatabase(named name: String) -> BlazeDBClient? {
        return DatabaseRegistry.shared.get(named: name)
    }
    
    /// Unregister a database from the global registry
    ///
    /// - Parameter name: Database name
    public static func unregisterDatabase(named name: String) {
        DatabaseRegistry.shared.unregister(named: name)
    }
    
    /// List all registered databases
    ///
    /// - Returns: Array of registered database names
    public static func registeredDatabases() -> [String] {
        return DatabaseRegistry.shared.allNames
    }
}

// MARK: - Database Registry

/// Global registry for tracking databases by name
public final class DatabaseRegistry: @unchecked Sendable {
    nonisolated(unsafe) public static let shared = DatabaseRegistry()
    
    private var databases: [String: BlazeDBClient] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Register a database
    func register(name: String, client: BlazeDBClient) {
        lock.lock()
        defer { lock.unlock() }
        databases[name] = client
        BlazeLogger.info("Registered database: \(name)")
    }
    
    /// Get a registered database
    func get(named name: String) -> BlazeDBClient? {
        lock.lock()
        defer { lock.unlock() }
        return databases[name]
    }
    
    /// Unregister a database
    func unregister(named name: String) {
        lock.lock()
        defer { lock.unlock() }
        databases.removeValue(forKey: name)
        BlazeLogger.info("Unregistered database: \(name)")
    }
    
    /// Get all registered database names
    var allNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(databases.keys)
    }
    
    /// Get all registered databases
    var all: [BlazeDBClient] {
        lock.lock()
        defer { lock.unlock() }
        return Array(databases.values)
    }
}

