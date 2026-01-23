//
//  BlazeDBImporter.swift
//  BlazeDB
//
//  Database import API
//  Verifies integrity before restore, refuses mismatched schemas
//

import Foundation

/// Database importer
///
/// Restores databases from dump files with integrity verification.
public struct BlazeDBImporter {
    
    /// Restore database from dump file
    ///
    /// - Parameters:
    ///   - dumpURL: URL of dump file
    ///   - db: Target database client (must be empty or match schema)
    ///   - allowSchemaMismatch: If false, refuses mismatched schemas
    /// - Throws: Error if verification fails or restore fails
    ///
    /// ## Example
    /// ```swift
    /// let importer = BlazeDBImporter()
    /// try importer.restore(from: dumpURL, to: db, allowSchemaMismatch: false)
    /// ```
    public static func restore(
        from dumpURL: URL,
        to db: BlazeDBClient,
        allowSchemaMismatch: Bool = false
    ) throws {
        // Read dump file
        let dumpData = try Data(contentsOf: dumpURL)
        
        // Decode and verify integrity
        let dump = try DatabaseDump.decodeAndVerify(dumpData)
        
        // Verify schema compatibility
        let dbSchemaVersion = try db.getSchemaVersion() ?? SchemaVersion(major: 0, minor: 0)
        
        if !allowSchemaMismatch && dump.header.schemaVersion != dbSchemaVersion {
            throw BlazeDBError.migrationFailed(
                "Schema version mismatch: dump is \(dump.header.schemaVersion), database is \(dbSchemaVersion). Use allowSchemaMismatch: true to override, or run migrations first.",
                underlyingError: nil
            )
        }
        
        // Verify database is empty (or warn)
        let existingCount = db.getRecordCount()
        if existingCount > 0 {
            throw BlazeDBError.invalidInput(
                reason: "Cannot restore to non-empty database. Database has \(existingCount) records. Clear database first or use a new database."
            )
        }
        
        // Restore records
        for record in dump.records {
            // Insert record (ID preserved if present in storage["id"])
            try db.insert(record)
        }
        
        // Restore schema version
        try db.setSchemaVersion(dump.header.schemaVersion)
        
        // Verify restore succeeded
        let restoredCount = db.getRecordCount()
        guard restoredCount == dump.manifest.recordCount else {
            throw BlazeDBError.corruptedData(
                location: "restore verification",
                reason: "Record count mismatch: expected \(dump.manifest.recordCount), got \(restoredCount)"
            )
        }
    }
    
    /// Verify dump file integrity without restoring
    ///
    /// - Parameter dumpURL: URL of dump file
    /// - Returns: Dump header if valid
    /// - Throws: Error if verification fails
    public static func verify(_ dumpURL: URL) throws -> DumpHeader {
        let dumpData = try Data(contentsOf: dumpURL)
        let dump = try DatabaseDump.decodeAndVerify(dumpData)
        return dump.header
    }
}
