//
//  SQLiteMigrator.swift
//  BlazeDB
//
//  SQLite to BlazeDB migration tool
//  Integrated into main BlazeDB package
//
//  Created by Auto on 1/XX/25.
//

import Foundation

#if canImport(SQLite3)
import SQLite3

/// Tool for migrating data from SQLite to BlazeDB
public struct SQLiteMigrator {
    
    /// Import data from a SQLite database into BlazeDB
    ///
    /// - Parameters:
    ///   - source: URL to SQLite .db or .sqlite file
    ///   - destination: URL where BlazeDB file will be created
    ///   - password: Password for BlazeDB encryption
    ///   - tables: Optional array of table names to import (nil = all tables)
    ///   - progressHandler: Optional callback with (current, total) progress
    ///   - progressMonitor: Optional progress monitor for detailed tracking
    /// - Throws: MigrationError if migration fails
    ///
    /// ## Example
    /// ```swift
    /// try SQLiteMigrator.importFromSQLite(
    ///     source: URL(fileURLWithPath: "/path/to/app.sqlite"),
    ///     destination: URL(fileURLWithPath: "/path/to/app.blazedb"),
    ///     password: "secure-password",
    ///     tables: nil  // Import all tables
    /// ) { current, total in
    ///     print("Progress: \(current)/\(total)")
    /// }
    /// ```
    public static func importFromSQLite(
        source: URL,
        destination: URL,
        password: String,
        tables: [String]? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil,
        progressMonitor: MigrationProgressMonitor? = nil
    ) throws {
        BlazeLogger.info("🔄 Starting SQLite migration from \(source.path) to \(destination.path)")
        
        // Initialize progress monitor
        progressMonitor?.reset()
        
        // Open SQLite database
        var db: OpaquePointer?
        guard sqlite3_open(source.path, &db) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            BlazeLogger.error("❌ Failed to open SQLite database: \(error)")
            progressMonitor?.fail(MigrationError.sqliteError("Failed to open SQLite database: \(error)"))
            throw MigrationError.sqliteError("Failed to open SQLite database: \(error)")
        }
        defer { sqlite3_close(db) }
        
        // Get list of tables
        guard let dbUnwrapped = db else {
            throw MigrationError.sqliteError("SQLite database pointer is nil")
        }
        
        let tablesToImport: [String]
        if let tables = tables {
            tablesToImport = tables
            BlazeLogger.info("📋 Using specified tables: \(tablesToImport.joined(separator: ", "))")
        } else {
            tablesToImport = try getAllTables(from: dbUnwrapped)
            BlazeLogger.info("📋 Found \(tablesToImport.count) tables to import: \(tablesToImport.joined(separator: ", "))")
        }
        
        // Count total records for progress tracking
        var totalRecordsCount: Int = 0
        for tableName in tablesToImport {
            let count = try getTableRecordCount(from: dbUnwrapped, tableName: tableName)
            totalRecordsCount += count
            BlazeLogger.debug("📊 Table '\(tableName)': \(count) records")
        }
        
        BlazeLogger.info("📊 Total records to migrate: \(totalRecordsCount)")
        
        // Start progress monitor
        progressMonitor?.start(totalTables: tablesToImport.count, recordsTotal: totalRecordsCount)
        
        // Create BlazeDB
        let blazeDB = try BlazeDBClient(
            name: "Migration",
            fileURL: destination,
            password: password
        )
        BlazeLogger.debug("✅ BlazeDB created at \(destination.path)")
        
        // Record telemetry for migration start (if enabled)
        #if !BLAZEDB_LINUX_CORE
        blazeDB.telemetry.record(
            operation: "migration.sqlite.start",
            duration: 0,
            success: true,
            recordCount: totalRecordsCount
        )
        #endif
        
        // Import each table
        var totalRecords = 0
        for (index, tableName) in tablesToImport.enumerated() {
            BlazeLogger.info("📥 Importing table '\(tableName)' (\(index + 1)/\(tablesToImport.count))...")
            progressMonitor?.updateTable(tableName, index: index + 1, recordsProcessed: totalRecords)
            
            let records = try importTable(
                tableName,
                from: dbUnwrapped,
                into: blazeDB,
                progressMonitor: progressMonitor,
                baseRecordCount: totalRecords
            )
            totalRecords += records
            progressHandler?(index + 1, tablesToImport.count)
            BlazeLogger.info("✅ Imported \(records) records from '\(tableName)' (total: \(totalRecords))")
        }
        
        // Persist to disk
        BlazeLogger.debug("💾 Persisting to disk...")
        progressMonitor?.update(status: .creatingIndexes)
        try blazeDB.persist()
        
        progressMonitor?.complete(recordsProcessed: totalRecords)
        
        // Record telemetry for migration completion
        #if !BLAZEDB_LINUX_CORE
        let migrationDuration = Date().timeIntervalSince(progressMonitor?.getProgress().startTime ?? Date())
        blazeDB.telemetry.record(
            operation: "migration.sqlite.complete",
            duration: migrationDuration * 1000,  // Convert to milliseconds
            success: true,
            recordCount: totalRecords
        )
        #endif
        
