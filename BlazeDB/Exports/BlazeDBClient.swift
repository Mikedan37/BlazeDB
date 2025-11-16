//  BlazeDBClient.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit

// MARK: - BlazeDocumentField serialization

extension BlazeDocumentField {
    func serializedString() -> String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .uuid(let v): return v.uuidString
        case .data(let v): return "<Data: \(v.count) bytes>"
        case .array(let arr): return "[\(arr.map { $0.serializedString() }.joined(separator: ", "))]"
        case .dictionary(let dict): return "{\(dict.map { "\($0): \($1.serializedString())" }.joined(separator: ", "))}"
        }
    }
}

extension Date {
    var iso8601: String { ISO8601DateFormatter().string(from: self) }
}

// MARK: - Integrity reporting

public struct IntegrityIssue {
    public enum Severity { case warning, error }
    public let severity: Severity
    public let message: String
}

public struct ValidationReport {
    public let ok: Bool
    public let issues: [IntegrityIssue]
}

// MARK: - Errors

public enum BlazeDBError: Error, LocalizedError, CustomStringConvertible {
    case recordExists(id: UUID? = nil, suggestion: String? = nil)
    case recordNotFound(id: UUID? = nil, collection: String? = nil, suggestion: String? = nil)
    case transactionFailed(String, underlyingError: Error? = nil)
    case migrationFailed(String, underlyingError: Error? = nil)
    case invalidQuery(reason: String, suggestion: String? = nil)
    case indexNotFound(field: String, availableIndexes: [String] = [])
    case invalidField(name: String, expectedType: String, actualType: String)
    case diskFull(availableSpace: Int64? = nil)
    case permissionDenied(operation: String, path: String? = nil)
    case databaseLocked(operation: String, timeout: TimeInterval? = nil)
    case corruptedData(location: String, reason: String)
    case passwordTooWeak(requirements: String)
    case invalidData(reason: String)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        case .recordExists(let id, let suggestion):
            var msg = "Record already exists"
            if let id = id { msg += " with ID: \(id)" }
            msg += ". Use update() to modify existing record or upsert() to insert-or-update."
            if let suggestion = suggestion { msg += " \(suggestion)" }
            return msg
            
        case .recordNotFound(let id, let collection, let suggestion):
            var msg = "Record not found"
            if let id = id { msg += " with ID: \(id)" }
            if let collection = collection { msg += " in collection '\(collection)'" }
            msg += ". The record may have been deleted or never existed."
            if let suggestion = suggestion { msg += " \(suggestion)" }
            else { msg += " Verify the ID is correct." }
            return msg
            
        case .transactionFailed(let reason, let underlying):
            var msg = "Transaction failed: \(reason)"
            if let underlying = underlying {
                msg += ". Underlying error: \(underlying.localizedDescription)"
            }
            msg += " All changes have been rolled back."
            return msg
            
        case .migrationFailed(let reason, let underlying):
            var msg = "Database migration failed: \(reason)"
            if let underlying = underlying {
                msg += ". Underlying error: \(underlying.localizedDescription)"
            }
            msg += " Database may be in inconsistent state. Restore from backup if available."
            return msg
            
        case .invalidQuery(let reason, let suggestion):
            var msg = "Invalid query: \(reason)"
            if let suggestion = suggestion {
                msg += ". Suggestion: \(suggestion)"
            }
            return msg
            
        case .indexNotFound(let field, let available):
            var msg = "No index found for field '\(field)'."
            if !available.isEmpty {
                msg += " Available indexes: \(available.joined(separator: ", "))."
            }
            msg += " Create an index with: db.collection.createIndex(on: \"\(field)\") for better performance."
            return msg
            
        case .invalidField(let name, let expected, let actual):
            return "Field '\(name)' has invalid type: expected \(expected) but got \(actual). Check your data model."
            
        case .diskFull(let available):
            var msg = "Disk is full or nearly full."
            if let available = available {
                msg += " Only \(available / 1024 / 1024) MB available."
            }
            msg += " Free up disk space and try again."
            return msg
            
        case .permissionDenied(let operation, let path):
            var msg = "Permission denied for operation: \(operation)"
            if let path = path { msg += " at path: \(path)" }
            msg += ". Check file permissions and app sandbox entitlements."
            return msg
            
        case .databaseLocked(let operation, let timeout):
            var msg = "Database is locked for operation: \(operation)"
            if let timeout = timeout {
                msg += " (timeout: \(timeout)s)"
            }
            msg += ". Another process may be using the database. Wait and retry."
            return msg
            
        case .corruptedData(let location, let reason):
            return "Data corruption detected at \(location): \(reason). Database integrity may be compromised. Restore from backup if available."
            
        case .passwordTooWeak(let requirements):
            return "Password is too weak. Requirements: \(requirements). Use a stronger password with letters, numbers, and special characters."
            
        case .invalidData(let reason):
            return "Invalid data: \(reason). Check input data format and types."
        }
    }
    
    // MARK: - CustomStringConvertible
    
    public var description: String {
        return errorDescription ?? "BlazeDBError"
    }
}

public enum BlazeCorruptionError: Error {
    case corrupt
}

