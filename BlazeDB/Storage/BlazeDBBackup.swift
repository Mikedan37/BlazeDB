//
//  BlazeDBBackup.swift
//  BlazeDB
//
//  Backup, export, and import functionality
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - Export/Import Formats

public enum ExportFormat: Sendable {
    case json
    case cbor
    case blazedb  // Native binary format
}

public enum ImportMode: Sendable {
    case append   // Add to existing data
    case replace  // Clear and replace
    case merge    // Update existing, add new
}

// MARK: - Backup Stats

public struct BackupStats: Sendable {
    public let recordCount: Int
    public let fileSize: Int64
    public let duration: TimeInterval
    public let timestamp: Date
    
    public var description: String {
        """
        Backup Stats:
          Records: \(recordCount)
          Size: \(fileSize / 1024 / 1024) MB
          Duration: \(String(format: "%.2f", duration))s
          Created: \(timestamp.formatted())
        """
    }
}

public struct ImportStats {
    public let recordsImported: Int
    public let recordsSkipped: Int
    public let recordsUpdated: Int
    public let duration: TimeInterval
    
    public var description: String {
        """
        Import Stats:
          Imported: \(recordsImported)
          Skipped: \(recordsSkipped)
          Updated: \(recordsUpdated)
          Duration: \(String(format: "%.2f", duration))s
        """
    }
}

// MARK: - BlazeDBClient Backup Extension

extension BlazeDBClient {
    
    // MARK: - Backup Operations
    
    /// Create a full backup of the database (synchronous)
    ///
    /// Creates a complete copy of the database file and all associated metadata.
    /// The backup is encrypted with the same key as the source database.
    ///
    /// **Safety:** Requires exclusive database access. The database must be open and
    /// have exclusive file lock. Backup will fail if another process has the database open.
    ///
    /// - Parameter url: Destination URL for the backup
    /// - Returns: Statistics about the backup operation
    /// - Throws: BlazeDBError if backup fails (e.g., database locked, disk full, permission denied)
    ///
    /// ## Example
    /// ```swift
    /// let backupURL = FileManager.default.temporaryDirectory
    ///     .appendingPathComponent("backup.blazedb")
    /// let stats = try db.backup(to: backupURL)
    /// print("Backed up \(stats.recordCount) records")
    /// ```
    public func backup(to url: URL) throws -> BackupStats {
        BlazeLogger.info("Starting backup to \(url.path)")
        let startTime = Date()
        
        // Ensure all pending changes are persisted before backup
        try persist()
        
        // Count records for stats
        let recordCount = try count()
        
        // Remove existing backup if it exists (overwrite behavior)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        // Copy database file
        try FileManager.default.copyItem(at: fileURL, to: url)
        
        // Copy metadata
        let backupMetaURL = url.deletingPathExtension().appendingPathExtension("meta")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            if FileManager.default.fileExists(atPath: backupMetaURL.path) {
                try FileManager.default.removeItem(at: backupMetaURL)
            }
            try FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }
        
        // Copy indexes if they exist
        let indexesURL = metaURL.deletingPathExtension().appendingPathExtension("indexes")
        let backupIndexesURL = backupMetaURL.deletingPathExtension().appendingPathExtension("indexes")
        if FileManager.default.fileExists(atPath: indexesURL.path) {
            if FileManager.default.fileExists(atPath: backupIndexesURL.path) {
                try FileManager.default.removeItem(at: backupIndexesURL)
            }
            try FileManager.default.copyItem(at: indexesURL, to: backupIndexesURL)
        }
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        let duration = Date().timeIntervalSince(startTime)
        
        let stats = BackupStats(
            recordCount: recordCount,
            fileSize: fileSize,
            duration: duration,
            timestamp: Date()
        )
        