        BlazeLogger.info("✅ Migration complete: \(totalRecords) records from \(tablesToImport.count) tables")
    }
    
    // MARK: - Private Helpers
    
    private static func getAllTables(from db: OpaquePointer) throws -> [String] {
        var tables: [String] = []
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw MigrationError.sqliteError("Failed to prepare query")
        }
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                let tableName = String(cString: cString)
                tables.append(tableName)
            }
        }
        
        return tables
    }
    
    private static func getTableRecordCount(from db: OpaquePointer, tableName: String) throws -> Int {
        let countQuery = "SELECT COUNT(*) FROM \(tableName)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, countQuery, -1, &statement, nil) == SQLITE_OK else {
            return 0  // If count fails, return 0 (will still migrate)
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }
    
    private static func importTable(
        _ tableName: String,
        from db: OpaquePointer,
        into blazeDB: BlazeDBClient,
        progressMonitor: MigrationProgressMonitor? = nil,
        baseRecordCount: Int = 0
    ) throws -> Int {
        BlazeLogger.debug("🔍 Getting column info for table '\(tableName)'...")
        
        // Get column info
        let columnQuery = "PRAGMA table_info(\(tableName))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, columnQuery, -1, &statement, nil) == SQLITE_OK else {
            let error = "Failed to get column info for \(tableName)"
            BlazeLogger.error("❌ \(error)")
            throw MigrationError.sqliteError(error)
        }
        defer { sqlite3_finalize(statement) }
        
        var columns: [(name: String, type: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameCString = sqlite3_column_text(statement, 1),
               let typeCString = sqlite3_column_text(statement, 2) {
                let name = String(cString: nameCString)
                let type = String(cString: typeCString)
                columns.append((name: name, type: type))
            }
        }
        
        BlazeLogger.debug("📋 Found \(columns.count) columns in '\(tableName)': \(columns.map { $0.name }.joined(separator: ", "))")
        
        // Fetch all rows with efficient batching
        BlazeLogger.debug("📥 Fetching rows from '\(tableName)'...")
        let selectQuery = "SELECT * FROM \(tableName)"
        var selectStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectQuery, -1, &selectStatement, nil) == SQLITE_OK else {
            let error = "Failed to select from \(tableName)"
            BlazeLogger.error("❌ \(error)")
            throw MigrationError.sqliteError(error)
        }
        defer { sqlite3_finalize(selectStatement) }
        
        var records: [BlazeDataRecord] = []
        let batchSize = 1000  // Process in batches of 1000 records
        var totalCount = 0
        var nullValueCount = 0
        
        while sqlite3_step(selectStatement) == SQLITE_ROW {
            var document: [String: BlazeDocumentField] = [:]
            
            for (index, column) in columns.enumerated() {
                let columnType = sqlite3_column_type(selectStatement, Int32(index))
                
                if columnType == SQLITE_NULL {
                    nullValueCount += 1
                    continue  // Skip NULL values (BlazeDB doesn't store null, missing fields are nil)
                }
                
                let value: BlazeDocumentField
                switch columnType {
                case SQLITE_INTEGER:
                    value = .int(Int(sqlite3_column_int64(selectStatement, Int32(index))))
                case SQLITE_FLOAT:
                    value = .double(sqlite3_column_double(selectStatement, Int32(index)))
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(selectStatement, Int32(index)) {
                        value = .string(String(cString: cString))
                    } else {
                        continue
                    }
                case SQLITE_BLOB:
                    if let blob = sqlite3_column_blob(selectStatement, Int32(index)) {
                        let length = sqlite3_column_bytes(selectStatement, Int32(index))
                        let data = Data(bytes: blob, count: Int(length))
                        value = .data(data)
                    } else {
                        continue
                    }
                default:
                    continue
                }
                
                document[column.name] = value
            }
            
            // Convert to BlazeDataRecord
            let record = BlazeDataRecord(document)
            records.append(record)
            
            // Batch insert when batch size reached
            if records.count >= batchSize {
                _ = try blazeDB.insertMany(records)
                totalCount += records.count
                records.removeAll(keepingCapacity: true)  // Keep capacity for efficiency
                
                // Update progress monitor
                progressMonitor?.update(recordsProcessed: baseRecordCount + totalCount)
            }
        }
        
        // Insert remaining records
        if !records.isEmpty {
            _ = try blazeDB.insertMany(records)
            totalCount += records.count
            progressMonitor?.update(recordsProcessed: baseRecordCount + totalCount)
        }
        
        if nullValueCount > 0 {
            BlazeLogger.debug("⚠️ Skipped \(nullValueCount) NULL values (BlazeDB uses missing fields instead of null)")
        }
        BlazeLogger.debug("✅ Table '\(tableName)' complete: \(totalCount) records")
        return totalCount
    }
}

#else
// Fallback when SQLite3 is not available
public struct SQLiteMigrator {
    public static func importFromSQLite(
        source: URL,
        destination: URL,
        password: String,
        tables: [String]? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil,
        progressMonitor: MigrationProgressMonitor? = nil
    ) throws {
        throw MigrationError.sqliteError("SQLite3 not available on this platform")
    }
}
#endif

// MARK: - Migration Errors

public enum MigrationError: Error, LocalizedError {
    case sqliteError(String)
    case blazeDBError(String)
    case coreDataError(String)
    case invalidData(String)
    
    public var errorDescription: String? {
        switch self {
        case .sqliteError(let msg): return "SQLite error: \(msg)"
        case .blazeDBError(let msg): return "BlazeDB error: \(msg)"
        case .coreDataError(let msg): return "Core Data error: \(msg)"
        case .invalidData(let msg): return "Invalid data: \(msg)"
        }
    }
}

