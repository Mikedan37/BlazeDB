//
//  BlazeDBClient+Export.swift
//  BlazeDB
//
//  Database export API
//  Deterministic, verifiable, complete
//

import Foundation

extension BlazeDBClient {
    
    /// Export database to dump file
    ///
    /// Creates a deterministic, verifiable dump of the entire database.
    /// The dump includes schema version, metadata, and all records.
    ///
    /// - Parameter url: File URL to write dump to
    /// - Throws: Error if export fails
    ///
    /// ## Example
    /// ```swift
    /// let dumpURL = FileManager.default.temporaryDirectory.appendingPathComponent("backup.blazedump")
    /// try db.export(to: dumpURL)
    /// ```
    public func export(to url: URL) throws {
        // Get schema version (or default to 0.0 for legacy)
        let schemaVersion = try getSchemaVersion() ?? SchemaVersion(major: 0, minor: 0)
        
        // Get all records in canonical order (sorted by ID)
        let allRecords = try fetchAll()
        let sortedRecords = allRecords.sorted { record1, record2 in
            let id1 = record1.storage["id"]?.uuidValue?.uuidString ?? ""
            let id2 = record2.storage["id"]?.uuidValue?.uuidString ?? ""
            return id1 < id2
        }
        
        // Create header
        let header = DumpHeader(
            formatVersion: .v1,
            schemaVersion: schemaVersion,
            databaseId: UUID(),  // Generate new ID for export
            exportedAt: Date(),
            databaseName: name,
            toolVersion: "BlazeDB-1.0"
        )
        
        // Encode dump (manifest computed during encoding)
        let data = try DatabaseDump.encode(header: header, records: sortedRecords)
        try data.write(to: url, options: [])
    }
    
    /// Export database to dump file (async)
    ///
    /// - Parameter url: File URL to write dump to
    /// - Throws: Error if export fails
    public func export(to url: URL) async throws {
        // Call the synchronous version - it's already thread-safe
        // Use a type-erased closure to force resolution to the sync version
        let syncExport: (BlazeDBClient, URL) throws -> Void = { db, url in
            try db.export(to: url)
        }
        try syncExport(self, url)
    }
}