        BlazeLogger.info("Backup complete: \(recordCount) records, \(fileSize / 1024 / 1024) MB, \(String(format: "%.2f", duration))s")
        return stats
    }
    
    /// Create a full backup of the database (async - convenience wrapper)
    ///
    /// Creates a complete copy of the database file and all associated metadata.
    /// The backup is encrypted with the same key as the source database.
    ///
    /// - Parameter url: Destination URL for the backup
    /// - Returns: Statistics about the backup operation
    /// - Throws: BlazeDBError if backup fails
    ///
    /// ## Example
    /// ```swift
    /// let backupURL = FileManager.default.temporaryDirectory
    ///     .appendingPathComponent("ashpile-backup.blazedb")
    /// let stats = try await db.backup(to: backupURL)
    /// print(stats.description)
    /// ```
    public func backup(to url: URL) async throws -> BackupStats {
        // Delegate to synchronous version
        return try await Task { try backup(to: url) }.value
    }
    
    /// Restore database from a backup (synchronous)
    ///
    /// Replaces the current database with a backup file.
    /// **WARNING:** This destroys current data! Use with caution.
    ///
    /// **Safety:** Requires exclusive database access. The database must be open and
    /// have exclusive file lock. Restore will fail if another process has the database open.
    /// The backup file must exist and be readable. The backup must use the same encryption
    /// key as the current database.
    ///
    /// - Parameter url: URL of the backup file
    /// - Throws: BlazeDBError if restore fails (e.g., backup not found, wrong encryption key, database locked)
    ///
    /// ## Example
    /// ```swift
    /// try db.restore(from: backupURL)
    /// print("Database restored from backup")
    /// ```
    public func restore(from url: URL) throws {
        BlazeLogger.warn("RESTORE: This will replace current database!")
        
        // Verify backup file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BlazeDBError.recordNotFound(
                id: nil,
                collection: nil,
                suggestion: "Backup file not found at \(url.path)"
            )
        }
        
        // Verify backup metadata exists
        let backupMetaURL = url.deletingPathExtension().appendingPathExtension("meta")
        guard FileManager.default.fileExists(atPath: backupMetaURL.path) else {
            throw BlazeDBError.corruptedData(
                location: "backup metadata",
                reason: "Backup metadata file not found at \(backupMetaURL.path). Backup may be incomplete."
            )
        }
        
        // Persist any pending changes before restore
        try persist()
        
        // Remove current files
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.removeItem(at: metaURL)
        }
        
        let indexesURL = metaURL.deletingPathExtension().appendingPathExtension("indexes")
        if FileManager.default.fileExists(atPath: indexesURL.path) {
            try? FileManager.default.removeItem(at: indexesURL)
        }
        
        // Copy backup files
        try FileManager.default.copyItem(at: url, to: fileURL)
        try FileManager.default.copyItem(at: backupMetaURL, to: metaURL)
        
        let backupIndexesURL = backupMetaURL.deletingPathExtension().appendingPathExtension("indexes")
        if FileManager.default.fileExists(atPath: backupIndexesURL.path) {
            try FileManager.default.copyItem(at: backupIndexesURL, to: indexesURL)
        }
        
        // Reload collection with restored files
        // This will use the same encryption key, so backup must have been created with same key
        let newStore = try PageStore(fileURL: fileURL, key: encryptionKey)
        collection = try DynamicCollection(
            store: newStore,
            metaURL: metaURL,
            project: project,
            encryptionKey: encryptionKey
        )
        
        BlazeLogger.info("Database restored from backup")
    }
    
    /// Restore database from a backup (async - convenience wrapper)
    ///
    /// Replaces the current database with a backup file.
    /// **WARNING:** This destroys current data! Use with caution.
    ///
    /// - Parameter url: URL of the backup file
    /// - Throws: BlazeDBError if restore fails
    ///
    /// ## Example
    /// ```swift
    /// try await db.restore(from: backupURL)
    /// print("Database restored from backup")
    /// ```
    public func restore(from url: URL) async throws {
        // Delegate to synchronous version
        try await Task { try restore(from: url) }.value
    }
    
    // MARK: - Export Operations
    
    /// Export all database records to a portable format
    ///
    /// Exports can be used for:
    /// - Data migration to other systems
    /// - External analysis
    /// - Version control
    /// - Sharing datasets
    ///
    /// - Parameter format: Export format (json, cbor, or native)
    /// - Returns: Encoded data
    /// - Throws: BlazeDBError if export fails
    ///
    /// ## Example
    /// ```swift
    /// // Export as JSON
    /// let jsonData = try await db.export(format: .json)
    /// try jsonData.write(to: documentsURL.appendingPathComponent("data.json"))
    ///
    /// // Export as CBOR (more efficient)
    /// let cborData = try await db.export(format: .cbor)
    /// ```
    public func export(format: ExportFormat = .json) async throws -> Data {
        BlazeLogger.info("📤 Exporting database in \(format) format")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let allRecords = try self.fetchAll()
                    
                    let data: Data
                    switch format {
                    case .json:
                        data = try JSONEncoder().encode(allRecords)
                        
                    case .cbor:
                        // CBOR not used anymore, use JSON
                        BlazeLogger.warn("CBOR format deprecated, using JSON instead")
                        data = try JSONEncoder().encode(allRecords)
                        
                    case .blazedb:
                        // Native format: Just copy the database
                        data = try Data(contentsOf: self.fileURL)
                    }
                    
                    BlazeLogger.info("✅ Exported \(allRecords.count) records (\(data.count) bytes)")
                    continuation.resume(returning: data)
                } catch {
                    BlazeLogger.error("❌ Export failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Export specific records matching a query
    ///
    /// - Parameters:
    ///   - where: Predicate to filter records
    ///   - format: Export format
    /// - Returns: Encoded data of matching records
    ///
    /// ## Example
    /// ```swift
    /// // Export only open bugs
    /// let openBugsData = try await db.export(
    ///     where: { $0.storage["status"]?.stringValue == "open" },
    ///     format: .json
    /// )
    /// ```
    public func export(
        where predicate: @escaping (BlazeDataRecord) -> Bool,
        format: ExportFormat = .json
    ) async throws -> Data {
        BlazeLogger.info("📤 Exporting filtered records in \(format) format")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let allRecords = try self.fetchAll()
                    let filtered = allRecords.filter(predicate)
                    
                    let data: Data
                    switch format {
                    case .json:
                        data = try JSONEncoder().encode(filtered)
                    case .cbor:
                        // CBOR not used anymore, use JSON
                        BlazeLogger.warn("CBOR format deprecated, using JSON instead")
                        data = try JSONEncoder().encode(filtered)
                    case .blazedb:
                        // For filtered export, use JSON
                        data = try JSONEncoder().encode(filtered)
                    }
                    
                    BlazeLogger.info("✅ Exported \(filtered.count) filtered records (\(data.count) bytes)")
                    continuation.resume(returning: data)
                } catch {
                    BlazeLogger.error("❌ Export failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Import Operations
    
    /// Import records from exported data
    ///
    /// - Parameters:
    ///   - data: Exported data to import
    ///   - format: Format of the data
    ///   - mode: Import mode (append, replace, or merge)
    /// - Returns: Import statistics
    /// - Throws: BlazeDBError if import fails
    ///
    /// ## Example
    /// ```swift
    /// // Import from JSON
    /// let jsonData = try Data(contentsOf: backupURL)
    /// let stats = try await db.import(from: jsonData, format: .json, mode: .append)
    /// print("Imported \(stats.recordsImported) records")
    /// ```
    public func `import`(
        from data: Data,
        format: ExportFormat = .json,
        mode: ImportMode = .append
    ) async throws -> ImportStats {
        BlazeLogger.info("📥 Importing data in \(format) format (mode: \(mode))")
        let startTime = Date()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Decode records
                    let records: [BlazeDataRecord]
                    switch format {
                    case .json:
                        records = try JSONDecoder().decode([BlazeDataRecord].self, from: data)
                    case .cbor:
                        // CBOR not used anymore, use JSON
                        BlazeLogger.warn("CBOR format deprecated, using JSON instead")
                        records = try JSONDecoder().decode([BlazeDataRecord].self, from: data)
                    case .blazedb:
                        // Native format import not supported in this mode
                        throw BlazeDBError.transactionFailed("Native .blazedb format requires restore() method", underlyingError: nil)
                    }
                    
                    var imported = 0
                    var skipped = 0
                    var updated = 0
                    
                    // Handle import mode
                    if mode == .replace {
                        // Delete all existing records
                        let existingCount = try self.count()
                        _ = try self.deleteMany(where: { _ in true })
                        BlazeLogger.debug("Deleted \(existingCount) existing records for replace mode")
                    }
                    
                    // Import records
                    for record in records {
                        // Check if record has ID
                        if let existingID = record.storage["id"]?.uuidValue {
                            if mode == .merge {
                                // Try to fetch existing
                                if try self.fetch(id: existingID) != nil {
                                    // Update existing
                                    try self.update(id: existingID, with: record)
                                    updated += 1
                                } else {
                                    // Insert new
                                    _ = try self.insert(record, id: existingID)
                                    imported += 1
                                }
                            } else {
                                // Append mode: check for duplicates
                                if try self.fetch(id: existingID) != nil {
                                    skipped += 1
                                } else {
                                    _ = try self.insert(record, id: existingID)
                                    imported += 1
                                }
                            }
                        } else {
                            // No ID: always insert as new
                            _ = try self.insert(record)
                            imported += 1
                        }
                    }
                    
                    let duration = Date().timeIntervalSince(startTime)
                    
                    let stats = ImportStats(
                        recordsImported: imported,
                        recordsSkipped: skipped,
                        recordsUpdated: updated,
                        duration: duration
                    )
                    
                    BlazeLogger.info("✅ Import complete: \(stats.description)")
                    continuation.resume(returning: stats)
                    
                } catch {
                    BlazeLogger.error("❌ Import failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Incremental Backup
    
    /// Create incremental backup (only records changed since last backup)
    ///
    /// - Parameters:
    ///   - url: Destination URL
    ///   - since: Only export records modified after this date
    /// - Returns: Backup statistics
    ///
    /// ## Example
    /// ```swift
    /// // Backup last 24 hours of changes
    /// let yesterday = Date().addingTimeInterval(-86400)
    /// let stats = try await db.incrementalBackup(to: incrementalURL, since: yesterday)
    /// ```
    public func incrementalBackup(to url: URL, since date: Date) async throws -> BackupStats {
        BlazeLogger.info("🔄 Creating incremental backup (since \(date))")
        let startTime = Date()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Fetch all records and filter by modification date
                    let allRecords = try self.fetchAll()
                    let changedRecords = allRecords.filter { record in
                        // Check if record was modified after the date
                        if let modDate = record.storage["updated_at"]?.dateValue ?? record.storage["created_at"]?.dateValue {
                            return modDate > date
                        }
                        return false  // No timestamp, skip
                    }
                    
                    // Export as JSON
                    let data = try JSONEncoder().encode(changedRecords)
                    try data.write(to: url)
                    
                    let duration = Date().timeIntervalSince(startTime)
                    
                    let stats = BackupStats(
                        recordCount: changedRecords.count,
                        fileSize: Int64(data.count),
                        duration: duration,
                        timestamp: Date()
                    )
                    
                    BlazeLogger.info("✅ Incremental backup: \(changedRecords.count) records (\(data.count) bytes)")
                    continuation.resume(returning: stats)
                    
                } catch {
                    BlazeLogger.error("❌ Incremental backup failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify a backup file is valid
    ///
    /// - Parameter url: Backup file URL
    /// - Returns: True if backup is valid
    ///
    /// ## Example
    /// ```swift
    /// if try await db.verifyBackup(at: backupURL) {
    ///     print("Backup is valid!")
    /// }
    /// ```
    public func verifyBackup(at url: URL) async throws -> Bool {
        BlazeLogger.info("🔍 Verifying backup at \(url.path)")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Try to open backup as a temporary database
                    let tempDB = try BlazeDBClient(
                        name: "BackupVerification",
                        fileURL: url,
                        password: "" // Will fail if wrong password
                    )
                    
                    // Try to count records
                    let count = try tempDB.count()
                    
                    BlazeLogger.info("✅ Backup verified: \(count) records")
                    continuation.resume(returning: true)
                    
                } catch {
                    BlazeLogger.warn("❌ Backup verification failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - Internal Helpers

extension BlazeDocumentField {
    /// Helper for export
    var exportValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v.timeIntervalSince1970
        case .uuid(let v): return v.uuidString
        case .data(let v): return v.base64EncodedString()
        case .array(let v): return v.map { $0.exportValue }
        case .dictionary(let v): return v.mapValues { $0.exportValue }
        case .vector(let v): return v
        case .null: return NSNull()
        }
    }
}