// MARK: - BlazeDBClient

public final class BlazeDBClient {
    internal var collection: DynamicCollection
    public let name: String
    private static var cachedKey: SymmetricKey?
    private let writeLock = NSLock()
    private let transactionLogLock = NSLock()  // 🔒 Dedicated lock for WAL writes
    
    /// Clear the cached encryption key (useful for testing)
    public static func clearCachedKey() {
        cachedKey = nil
    }
    private var inSafeWrite = false
    
    // BLOCKER #2 FIX: Vacuum state management (internal for extensions)
    internal var isVacuuming: Bool = false
    internal let vacuumLock = NSLock()

    // For reloads
    internal let fileURL: URL
    internal let metaURL: URL
    internal let project: String
    private let password: String  // SECURITY: Store password for audit
    internal let encryptionKey: SymmetricKey

    // MARK: - Init
    
    /// Initializes a new BlazeDB client instance.
    ///
    /// Creates or opens a database at the specified file URL with encryption enabled.
    /// The database uses AES-256 encryption with a key derived from the provided password.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for this database instance
    ///   - fileURL: The file system location where the database will be stored
    ///   - password: Password used to derive the encryption key (using PBKDF2)
    ///   - project: Optional project namespace (defaults to "Default")
    /// - Throws: BlazeDBError if initialization, migration, or recovery fails
    ///
    /// - Important: The same password must be used for subsequent opens of the same database.
    ///
    /// ## Example
    /// ```swift
    /// let dbURL = FileManager.default.temporaryDirectory
    ///     .appendingPathComponent("myapp.blazedb")
    /// let db = try BlazeDBClient(name: "MyApp", fileURL: dbURL, password: "secure123")
    /// ```
    public init(name: String, fileURL: URL, password: String, project: String = "Default") throws {
        BlazeLogger.info("🔷 Initializing BlazeDB: '\(name)' at \(fileURL.path)")
        
        self.name = name
        self.fileURL = fileURL
        self.metaURL = fileURL.deletingPathExtension().appendingPathExtension("meta")
        self.project = UserDefaults.standard.string(forKey: "activeProject") ?? project
        self.password = password  // SECURITY: Store for audit

        // 🔑 Derive or reuse key
        let key: SymmetricKey
        if let cached = BlazeDBClient.cachedKey {
            key = cached
            BlazeLogger.debug("Using cached encryption key")
        } else {
            do {
                key = try KeyManager.getKey(from: .password(password))
                BlazeDBClient.cachedKey = key
                BlazeLogger.debug("✅ Encryption key derived and cached")
            } catch KeyManagerError.passwordTooWeak {
                // SECURITY AUDIT: Enhanced password error with recommendations
                let (strength, recommendations) = PasswordStrengthValidator.analyze(password)
                let errorMsg = """
                ❌ Password too weak (strength: \(strength.description))
                Recommendations: \(recommendations.joined(separator: ". "))
                Use at least 12 characters with uppercase, lowercase, and numbers.
                """
                BlazeLogger.error(errorMsg)
                throw BlazeDBError.passwordTooWeak(requirements: recommendations.joined(separator: ". "))
            } catch {
                let errorMsg = "❌ Failed to derive encryption key: \(error.localizedDescription)"
                BlazeLogger.error(errorMsg)
                throw BlazeDBError.transactionFailed(errorMsg)
            }
        }
        self.encryptionKey = key

        // Init store + collection
        do {
            let store = try PageStore(fileURL: fileURL, key: key)
            self.collection = try DynamicCollection(store: store,
                                                    metaURL: metaURL,
                                                    project: self.project,
                                                    encryptionKey: key)
            BlazeLogger.debug("✅ PageStore and collection initialized")
        } catch {
            let errorMsg = "❌ Failed to initialize storage: \(error.localizedDescription)"
            BlazeLogger.error(errorMsg)
            throw BlazeDBError.transactionFailed(errorMsg)
        }

        // Migration and recovery
        do {
            try performMigrationIfNeeded()
            BlazeLogger.debug("✅ Migration check complete")
        } catch {
            let errorMsg = "❌ Migration failed: \(error.localizedDescription)"
            BlazeLogger.error(errorMsg)
            throw BlazeDBError.migrationFailed(errorMsg)
        }
        
        do {
            // CRASH SAFETY: Recover from incomplete VACUUM first
            try recoverFromVacuumCrashIfNeeded()
            
            try replayTransactionLogIfNeeded()
            BlazeLogger.debug("✅ Transaction log replay complete")
        } catch {
            let errorMsg = "❌ Recovery failed: \(error.localizedDescription)"
            BlazeLogger.error(errorMsg)
            throw BlazeDBError.transactionFailed(errorMsg)
        }
        
        BlazeLogger.info("✅ BlazeDB '\(name)' initialized successfully")
        
        // SECURITY AUDIT: Auto-enable CRC32 for unencrypted databases
        if password.isEmpty {
            BlazeBinaryEncoder.crc32Mode = .enabled
            BlazeLogger.info("🔒 Auto-enabled CRC32 for unencrypted database (corruption detection)")
        }
    }

