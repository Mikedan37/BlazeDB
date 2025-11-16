//
//  SQLiteMigrator.swift
//  BlazeDB Migration Tools
//
//  Imports data from SQLite databases into BlazeDB
//

import Foundation
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
    /// - Throws: Error if migration fails
    ///
    /// Example:
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
        progressHandler: ((Int, Int) -> Void)? = nil
    ) throws {
        // Open SQLite database
        var db: OpaquePointer?
        guard sqlite3_open(source.path, &db) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw MigrationError.sqliteError("Failed to open SQLite database: \(error)")
        }
        defer { sqlite3_close(db) }
        
        // Get list of tables
        let tablesToImport: [String]
        if let tables = tables {
            tablesToImport = tables
        } else {
            tablesToImport = try getAllTables(from: db!)
        }
        
        // Create BlazeDB
        guard let blazeDB = BlazeDBClient(name: "Migration", at: destination, password: password) else {
            throw MigrationError.blazeDBError("Failed to initialize BlazeDB")
        }
        
        // Import each table
        var totalRecords = 0
        for (index, tableName) in tablesToImport.enumerated() {
            let records = try importTable(tableName, from: db!, into: blazeDB)
            totalRecords += records
            progressHandler?(index + 1, tablesToImport.count)
        }
        
        // Persist to disk
        try blazeDB.persist()
        
        print("✅ Migration complete: \(totalRecords) records from \(tablesToImport.count) tables")
    }
    
    // MARK: - Private Helpers
    
    private static func getAllTables(from db: OpaquePointer) throws -> [String] {
        var tables: [String] = []
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw MigrationError.sqliteError("Failed to query tables: \(error)")
        }
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                tables.append(String(cString: cString))
            }
        }
        
        return tables
    }
    
    private static func importTable(_ tableName: String, from sqliteDB: OpaquePointer, into blazeDB: BlazeDBClient) throws -> Int {
        let query = "SELECT * FROM \(tableName)"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(sqliteDB, query, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(sqliteDB))
            throw MigrationError.sqliteError("Failed to prepare query for table \(tableName): \(error)")
        }
        defer { sqlite3_finalize(statement) }
        
        // Get column names
        let columnCount = sqlite3_column_count(statement)
        var columnNames: [String] = []
        for i in 0..<columnCount {
            if let cString = sqlite3_column_name(statement, i) {
                columnNames.append(String(cString: cString))
            }
        }
        
        // Import rows
        var records: [BlazeDataRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var storage: [String: BlazeDocumentField] = [:]
            storage["_table"] = .string(tableName)  // Track original table name
            
            for (index, columnName) in columnNames.enumerated() {
                let columnType = sqlite3_column_type(statement, Int32(index))
                
                switch columnType {
                case SQLITE_INTEGER:
                    storage[columnName] = .int(Int(sqlite3_column_int64(statement, Int32(index))))
                    
                case SQLITE_FLOAT:
                    storage[columnName] = .double(sqlite3_column_double(statement, Int32(index)))
                    
                case SQLITE_TEXT:
                    if let cString = sqlite3_column_text(statement, Int32(index)) {
                        let text = String(cString: cString)
                        
                        // Try to parse as Date (ISO8601)
                        if let date = ISO8601DateFormatter().date(from: text) {
                            storage[columnName] = .date(date)
                        } else {
                            storage[columnName] = .string(text)
                        }
                    }
                    
                case SQLITE_BLOB:
                    let dataSize = sqlite3_column_bytes(statement, Int32(index))
                    if let dataPointer = sqlite3_column_blob(statement, Int32(index)) {
                        let data = Data(bytes: dataPointer, count: Int(dataSize))
                        storage[columnName] = .data(data)
                    }
                    
                case SQLITE_NULL:
                    // Skip NULL values
                    break
                    
                default:
                    break
                }
            }
            
            records.append(BlazeDataRecord(storage))
        }
        
        // Batch insert for performance
        if !records.isEmpty {
            _ = try blazeDB.insertMany(records)
            print("✅ Imported \(records.count) records from table '\(tableName)'")
        }
        
        return records.count
    }
}

// MARK: - Errors

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

