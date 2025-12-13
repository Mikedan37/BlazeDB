//
//  SQLMigrator.swift
//  BlazeDB
//
//  SQL command execution and migration tool
//  For users with SQL commands (CREATE TABLE, INSERT, etc.)
//
//  Created by Auto on 1/XX/25.
//

import Foundation

#if canImport(SQLite3)
import SQLite3

/// Tool for migrating from SQL commands (CREATE TABLE, INSERT, etc.) to BlazeDB
public struct SQLMigrator {
    
    /// Execute SQL commands and migrate to BlazeDB
    ///
    /// This method creates a temporary SQLite database, executes your SQL commands,
    /// then migrates the data to BlazeDB. Perfect for users with SQL scripts.
    ///
    /// - Parameters:
    ///   - sqlCommands: Array of SQL commands to execute (CREATE TABLE, INSERT, etc.)
    ///   - destination: URL where BlazeDB file will be created
    ///   - password: Password for BlazeDB encryption
    ///   - progressHandler: Optional callback with (current, total) progress
    /// - Throws: MigrationError if migration fails
    ///
    /// ## Example
    /// ```swift
    /// let sqlCommands = [
    ///     "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)",
    ///     "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')",
    ///     "INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')"
    /// ]
    ///
    /// try SQLMigrator.importFromSQL(
    ///     sqlCommands: sqlCommands,
    ///     destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
    ///     password: "secure-password"
    /// )
    /// ```
    public static func importFromSQL(
        sqlCommands: [String],
        destination: URL,
        password: String,
        progressHandler: ((Int, Int) -> Void)? = nil,
        progressMonitor: MigrationProgressMonitor? = nil
    ) throws {
        BlazeLogger.info("🔄 Starting SQL migration to \(destination.path)")
        BlazeLogger.debug("📝 Executing \(sqlCommands.count) SQL commands")
        
        // Initialize progress monitor
        progressMonitor?.reset()
        progressMonitor?.update(status: .preparing)
        
        // Create temporary SQLite database
        let tempSQLiteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).sqlite")
        
        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempSQLiteURL)
        }
        
        // Step 1: Create SQLite database and execute SQL commands
        var sqliteDB: OpaquePointer?
        guard sqlite3_open(tempSQLiteURL.path, &sqliteDB) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(sqliteDB))
            BlazeLogger.error("❌ Failed to create temporary SQLite database: \(error)")
            progressMonitor?.fail(MigrationError.sqliteError("Failed to create temporary SQLite database: \(error)"))
            throw MigrationError.sqliteError("Failed to create temporary SQLite database: \(error)")
        }
        defer { sqlite3_close(sqliteDB) }
        
        BlazeLogger.debug("✅ Temporary SQLite database created")
        
        // Execute each SQL command
        for (index, sqlCommand) in sqlCommands.enumerated() {
            var errorMessage: UnsafeMutablePointer<CChar>?
            
            let result = sqlite3_exec(
                sqliteDB,
                sqlCommand,
                nil,
                nil,
                &errorMessage
            )
            
            if result != SQLITE_OK {
                let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                BlazeLogger.error("❌ SQL execution failed at command \(index + 1): \(error)")
                BlazeLogger.debug("Failed command: \(sqlCommand)")
                progressMonitor?.fail(MigrationError.sqliteError("SQL execution failed at command \(index + 1): \(error)\nCommand: \(sqlCommand)"))
                throw MigrationError.sqliteError("SQL execution failed at command \(index + 1): \(error)\nCommand: \(sqlCommand)")
            }
            
            sqlite3_free(errorMessage)
            
            if (index + 1) % 10 == 0 {
                BlazeLogger.debug("📝 Executed \(index + 1)/\(sqlCommands.count) SQL commands")
            }
        }
        
        BlazeLogger.info("✅ SQL commands executed successfully (\(sqlCommands.count) commands)")
        
        // Step 2: Migrate from temporary SQLite to BlazeDB
        // Note: Telemetry will be recorded by SQLiteMigrator
        try SQLiteMigrator.importFromSQLite(
            source: tempSQLiteURL,
            destination: destination,
            password: password,
            tables: nil,  // Import all tables
            progressHandler: progressHandler,
            progressMonitor: progressMonitor
        )
        
        BlazeLogger.info("✅ SQL migration complete")
    }
    
    /// Import from SQL file
    ///
    /// Reads SQL commands from a file and migrates to BlazeDB.
    ///
    /// - Parameters:
    ///   - sqlFileURL: URL to SQL file
    ///   - destination: URL where BlazeDB file will be created
    ///   - password: Password for BlazeDB encryption
    ///   - progressHandler: Optional callback with progress
    /// - Throws: MigrationError if migration fails
    ///
    /// ## Example
    /// ```swift
    /// let sqlFile = URL(fileURLWithPath: "/path/to/schema.sql")
    /// try SQLMigrator.importFromSQLFile(
    ///     sqlFileURL: sqlFile,
    ///     destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
    ///     password: "secure-password"
    /// )
    /// ```
    public static func importFromSQLFile(
        sqlFileURL: URL,
        destination: URL,
        password: String,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        // Read SQL file
        let sqlContent = try String(contentsOf: sqlFileURL, encoding: .utf8)
        
        // Split into individual commands (semicolon-separated)
        let commands = sqlContent
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("--") }  // Remove empty and comments
        
        // Execute migration
        try importFromSQL(
            sqlCommands: commands,
            destination: destination,
            password: password,
            progressHandler: progressHandler
        )
    }
}

#else
// Fallback when SQLite3 is not available
public struct SQLMigrator {
    public static func importFromSQL(
        sqlCommands: [String],
        destination: URL,
        password: String,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        throw MigrationError.sqliteError("SQLite3 not available on this platform")
    }
    
    public static func importFromSQLFile(
        sqlFileURL: URL,
        destination: URL,
        password: String,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        throw MigrationError.sqliteError("SQLite3 not available on this platform")
    }
}
#endif