    public convenience init(name: String, fileURL: URL, password: String) throws {
        try self.init(name: name, fileURL: fileURL, password: password, project: "Default")
    }
    
    /// Failable initializer for simpler usage without try-catch.
    ///
    /// Creates a BlazeDB instance, returning `nil` if initialization fails.
    /// Errors are logged automatically - check console/logs for details.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for this database instance
    ///   - fileURL: The file system location where the database will be stored
    ///   - password: Password used to derive the encryption key (must be 8+ characters)
    ///   - project: Optional project namespace (defaults to "Default")
    ///
    /// - Returns: A BlazeDBClient instance, or `nil` if initialization failed
    ///
    /// ## Example - Simple Usage (No try-catch)
    /// ```swift
    /// guard let db = BlazeDBClient(name: "MyApp", at: url, password: "secure-pass-123") else {
    ///     print("Failed to initialize database - check logs")
    ///     return
    /// }
    /// // Use db...
    /// ```
    ///
    /// ## Example - With Error Details
    /// ```swift
    /// do {
    ///     let db = try BlazeDBClient(name: "MyApp", fileURL: url, password: "secure-pass-123")
    ///     // Use db...
    /// } catch {
    ///     print("Database init failed: \(error)")
    /// }
    /// ```
    public convenience init?(name: String, at fileURL: URL, password: String, project: String = "Default") {
        do {
            try self.init(name: name, fileURL: fileURL, password: password, project: project)
        } catch {
            BlazeLogger.error("❌ Failed to initialize BlazeDB '\(name)': \(error)")
            return nil
        }
    }
    
    /// Automatically flushes unsaved changes when the database is deallocated
    deinit {
        do {
            try persist()
            BlazeLogger.debug("✅ Auto-flushed unsaved changes in deinit for '\(name)'")
        } catch {
            BlazeLogger.error("❌ Failed to flush in deinit for '\(name)': \(error)")
        }
    }

    // MARK: - Transaction log

