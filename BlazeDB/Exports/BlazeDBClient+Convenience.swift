//
//  BlazeDBClient+Convenience.swift
//  BlazeDB
//
//  Convenience initializers for easier database creation
//  Uses Application Support by default, just provide a name!
//
//

import Foundation

extension BlazeDBClient {
    private static let canonicalDatabaseExtension = "blazedb"
    private struct DefaultDatabaseLocationCandidate {
        let url: URL
        let label: String
    }
    
    public enum DatabaseNameConventionError: LocalizedError {
        case emptyName
        case unsupportedExtension(found: String, expected: String)
        
        public var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Database name is empty."
            case .unsupportedExtension(let found, let expected):
                return "Unsupported database extension '.\(found)'. Expected '.\(expected)'."
            }
        }
    }
    
    // MARK: - Convenience Initializers
    
    /// Create or open a database by name (uses Application Support by default).
    ///
    /// Deprecated convenience initializer.
    /// For most app code, prefer ``BlazeDB/open(name:password:)``.
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
    /// // Database is automatically stored under the platform default directory, e.g.:
    /// // macOS: ~/Library/Application Support/BlazeDB/MyApp.blazedb
    /// // iOS: <Sandbox>/Library/Application Support/BlazeDB/MyApp.blazedb
    /// ```
    @available(*, deprecated, message: "Use BlazeDBClient.open(named:password:) or open(at:password:) instead.")
    public convenience init(name: String, password: String, project: String = "Default") throws {
        let url = try Self.defaultDatabaseURL(for: name)
        try self.init(name: name, fileURL: url, password: password, project: project)
    }
    
    /// Create or open a database by name (failable, no try-catch needed).
    ///
    /// Deprecated convenience helper.
    /// For most app code, prefer ``BlazeDB/open(name:password:)`` and explicit error handling.
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
    @available(*, deprecated, message: "Use BlazeDBClient.open(named:password:) instead. Returns non-optional and throws on failure.")
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
    
    /// Get the default database URL for a given name.
    ///
    /// Databases are stored under the same platform default directory used by
    /// ``BlazeDBClient/open(named:password:)`` and ``PathResolver``.
    ///
    /// - Parameter name: Database name
    /// - Returns: URL to the database file
    /// - Throws: BlazeDBError if the default directory cannot be accessed
    public static func defaultDatabaseURL(for name: String) throws -> URL {
        let blazeDBDir = try PathResolver.defaultDatabaseDirectory()
        let dbName = try normalizedDatabaseFileName(fromUserInput: name)
        let canonicalURL = blazeDBDir.appendingPathComponent(dbName)
        let fileManager = FileManager.default

        let alternatives = legacyDefaultDatabaseLocationCandidates(
            fromUserInput: name,
            normalizedName: dbName,
            canonicalURL: canonicalURL
        )
        let existingAlternatives = alternatives.filter {
            fileManager.fileExists(atPath: $0.url.path)
        }
        let canonicalExists = fileManager.fileExists(atPath: canonicalURL.path)

        if canonicalExists {
            if !existingAlternatives.isEmpty {
                throw ambiguousDefaultDatabaseLocationError(
                    for: name,
                    candidates: [DefaultDatabaseLocationCandidate(url: canonicalURL, label: "canonical")] + existingAlternatives
                )
            }
            return canonicalURL
        }

        if existingAlternatives.count > 1 {
            throw ambiguousDefaultDatabaseLocationError(
                for: name,
                candidates: existingAlternatives
            )
        }

        if let existingAlternative = existingAlternatives.first {
            return existingAlternative.url
        }

        return canonicalURL
    }

    /// Normalize user input to canonical `.blazedb` naming.
    ///
    /// Rules:
    /// - `foo` -> `foo.blazedb`
    /// - `foo.blazedb` -> `foo.blazedb`
    /// - `foo.anything` -> error (explicit unsupported extension)
    ///
    /// Note: extension detection only inspects the final path component suffix.
    public static func normalizedDatabaseFileName(fromUserInput raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw DatabaseNameConventionError.emptyName
        }

        // Strip any path components if a caller accidentally passes a path-like string.
        let lastComponent = (trimmed as NSString).lastPathComponent
        let ext = (lastComponent as NSString).pathExtension.lowercased()
        let base = (lastComponent as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            throw DatabaseNameConventionError.emptyName
        }

        switch ext {
        case "":
            return "\(lastComponent).\(canonicalDatabaseExtension)"
        case canonicalDatabaseExtension:
            return lastComponent
        default:
            throw DatabaseNameConventionError.unsupportedExtension(
                found: ext,
                expected: canonicalDatabaseExtension
            )
        }
    }

    private static func legacyDefaultDatabaseLocationCandidates(
        fromUserInput raw: String,
        normalizedName dbName: String,
        canonicalURL: URL
    ) -> [DefaultDatabaseLocationCandidate] {
        var candidates: [DefaultDatabaseLocationCandidate] = []

        if let doubleExtensionURL = legacyDoubleExtensionDatabaseURL(
            fromUserInput: raw,
            canonicalURL: canonicalURL
        ) {
            candidates.append(DefaultDatabaseLocationCandidate(
                url: doubleExtensionURL,
                label: "legacy double-extension"
            ))
        }

        #if os(Linux)
        if let legacyURL = legacyApplicationSupportDatabaseURL(named: dbName) {
            candidates.append(DefaultDatabaseLocationCandidate(
                url: legacyURL,
                label: "legacy Linux Application Support"
            ))
        }
        #endif

        return candidates
    }

    private static func legacyDoubleExtensionDatabaseURL(
        fromUserInput raw: String,
        canonicalURL: URL
    ) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastComponent = (trimmed as NSString).lastPathComponent
        let ext = (lastComponent as NSString).pathExtension.lowercased()
        guard ext == canonicalDatabaseExtension else {
            return nil
        }

        // Before the shared normalization fix, named opens with "foo.blazedb"
        // created "foo.blazedb.blazedb". Keep that file reachable when it is
        // the only existing default-location candidate.
        return canonicalURL.appendingPathExtension(canonicalDatabaseExtension)
    }

    private static func ambiguousDefaultDatabaseLocationError(
        for name: String,
        candidates: [DefaultDatabaseLocationCandidate]
    ) -> BlazeDBError {
        let candidateList = candidates
            .map { "\($0.label): \($0.url.path)" }
            .joined(separator: "; ")
        return .invalidInput(
            reason: "Multiple default database files exist for '\(name)': \(candidateList). Open the intended file with open(at:password:) and remove or migrate the duplicate before using name-based open."
        )
    }

    #if os(Linux)
    /// Linux builds briefly used Foundation's Application Support directory here,
    /// which resolves near the XDG data directory but with a capitalized BlazeDB
    /// component. Prefer that existing file only to avoid hiding user data.
    private static func legacyApplicationSupportDatabaseURL(named dbName: String) -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("BlazeDB", isDirectory: true)
            .appendingPathComponent(dbName)
    }
    #endif
    
    /// Get the default database directory
    ///
    /// Returns the default BlazeDB directory used by ``PathResolver``.
    public static var defaultDatabaseDirectory: URL {
        get throws {
            try PathResolver.defaultDatabaseDirectory()
        }
    }
    
    // MARK: - Database Discovery
    
    /// Discover all databases in the default location
    ///
    /// Scans the platform default BlazeDB directory for all `.blazedb` files
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
        let searchName = try normalizedDatabaseFileName(fromUserInput: name)
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
    public static let shared = DatabaseRegistry()
    
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