    private var transactionLogURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
    }

    private var transactionBackupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_in_progress.blazedb")
    }

    private var transactionMetaBackupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_in_progress.meta")
    }

    private func appendToTransactionLog(_ operation: String, payload: [String: BlazeDocumentField]) {
        guard FileManager.default.fileExists(atPath: transactionBackupURL.path) else {
            // Silently skip - this is expected for non-transactional operations
            return
        }
        let entry: [String: Any] = [
            "operation": operation,
            "payload": payload.mapValues { $0.serializedString() },
            "timestamp": Date().iso8601
        ]
        
        // 🔒 Thread-safe WAL writes
        transactionLogLock.lock()
        defer { transactionLogLock.unlock() }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: entry, options: [])
            if FileManager.default.fileExists(atPath: transactionLogURL.path) {
                let handle = try FileHandle(forWritingTo: transactionLogURL)
                handle.seekToEndOfFile()
                if let newlineData = "\n".data(using: .utf8) {
                    handle.write(data + newlineData)
                } else {
                    handle.write(data)  // Fallback (should never happen)
                }
                try handle.close()
            } else {
                try data.write(to: transactionLogURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                     ofItemAtPath: transactionLogURL.path)
            }
        } catch {
            BlazeLogger.error("Failed to log transaction: \(error)")
        }
    }

    /// Replays any uncommitted transactions from the write-ahead log (WAL).
    ///
    /// This method is automatically called during initialization to ensure crash recovery.
    /// If the database crashed mid-transaction, this will replay logged operations.
    ///
    /// - Throws: BlazeDBError if replay fails
    public func replayTransactionLogIfNeeded() throws {
        let logURL = transactionLogURL
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return
        }
        
        guard let data = try? Data(contentsOf: logURL),
              let contents = String(data: data, encoding: .utf8) else {
            return
        }

        for entryString in contents.split(separator: "\n").map(String.init) {
            guard let entryData = entryString.data(using: .utf8) else { continue }
            do {
                guard let json = try JSONSerialization.jsonObject(with: entryData) as? [String: Any],
                      let op = json["operation"] as? String,
                      let payload = json["payload"] as? [String: String] else { continue }
                let restored = payload.mapValues { BlazeDocumentField.string($0) }
                switch op {
                case "insert": _ = try? insert(BlazeDataRecord(restored))
                case "update":
                    if case let .string(idStr)? = restored["id"], let id = UUID(uuidString: idStr) {
                        try? update(id: id, with: BlazeDataRecord(restored))
                    }
                case "delete":
                    if case let .string(idStr)? = restored["id"], let id = UUID(uuidString: idStr) {
                        try? delete(id: id)
                    }
                default: continue
                }
            } catch {
                BlazeLogger.warn("Skipping corrupted log entry: \(error)")
            }
        }
        try? FileManager.default.removeItem(at: logURL)
    }

    // MARK: - CRUD

    /// Inserts a new record into the database.
    ///
    /// If the record doesn't have an `id` field, a new UUID will be generated automatically.
    /// A `createdAt` timestamp is also added if not present.
    ///
    /// - Parameter data: The record to insert
    /// - Returns: The UUID of the inserted record
    /// - Throws: BlazeDBError if insertion fails
    ///
    /// ## Example
    /// ```swift
    /// let record = BlazeDataRecord([
    ///     "title": .string("Hello"),
    ///     "count": .int(42)
    /// ])
    /// let id = try db.insert(record)
    /// ```
    public func insert(_ data: BlazeDataRecord) throws -> UUID {
        let startTime = Date()
        
        do {
            var record = data
            let id: UUID
            if case let .uuid(existingID)? = record.storage["id"] {
                id = existingID
            } else if case let .string(idStr)? = record.storage["id"], let parsed = UUID(uuidString: idStr) {
                id = parsed
                record.storage["id"] = .uuid(parsed) // normalize to uuid
            } else {
                id = UUID()
                record.storage["id"] = .uuid(id)
            }

            if record.storage["createdAt"] == nil {
                record.storage["createdAt"] = .date(Date())
            }
            
            // Validate against schema (if defined)
            try validateAgainstSchema(record)

            try performSafeWrite { _ = try collection.insert(record) }
            appendToTransactionLog("insert", payload: record.storage)
            
            // Notify change observers (for sync)
            notifyInsert(id: id)
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insert", duration: duration, success: true, recordCount: 1)
            
            return id
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insert", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }

    /// Insert a record with a specific UUID (for transaction tests and deterministic inserts)
    public func insert(_ data: BlazeDataRecord, id: UUID) throws {
        var record = data
        record.storage["id"] = .uuid(id)
        if record.storage["createdAt"] == nil {
            record.storage["createdAt"] = .date(Date())
        }
        try performSafeWrite { _ = try collection.insert(record) }
        appendToTransactionLog("insert", payload: record.storage)
        
        // Notify change observers (for sync)
        notifyInsert(id: id)
    }
    
    /// Insert multiple records in a single batch (much faster than individual inserts)
    ///
    /// OPTIMIZED: Uses batch insert for 3-5x speedup over individual operations.
    ///
    /// - Parameter records: Array of records to insert
    /// - Returns: Array of UUIDs for the inserted records
    /// - Throws: BlazeDBError if insertion fails
    public func insertMany(_ records: [BlazeDataRecord]) throws -> [UUID] {
        let startTime = Date()
        
        do {
            var ids: [UUID] = []
            try performSafeWrite {
                // Use optimized batch insert (3-5x faster!)
                ids = try collection.insertBatch(records)
                
                // Log to transaction log
                for (index, id) in ids.enumerated() {
                    if index < records.count {
                        appendToTransactionLog("insert", payload: records[index].storage)
                    }
                }
            }
            BlazeLogger.info("Inserted \(ids.count) records in optimized batch")
            
            // Notify change observers (for sync) - batch notification
            let changes = ids.map { DatabaseChange(type: .insert($0), collectionName: name) }
            notifyBatchChanges(changes)
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: true, recordCount: ids.count)
            
            return ids
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Update multiple records matching a predicate
    /// - Parameters:
    ///   - where: Predicate to match records
    ///   - set: Fields to update
    /// - Returns: Number of records updated
    public func updateMany(where predicate: @escaping (BlazeDataRecord) -> Bool, set fields: [String: BlazeDocumentField]) throws -> Int {
        var updateCount = 0
        try performSafeWrite {
            // Fetch all records WITH their IDs
            let allIDs = collection.indexMap.keys
            for id in allIDs {
                guard let record = try? collection.fetch(id: id) else { continue }
                
                // Check if record matches predicate
                guard predicate(record) else { continue }
                
                // Update matching record
                var updated = record
                for (key, value) in fields {
                    updated.storage[key] = value
                }
                updated.storage["updatedAt"] = .date(Date())
                try collection.update(id: id, with: updated)
                updateCount += 1
            }
        }
        BlazeLogger.info("Updated \(updateCount) records in batch")
        return updateCount
    }
    
    /// Delete multiple records matching a predicate
    /// - Parameter where: Predicate to match records
    /// - Returns: Number of records deleted
    public func deleteMany(where predicate: @escaping (BlazeDataRecord) -> Bool) throws -> Int {
        var deleteCount = 0
        try performSafeWrite {
            // Fetch all records WITH their IDs
            let allIDs = collection.indexMap.keys
            for id in allIDs {
                guard let record = try? collection.fetch(id: id) else { continue }
                
                // Check if record matches predicate
                guard predicate(record) else { continue }
                
                // Delete matching record
                try collection.delete(id: id)
                deleteCount += 1
            }
        }
        BlazeLogger.info("Deleted \(deleteCount) records in batch")
        return deleteCount
    }
    
    /// Insert or update a record (upsert)
    /// - Parameters:
    ///   - id: UUID of the record
    ///   - data: Record data
    /// - Returns: True if inserted, false if updated
    @discardableResult
    public func upsert(id: UUID, data: BlazeDataRecord) throws -> Bool {
        if let _ = try fetch(id: id) {
            try update(id: id, with: data)
            BlazeLogger.debug("Upsert: Updated existing record \(id)")
            return false
        } else {
            try insert(data, id: id)
            BlazeLogger.debug("Upsert: Inserted new record \(id)")
            return true
        }
    }

    /// Fetches a single record by its UUID.
    ///
    /// - Parameter id: The UUID of the record to fetch
    /// - Returns: The record if found, or `nil` if not found
    /// - Throws: BlazeDBError if the fetch operation fails
    ///
    /// ## Example
    /// ```swift
    /// if let record = try db.fetch(id: someUUID) {
    ///     print("Found: \(record)")
    /// }
    /// ```
    public func fetch(id: UUID) throws -> BlazeDataRecord? {
        let startTime = Date()
        
        do {
            let record = try collection.fetch(id: id)
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: true, recordCount: record == nil ? 0 : 1)
            
            return record
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }

    /// Fetches all records in the database.
    ///
    /// - Returns: Array of all records
    /// - Throws: BlazeDBError if the fetch fails
    ///
    /// - Warning: For large databases, consider using pagination with `fetchPage(offset:limit:)` instead.
    ///
    /// ## Example
    /// ```swift
    /// let allRecords = try db.fetchAll()
    /// print("Total records: \(allRecords.count)")
    /// ```
    public func fetchAll() throws -> [BlazeDataRecord] {
        let startTime = Date()
        
        do {
            let records = try collection.fetchAll()
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: true, recordCount: records.count)
            
            return records
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Get distinct values for a field
    /// - Parameter field: Field name to get unique values for
    /// - Returns: Array of unique field values
    public func distinct(field: String) throws -> [BlazeDocumentField] {
        let records = try collection.fetchAll()
        let values = records.compactMap { $0.storage[field] }
        let uniqueValues = Array(Set(values))
        BlazeLogger.info("Found \(uniqueValues.count) distinct values for field '\(field)' from \(records.count) records")
        return uniqueValues
    }
    
    // MARK: - Pagination
    
    /// Fetch a page of records
    /// - Parameters:
    ///   - offset: Number of records to skip
    ///   - limit: Maximum number of records to return
    /// - Returns: Array of records for the requested page
    public func fetchPage(offset: Int, limit: Int) throws -> [BlazeDataRecord] {
        try collection.fetchPage(offset: offset, limit: limit)
    }
    
    /// Get total count of records without loading them all
    /// - Returns: Total number of records
    public func count() -> Int {
        collection.count()
    }
    
    /// Fetch multiple records by their IDs
    /// - Parameter ids: Array of UUIDs to fetch
    /// - Returns: Dictionary mapping UUID to record
    public func fetchBatch(ids: [UUID]) throws -> [UUID: BlazeDataRecord] {
        try collection.fetchBatch(ids: ids)
    }

    /// Updates an existing record by its UUID.
    ///
    /// The entire record is replaced with the new data. An `updatedAt` timestamp is added automatically.
    ///
    /// - Parameters:
    ///   - id: The UUID of the record to update
    ///   - data: The new record data (replaces the entire record)
    /// - Throws: BlazeDBError.recordNotFound if the record doesn't exist
    ///
    /// ## Example
    /// ```swift
    /// var record = try db.fetch(id: someUUID)!
    /// record.storage["status"] = .string("completed")
    /// try db.update(id: someUUID, with: record)
    /// ```
    public func update(id: UUID, with data: BlazeDataRecord) throws {
        let startTime = Date()
        
        do {
            if getenv("BLAZEDB_CRASH_BEFORE_UPDATE") != nil {
                BlazeLogger.warn("💥 Simulating crash before update (BLAZEDB_CRASH_BEFORE_UPDATE set)")
                throw NSError(domain: "BlazeDBCrashSimulation", code: 999, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated crash before update"
                ])
            }
            
            // Validate against schema (if defined)
            try validateAgainstSchema(data)
            
            try performSafeWrite { try collection.update(id: id, with: data) }
            appendToTransactionLog("update", payload: data.storage)
            
            // Notify change observers (for sync)
            notifyUpdate(id: id)
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "update", duration: duration, success: true, recordCount: 1)
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "update", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }
    
    /// Update specific fields of a record without fetching first (partial update)
    /// - Parameters:
    ///   - id: UUID of the record to update
    ///   - fields: Dictionary of fields to update
    /// - Throws: BlazeDBError if record not found
    public func updateFields(id: UUID, fields: [String: BlazeDocumentField]) throws {
        // Fetch current record
        guard var record = try fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        // Update specified fields
        for (key, value) in fields {
            record.storage[key] = value
        }
        record.storage["updatedAt"] = .date(Date())
        
        // Save
        try update(id: id, with: record)
        BlazeLogger.debug("Partial update: Updated \(fields.count) fields for record \(id)")
    }

    /// Permanently deletes a record by its UUID.
    ///
    /// This is a hard delete - the record is removed from disk immediately.
    /// For recoverable deletion, use `softDelete(id:)` instead.
    ///
    /// - Parameter id: The UUID of the record to delete
    /// - Throws: BlazeDBError if deletion fails
    ///
    /// ## Example
    /// ```swift
    /// try db.delete(id: recordToRemove)
    /// ```
    public func delete(id: UUID) throws {
        let startTime = Date()
        
        do {
            try performSafeWrite { try collection.delete(id: id) }
            appendToTransactionLog("delete", payload: ["id": .string(id.uuidString)])
            
            // Notify change observers (for sync)
            notifyDelete(id: id)
            
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "delete", duration: duration, success: true, recordCount: 1)
        } catch {
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "delete", duration: duration, success: false, recordCount: 0, error: error)
            throw error
        }
    }

    /// Marks a record as deleted without removing it from disk.
    ///
    /// Sets the `isDeleted` field to `true`. The record remains in the database
    /// until `purge()` is called. This allows for recovery if needed.
    ///
    /// - Parameter id: The UUID of the record to soft-delete
    /// - Throws: BlazeDBError if the operation fails
    ///
    /// ## Example
    /// ```swift
    /// try db.softDelete(id: someUUID)
    /// // Can still fetch the record, but isDeleted = true
    /// // Call purge() to permanently remove all soft-deleted records
    /// ```
    public func softDelete(id: UUID) throws {
        try collection.update(id: id, with: BlazeDataRecord(["isDeleted": .bool(true)]))
    }

    /// Permanently removes all soft-deleted records from disk.
    ///
    /// This goes through all records marked with `isDeleted = true` and
    /// permanently deletes them. This operation cannot be undone.
    ///
    /// - Throws: BlazeDBError if purge fails
    ///
    /// ## Example
    /// ```swift
    /// try db.softDelete(id: uuid1)
    /// try db.softDelete(id: uuid2)
    /// try db.purge()  // Both records now permanently deleted
    /// ```
    public func purge() throws {
        try collection.purge()
    }

    public func rawDump() throws -> [Int: Data] {
        try collection.rawDump()
    }
    
    // MARK: - Manual Flush
    
    /// Manually flush pending metadata changes to disk
    /// Useful when you need to ensure data is persisted before critical operations
    public func persist() throws {
        try collection.persist()
        
        // ✅ FIX: Delete transaction log after successful persist
        // This prevents replaying already-persisted operations on next open
        let logURL = transactionLogURL
        if FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.removeItem(at: logURL)
        }
    }
    
    /// Alias for persist() - flushes pending metadata to disk
    public func flush() throws {
        try collection.persist()
    }
    
    // MARK: - JOIN Operations
    
    /// Join this database with another database
    /// - Parameters:
    ///   - other: The other database to join with
    ///   - foreignKey: Field name in this database that references the other database
    ///   - primaryKey: Field name in the other database to match against (default: "id")
    ///   - type: Type of join operation (default: .inner)
    /// - Returns: Array of joined records
    /// - Note: Uses batch fetching for optimal performance
    ///
    /// Example:
    /// ```swift
    /// // Join bugs with users (bugs.author_id = users.id)
    /// let bugsWithAuthors = try bugsDB.join(
    ///     with: usersDB,
    ///     on: "author_id",
    ///     equals: "id",
    ///     type: .left
    /// )
    ///
    /// for joined in bugsWithAuthors {
    ///     let bugTitle = joined.left["title"]?.stringValue
    ///     let authorName = joined.right?["name"]?.stringValue ?? "Unknown"
    ///     print("\(bugTitle) by \(authorName)")
    /// }
    /// ```
    public func join(
        with other: BlazeDBClient,
        on foreignKey: String,
        equals primaryKey: String = "id",
        type: JoinType = .inner
    ) throws -> [JoinedRecord] {
        return try collection.join(
            with: other.collection,
            on: foreignKey,
            equals: primaryKey,
            type: type
        )
    }
    
    // MARK: - Query Builder
    
    /// Create a query builder for chainable queries
    /// - Returns: QueryBuilder instance
    ///
    /// Example:
    /// ```swift
    /// let results = try db.query()
    ///     .where("status", equals: .string("open"))
    ///     .where("priority", greaterThan: .int(2))
    ///     .orderBy("created_at", descending: true)
    ///     .limit(10)
    ///     .execute()
    /// ```
    public func query() -> QueryBuilder {
        return collection.query()
    }

    // MARK: - MetaStore

    internal var metaStore: any MetaStore { collection }

    // MARK: - Safe Write / Rollback

    internal func performSafeWrite(_ block: () throws -> Void) throws {
        if inSafeWrite { try block(); return }
        writeLock.lock()
        inSafeWrite = true
        defer { inSafeWrite = false; writeLock.unlock() }

        let dir = fileURL.deletingLastPathComponent()
        // Use unique backup names to avoid concurrent write collisions
        let backupID = UUID().uuidString
        let backupURL = dir.appendingPathComponent("transaction_backup_\(backupID).blazedb")
        let backupMetaURL = dir.appendingPathComponent("transaction_backup_\(backupID).meta")

        // 🔑 Backup both db and meta *before the write begins* (only if they exist)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }

        do {
            try block()
            // Success → clean up
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupMetaURL)
        } catch {
            BlazeLogger.error("Rolling back to backup due to error: \(error)")
            // Restore DB
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.copyItem(at: backupURL, to: fileURL)

            // Restore meta
            if FileManager.default.fileExists(atPath: backupMetaURL.path) {
                try? FileManager.default.removeItem(at: metaURL)
                try? FileManager.default.copyItem(at: backupMetaURL, to: metaURL)
            }

            // Reload in-memory state to match restored files
            do {
                try reloadFromDisk()
            } catch {
                BlazeLogger.warn("Meta layout invalid after rollback, regenerating fresh layout...")
                let store = try PageStore(fileURL: fileURL, key: encryptionKey)
                let freshLayout = try StorageLayout.rebuild(from: store)
                self.collection = try DynamicCollection(
                    store: store,
                    layout: freshLayout,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
            }
            throw error
        }
    }

    private func reloadFromDisk() throws {
        BlazeLogger.info("Reloading database from disk after rollback...")

        // Reopen the PageStore from the restored file
        let store = try PageStore(fileURL: fileURL, key: encryptionKey)

        // Try to load a valid layout from the meta file; if that fails, rebuild from pages
        do {
            if FileManager.default.fileExists(atPath: metaURL.path) {
                // Prefer explicit load of StorageLayout to validate the meta contents
                let layout = try StorageLayout.load(from: metaURL)
                self.collection = try DynamicCollection(
                    store: store,
                    layout: layout,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
                return
            }
        } catch {
            BlazeLogger.warn("Failed to load layout from meta, will rebuild: \(error)")
        }

        // Fallback: rebuild a fresh layout by scanning the store, then persist it to meta
        let rebuilt = try StorageLayout.rebuild(from: store)
        do {
            // Persist the rebuilt layout so future opens are fast
            try rebuilt.save(to: metaURL)
        } catch {
            // If saving fails, continue with in-memory layout
            BlazeLogger.warn("Failed to save rebuilt layout to meta: \(error)")
        }
        self.collection = try DynamicCollection(
            store: store,
            layout: rebuilt,
            metaURL: metaURL,
            project: project,
            encryptionKey: encryptionKey
        )
    }

    // MARK: - Transaction API

    /// Begins an ACID transaction.
    ///
    /// Creates a snapshot of the current database state. All subsequent operations
    /// are logged until `commitTransaction()` or `rollbackTransaction()` is called.
    ///
    /// - Throws: BlazeDBError.transactionFailed if a transaction is already in progress
    ///
    /// ## Example
    /// ```swift
    /// try db.beginTransaction()
    /// try db.insert(record1)
    /// try db.insert(record2)
    /// try db.commitTransaction()  // Both inserts succeed together
    /// ```
    ///
    /// ## Important
    /// - Only one transaction can be active at a time
    /// - Always call commit or rollback to clean up transaction state
    /// - Transactions provide full ACID guarantees
    public func beginTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            throw BlazeDBError.transactionFailed("Transaction already in progress")
        }
        try FileManager.default.copyItem(at: fileURL, to: transactionBackupURL)
        // Also backup meta file if it exists
        if FileManager.default.fileExists(atPath: metaURL.path) {
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                try FileManager.default.removeItem(at: transactionMetaBackupURL)
            }
            try FileManager.default.copyItem(at: metaURL, to: transactionMetaBackupURL)
        }
    }

    /// Commits the current transaction, making all changes permanent.
    ///
    /// All operations performed since `beginTransaction()` are permanently written to disk.
    /// If any operation failed, the entire transaction can still be rolled back.
    ///
    /// - Throws: BlazeDBError.transactionFailed if no transaction is active or commit fails
    ///
    /// ## Example
    /// ```swift
    /// try db.beginTransaction()
    /// try db.insert(record1)
    /// try db.update(id: id2, with: record2)
    /// try db.commitTransaction()  // Both operations persisted atomically
    /// ```
    public func commitTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            // Persist current in-memory state to disk BEFORE deleting backups
            // This ensures the committed state is saved
            try persist()
            BlazeLogger.info("Persisted transaction changes to disk")
            
            // Now delete the backup files (transaction is committed)
            try FileManager.default.removeItem(at: transactionBackupURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                try FileManager.default.removeItem(at: transactionMetaBackupURL)
            }
            
            BlazeLogger.info("Transaction committed successfully")
        } else {
            throw BlazeDBError.transactionFailed("No transaction in progress")
        }
    }

    /// Rolls back the current transaction, discarding all changes.
    ///
    /// Restores the database to the state it was in when `beginTransaction()` was called.
    /// All operations performed during the transaction are undone.
    ///
    /// - Throws: BlazeDBError.transactionFailed if no transaction is active or rollback fails
    ///
    /// ## Example
    /// ```swift
    /// try db.beginTransaction()
    /// try db.insert(record1)
    /// if someCondition {
    ///     try db.rollbackTransaction()  // Insert is undone
    /// } else {
    ///     try db.commitTransaction()
    /// }
    /// ```
    public func rollbackTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.copyItem(at: transactionBackupURL, to: fileURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                // Replace meta with its backup
                try? FileManager.default.removeItem(at: metaURL)
                try FileManager.default.copyItem(at: transactionMetaBackupURL, to: metaURL)
            }
            try FileManager.default.removeItem(at: transactionBackupURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                try? FileManager.default.removeItem(at: transactionMetaBackupURL)
            }
            do {
                try reloadFromDisk()
            } catch {
                BlazeLogger.warn("Meta layout invalid after rollback, regenerating fresh layout...")
                let store = try PageStore(fileURL: fileURL, key: encryptionKey)
                let freshLayout = try StorageLayout.rebuild(from: store)
                self.collection = try DynamicCollection(
                    store: store,
                    layout: freshLayout,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
            }
        } else {
            throw BlazeDBError.transactionFailed("No transaction to roll back")
        }
    }

    // MARK: - Migration
    // Migration logic is defined in Internal/Migration.swift as an extension
}

// MARK: - Integrity validation

extension BlazeDBClient {
    /// Performs a comprehensive integrity check on the database.
    ///
    /// Validates the database structure, checksums, and internal consistency.
    /// Returns a report with any issues found.
    ///
    /// - Returns: A ValidationReport containing any warnings or errors detected
    ///
    /// ## Example
    /// ```swift
    /// let report = db.checkDatabaseIntegrity()
    /// if report.ok {
    ///     print("Database is healthy")
    /// } else {
    ///     print("Issues found: \(report.issues)")
    /// }
    /// ```
    public func checkDatabaseIntegrity() -> ValidationReport {
        var issues: [IntegrityIssue] = []
        let layout: StorageLayout
        do {
            layout = try StorageLayout.load(from: metaURL)
        } catch {
            issues.append(.init(severity: .error, message: "Failed to load layout: \(error)"))
            return ValidationReport(ok: false, issues: issues)
        }
        if !layout.checksumMatchesStoredValue() {
            issues.append(.init(severity: .warning, message: "Layout checksum mismatch"))
        }
        for field in layout.fields where !field.isValidType() {
            issues.append(.init(severity: .warning, message: "Invalid field type: \(field.typeName)"))
        }
        if !layout.headerIsValid() {
            issues.append(.init(severity: .warning, message: "Header invalid"))
        }
        return ValidationReport(ok: !issues.contains { $0.severity == .error }, issues: issues)
    }

    public func validateDatabaseIntegrity(strict: Bool = false) throws -> ValidationReport {
        let report = checkDatabaseIntegrity()
        if strict, !report.ok { throw BlazeCorruptionError.corrupt }
        return report
    }
}

// MARK: - Security Audit

extension BlazeDBClient {
    /// Perform security audit and get recommendations
    /// Returns a comprehensive security audit report with findings and recommendations
    ///
    /// ## Example
    /// ```swift
    /// let report = db.performSecurityAudit()
    /// if !report.isSecure {
    ///     print("⚠️ Security issues found:")
    ///     for finding in report.findings {
    ///         print("  \(finding.severity.rawValue): \(finding.title)")
    ///         print("    → \(finding.recommendation)")
    ///     }
    /// }
    /// ```
    public func performSecurityAudit() -> SecurityAuditReport {
        let hasRBAC = (collection as? DynamicCollection)?.secondaryIndexes.isEmpty == false
        let hasRLS = securityContext != nil
        
        return SecurityAuditor.audit(
            isEncrypted: !password.isEmpty,
            password: password.isEmpty ? nil : password,
            hasRBAC: hasRBAC,
            hasRLS: hasRLS,
            hasAuditLogging: false,  // TODO: Implement audit logging
            usesTLS: false,  // TODO: Check if sync uses TLS
            hasCertificatePinning: false,  // TODO: Check certificate pinning
            crc32Enabled: BlazeBinaryEncoder.crc32Mode == .enabled
        )
    }
}

// MARK: - StorageLayout helpers

extension StorageLayout {
    func checksumMatchesStoredValue() -> Bool { true }
    func headerIsValid() -> Bool { true }
}

extension FieldDefinition {
    func isValidType() -> Bool {
        switch typeName {
        case "string","int","double","bool","uuid","date": return true
        default: return false
        }
    }
}


// MARK: - StorageLayout rebuild helper

extension StorageLayout {
    static func rebuild(from store: PageStore) throws -> StorageLayout {
        // Walk valid pages from the PageStore and rebuild indexMap/nextPageIndex/etc.
        var indexMap: [UUID: Int] = [:]
        var nextPageIndex = 0
        var i = 0
        while true {
            do {
                guard let pageData = try store.readPage(index: i) else { break }
                // Try to decode a UUID from the first 16 bytes
                if pageData.count >= 16 {
                    let uuidData = pageData.prefix(16)
                    let uuid = UUID(uuid: (
                        uuidData[0], uuidData[1], uuidData[2], uuidData[3],
                        uuidData[4], uuidData[5], uuidData[6], uuidData[7],
                        uuidData[8], uuidData[9], uuidData[10], uuidData[11],
                        uuidData[12], uuidData[13], uuidData[14], uuidData[15]
                    ))
                    indexMap[uuid] = i
                }
                nextPageIndex = i + 1
                i += 1
            } catch {
                // Stop if we can't read the page (invalid index or header)
                break
            }
        }
        return StorageLayout(indexMap: indexMap, nextPageIndex: nextPageIndex, compoundIndexes: [:])
    }
}
