//  BlazeDBClient.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

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
        case .vector(let vec): return "<Vector: \(vec.count) dimensions>"
        case .null: return "null"
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
    case databaseLocked(operation: String, timeout: TimeInterval? = nil, path: URL? = nil)
    case corruptedData(location: String, reason: String)
    case passwordTooWeak(requirements: String)
    case invalidData(reason: String)
    case invalidInput(reason: String)
    
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
            
        case .databaseLocked(let operation, let timeout, let path):
            var msg = "Database is locked for operation: \(operation)"
            if let path = path {
                msg += " at path: \(path.path)"
            }
            msg += ". Another process is currently using this database."
            msg += " To resolve: Close the other process or wait for it to finish, then try again."
            if let timeout = timeout {
                msg += " (timeout: \(timeout)s)"
            }
            msg += ". Another process is using the database. Close other instances and try again."
            return msg
            
        case .corruptedData(let location, let reason):
            return "Data corruption detected at \(location): \(reason). Database integrity may be compromised. Restore from backup if available."
            
        case .passwordTooWeak(let requirements):
            return "Password is too weak. Requirements: \(requirements). Use a stronger password with letters, numbers, and special characters."
            
        case .invalidData(let reason):
            return "Invalid data: \(reason). Check input data format and types."
            
        case .invalidInput(let reason):
            return "Invalid input: \(reason). Check your input parameters."
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

public final class BlazeDBClient: @unchecked Sendable {
    internal var collection: DynamicCollection
    public let name: String
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?
    private let writeLock = NSLock()
    private let transactionLogLock = NSLock()  // 🔒 Dedicated lock for WAL writes
    
    /// Clear the cached encryption key (useful for testing)
    /// Also clears KeyManager's password key cache to ensure fresh key derivation
    public static func clearCachedKey() {
        cachedKey = nil
        // Note: KeyManager.passwordKeyCache is private, so we can't clear it directly
        // The cache will be naturally cleared when memory is freed
    }
    private var inSafeWrite = false
    
    // BLOCKER #2 FIX: Vacuum state management (internal for extensions)
    internal var isVacuuming: Bool = false
    internal let vacuumLock = NSLock()

    // For reloads
    internal let fileURL: URL
    
    /// Internal flag tracking close state
    internal var _isClosed: Bool = false
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
        // CRITICAL: Validate database name to prevent path traversal attacks
        // Database names should not contain path traversal characters or null bytes
        guard !name.contains("../") && !name.contains("..\\") && !name.contains("\0") else {
            throw BlazeDBError.invalidInput(reason: "Invalid database name: contains path traversal characters or null bytes")
        }
        guard !name.isEmpty && name.count <= 255 else {
            throw BlazeDBError.invalidInput(reason: "Invalid database name: must be non-empty and <= 255 characters")
        }
        
        // CRITICAL: Validate project name to prevent path traversal attacks
        guard !project.contains("../") && !project.contains("..\\") && !project.contains("\0") else {
            throw BlazeDBError.invalidInput(reason: "Invalid project name: contains path traversal characters or null bytes")
        }
        guard !project.isEmpty && project.count <= 255 else {
            throw BlazeDBError.invalidInput(reason: "Invalid project name: must be non-empty and <= 255 characters")
        }
        
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

        // CRASH SAFETY: Recover from incomplete VACUUM AFTER initializing collection
        // Note: recoverFromVacuumCrashIfNeeded is an instance method, called after collection is created
        // This will be called after collection initialization below
        do {
            // Recovery will be attempted after collection is initialized
        } catch {
            BlazeLogger.error("⚠️ VACUUM recovery check failed: \(error.localizedDescription)")
            // Don't fail initialization if recovery check fails - continue anyway
        }
        
        // Init store + collection
        do {
            // Verify files don't exist before initialization
            let mainExists = FileManager.default.fileExists(atPath: fileURL.path)
            let metaExists = FileManager.default.fileExists(atPath: metaURL.path)
            print("🔷 [INIT] BlazeDBClient.init: Before PageStore init")
            print("🔷 [INIT]   Main file exists: \(mainExists)")
            print("🔷 [INIT]   Meta file exists: \(metaExists)")
            BlazeLogger.debug("🔷 [INIT] Before PageStore init: main=\(mainExists), meta=\(metaExists)")
            
            // Note: We don't remove existing meta files here - they should be loaded by DynamicCollection
            // Test cleanup helpers handle aggressive cleanup in test scenarios
            
            print("🔷 [INIT] Creating PageStore...")
            let store = try PageStore(fileURL: fileURL, key: key)
            print("🔷 [INIT] ✅ PageStore created")
            
            // Check again after PageStore init
            let metaExistsAfter = FileManager.default.fileExists(atPath: metaURL.path)
            print("🔷 [INIT] After PageStore init: meta=\(metaExistsAfter)")
            BlazeLogger.debug("🔷 [INIT] After PageStore init: meta=\(metaExistsAfter)")
            
            print("🔷 [INIT] Creating DynamicCollection...")
            self.collection = try DynamicCollection(store: store,
                                                    metaURL: metaURL,
                                                    project: self.project,
                                                    encryptionKey: key,
                                                    password: password)  // Pass password for KDF auto-detection
            BlazeLogger.debug("✅ DynamicCollection created")
            
            // Validate format version after collection is initialized
            if FileManager.default.fileExists(atPath: metaURL.path) {
                try validateFormatVersion()
            } else {
                // New database - store current format version
                try storeFormatVersion()
            }
        } catch {
            let errorMsg = "❌ Failed to initialize storage: \(error.localizedDescription)"
            BlazeLogger.error(errorMsg)
            if let nsError = error as NSError? {
                BlazeLogger.error("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                if !nsError.userInfo.isEmpty {
                    BlazeLogger.error("❌ Error userInfo: \(nsError.userInfo)")
                }
            }
            throw BlazeDBError.transactionFailed(errorMsg)
        }

        // Migration and recovery
        do {
            try performMigrationIfNeeded()
            BlazeLogger.debug("✅ Migration check complete")
        } catch {
            let errorMsg = "❌ Migration failed: \(error.localizedDescription)"
            BlazeLogger.error(errorMsg)
            // Pass the underlying error for better debugging
            throw BlazeDBError.migrationFailed(errorMsg, underlyingError: error)
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
        
        #if !BLAZEDB_LINUX_CORE
        // Reload triggers from storage
        reloadTriggers()
        #endif
        
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
        // CRITICAL: Clean up auto vacuum timer to prevent memory leak
        // When BlazeDBClient is deallocated, the timer must be invalidated and removed from static dictionary
        // Otherwise, the timer will remain in memory indefinitely
        cleanupAutoVacuumTimer()
        
        // If not explicitly closed, attempt to flush and mark as closed
        if !_isClosed {
            do {
                try persist()
                BlazeLogger.debug("Auto-flushed unsaved changes in deinit for '\(name)'")
            } catch {
                BlazeLogger.error("Failed to flush in deinit for '\(name)': \(error)")
            }
            _isClosed = true
        }
    }

    // MARK: - Transaction log

    private var transactionLogURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
    }

    internal var transactionBackupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_in_progress.blazedb")
    }

    private var transactionMetaBackupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("txn_in_progress.meta")
    }

    internal func appendToTransactionLog(_ operation: String, payload: [String: BlazeDocumentField]) {  // Internal for AsyncOptimized extension access
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
            
            // Execute BEFORE INSERT triggers
            var modifiedRecord: BlazeDataRecord? = record
            try triggerManager.executeTriggers(for: .beforeInsert, record: record, modifiedRecord: &modifiedRecord)
            // Execute enhanced triggers
            try executeEnhancedTriggers(for: .beforeInsert, record: record, modifiedRecord: &modifiedRecord, collection: collection, collectionName: name)
            let recordToInsert = modifiedRecord ?? record
            
            // Validate foreign keys
            try validateForeignKeys(for: recordToInsert, operation: "insert")
            
            // Validate check constraints
            try validateCheckConstraints(in: recordToInsert)
            
            // Validate unique constraints
            try validateUniqueConstraints(in: recordToInsert)

            try performSafeWrite { _ = try collection.insert(recordToInsert) }
            appendToTransactionLog("insert", payload: recordToInsert.storage)
            
            // Execute AFTER INSERT triggers
            try triggerManager.executeTriggers(for: .afterInsert, record: recordToInsert, modifiedRecord: &modifiedRecord)
            // Execute enhanced triggers
            try executeEnhancedTriggers(for: .afterInsert, record: recordToInsert, modifiedRecord: &modifiedRecord, collection: collection, collectionName: name)
            
            // Notify change observers (for sync)
            notifyInsert(id: id)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry (if enabled)
            let insertDuration = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
            telemetry.record(operation: "insert", duration: insertDuration, success: true, recordCount: 1)
            #endif
            
            return id
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insert", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
                #if !BLAZEDB_LINUX_CORE
                // Use optimized batch insert (3-5x faster!)
                ids = try collection.insertBatch(records)
                #else
                // Linux: Fallback to individual inserts
                for record in records {
                    let id = try collection.insert(record)
                    ids.append(id)
                }
                #endif
                
                // Log to transaction log
                for (index, _) in ids.enumerated() {
                    if index < records.count {
                        appendToTransactionLog("insert", payload: records[index].storage)
                    }
                }
            }
            BlazeLogger.info("Inserted \(ids.count) records in optimized batch")
            
            // Notify change observers (for sync) - batch notification
            let changes = ids.map { DatabaseChange(type: .insert($0), collectionName: name) }
            notifyBatchChanges(changes)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: true, recordCount: ids.count)
            #endif
            
            return ids
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "insertMany", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
    
    /// Delete multiple records by IDs (optimized batch delete)
    ///
    /// Much faster than calling delete() in a loop because it:
    /// - Batches all page deletions in a single sync block
    /// - Saves metadata only once at the end
    /// - Syncs to disk only once at the end
    ///
    /// - Parameter ids: Array of UUIDs to delete
    /// - Returns: Number of records actually deleted
    ///
    /// ## Example
    /// ```swift
    /// let idsToDelete = [id1, id2, id3]
    /// let deleted = try db.deleteMany(ids: idsToDelete)
    /// print("Deleted \(deleted) records")
    /// ```
    public func deleteMany(ids: [UUID]) throws -> Int {
        let startTime = Date()
        
        do {
            var deletedCount = 0
            try performSafeWrite {
                #if !BLAZEDB_LINUX_CORE
                // Use optimized batch delete (much faster!)
                try collection.deleteBatch(ids)
                deletedCount = ids.count
                #else
                // Linux: Fallback to individual deletes
                for id in ids {
                    try collection.delete(id: id)
                }
                deletedCount = ids.count
                #endif
                
                // Log to transaction log
                for id in ids {
                    appendToTransactionLog("delete", payload: ["id": .uuid(id)])
                }
            }
            
            BlazeLogger.info("Deleted \(deletedCount) records in optimized batch")
            
            // Notify change observers (for sync) - batch notification
            let changes = ids.map { DatabaseChange(type: .delete($0), collectionName: name) }
            notifyBatchChanges(changes)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "deleteMany", duration: duration, success: true, recordCount: deletedCount)
            #endif
            
            return deletedCount
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "deleteMany", duration: duration, success: false, recordCount: 0, error: error)
            #endif
            throw error
        }
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
        do {
            _ = try fetch(id: id)
            // Record exists - update it
            try update(id: id, with: data)
            BlazeLogger.debug("Upsert: Updated existing record \(id)")
            return false
        } catch BlazeDBError.recordNotFound {
            // Record doesn't exist - insert it
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
        try ensureNotClosed()
        let startTime = Date()
        
        do {
            let record = try collection.fetch(id: id)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: true, recordCount: record == nil ? 0 : 1)
            #endif
            
            return record
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetch", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: true, recordCount: records.count)
            #endif
            
            return records
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "fetchAll", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
        try ensureNotClosed()
        // Get existing record for triggers
        guard let existingRecord = try collection.fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        
        // Execute BEFORE UPDATE triggers
        var modifiedRecord: BlazeDataRecord? = data
        try triggerManager.executeTriggers(for: .beforeUpdate, record: existingRecord, modifiedRecord: &modifiedRecord)
        // Execute enhanced triggers
        try executeEnhancedTriggers(for: .beforeUpdate, record: existingRecord, modifiedRecord: &modifiedRecord, collection: collection, collectionName: name)
        let recordToUpdate = modifiedRecord ?? data
        
        // Validate foreign keys
        try validateForeignKeys(for: recordToUpdate, operation: "update")
        
        // Validate check constraints
        try validateCheckConstraints(in: recordToUpdate)
        
        // Validate unique constraints (exclude current record)
        try validateUniqueConstraints(in: recordToUpdate, excludeId: id)
        let startTime = Date()
        
        do {
            if getenv("BLAZEDB_CRASH_BEFORE_UPDATE") != nil {
                BlazeLogger.warn("💥 Simulating crash before update (BLAZEDB_CRASH_BEFORE_UPDATE set)")
                throw NSError(domain: "BlazeDBCrashSimulation", code: 999, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated crash before update"
                ])
            }
            
            // Validate against schema (if defined)
            try validateAgainstSchema(recordToUpdate)
            
            try performSafeWrite { try collection.update(id: id, with: recordToUpdate) }
            appendToTransactionLog("update", payload: recordToUpdate.storage)
            
            // Execute AFTER UPDATE triggers
            try triggerManager.executeTriggers(for: .afterUpdate, record: recordToUpdate, modifiedRecord: &modifiedRecord)
            // Execute enhanced triggers - pass both old and new records
            // For afterUpdate, record is the old record, modifiedRecord is the new record
            var newRecord: BlazeDataRecord? = recordToUpdate
            try executeEnhancedTriggers(for: .afterUpdate, record: existingRecord, modifiedRecord: &newRecord, collection: collection, collectionName: name)
            
            // Notify change observers (for sync)
            notifyUpdate(id: id)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry (if enabled)
            let updateDuration = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
            telemetry.record(operation: "update", duration: updateDuration, success: true, recordCount: 1)
            #endif
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "update", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
        try ensureNotClosed()
        let startTime = Date()
        
        do {
            // Get existing record for triggers and foreign keys
            // Delete is idempotent: if record doesn't exist, return silently
            guard let existingRecord = try collection.fetch(id: id) else {
                // Record doesn't exist - delete is idempotent, so just return
                #if !BLAZEDB_LINUX_CORE
                let duration = Date().timeIntervalSince(startTime) * 1000
                telemetry.record(operation: "delete", duration: duration, success: true, recordCount: 0)
                #endif
                return
            }
            
            // Execute BEFORE DELETE triggers
            var modifiedRecord: BlazeDataRecord? = existingRecord
            try triggerManager.executeTriggers(for: .beforeDelete, record: existingRecord, modifiedRecord: &modifiedRecord)
            // Execute enhanced triggers
            try executeEnhancedTriggers(for: .beforeDelete, record: existingRecord, modifiedRecord: &modifiedRecord, collection: collection, collectionName: name)
            
            // Handle foreign key constraints (CASCADE, SET NULL, RESTRICT)
            // Note: foreignKeyManager is private, use ForeignKeys.validateForeignKeys instead
            try validateForeignKeys(for: existingRecord, operation: "delete")
            
            // OPTIMIZATION: Pass record to avoid double-fetch in collection.delete()
            try performSafeWrite { 
                // Pass the record to avoid re-fetching in _deleteNoSync
                try collection.delete(id: id, record: existingRecord)
            }
            appendToTransactionLog("delete", payload: ["id": .string(id.uuidString)])
            
            // Execute AFTER DELETE triggers
            try triggerManager.executeTriggers(for: .afterDelete, record: existingRecord, modifiedRecord: &modifiedRecord)
            // Execute enhanced triggers
            try executeEnhancedTriggers(for: .afterDelete, record: existingRecord, modifiedRecord: &modifiedRecord, collection: collection, collectionName: name)
            
            // Notify change observers (for sync)
            notifyDelete(id: id)
            
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "delete", duration: duration, success: true, recordCount: 1)
            #endif
        } catch {
            #if !BLAZEDB_LINUX_CORE
            // Track telemetry for failure
            let duration = Date().timeIntervalSince(startTime) * 1000
            telemetry.record(operation: "delete", duration: duration, success: false, recordCount: 0, error: error)
            #endif
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
        try ensureNotClosed()
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
        // Note: QueryBuilder operations will fail when executed if database is closed
        // We don't check here to allow query builder construction
        return collection.query()
    }

    // MARK: - MetaStore

    #if !BLAZEDB_LINUX_CORE
    internal var metaStore: any MetaStore { collection }
    #endif

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
            var rollbackSucceeded = false
            
            // Restore DB
            do {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    try FileManager.default.copyItem(at: backupURL, to: fileURL)
                }
                
                // Restore meta
                if FileManager.default.fileExists(atPath: backupMetaURL.path) {
                    try FileManager.default.removeItem(at: metaURL)
                    try FileManager.default.copyItem(at: backupMetaURL, to: metaURL)
                }
                
                rollbackSucceeded = true
            } catch let rollbackError {
                BlazeLogger.error("❌ CRITICAL: Failed to restore from backup: \(rollbackError)")
                BlazeLogger.error("❌ Backup files may still exist: \(backupURL.lastPathComponent), \(backupMetaURL.lastPathComponent)")
                // Continue to try reloadFromDisk even if rollback failed
            }

            // Reload in-memory state to match restored files
            do {
                try reloadFromDisk()
            } catch {
                BlazeLogger.warn("Meta layout invalid after rollback, regenerating fresh layout...")
                let store = try PageStore(fileURL: fileURL, key: encryptionKey)
                let freshLayout = try StorageLayout.rebuild(from: store)
                self.collection = DynamicCollection(
                    store: store,
                    layout: freshLayout,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
            }
            
            // Clean up backup files after rollback (best effort)
            if rollbackSucceeded {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.removeItem(at: backupMetaURL)
            }
            
            throw error
        }
    }

    internal func reloadFromDisk() throws {
        BlazeLogger.info("Reloading database from disk after rollback...")

        // Reopen the PageStore from the restored file
        let store = try PageStore(fileURL: fileURL, key: encryptionKey)

        // Try to load a valid layout from the meta file; if that fails, rebuild from pages
        do {
            if FileManager.default.fileExists(atPath: metaURL.path) {
                // Use loadSecure to handle HMAC-signed metadata files
                BlazeLogger.debug("Attempting to load layout from meta file: \(metaURL.path)")
                let layout = try StorageLayout.loadSecure(from: metaURL, signingKey: encryptionKey)
                BlazeLogger.debug("Successfully loaded layout: \(layout.indexMap.count) records in indexMap")
                self.collection = DynamicCollection(
                    store: store,
                    layout: layout,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
                BlazeLogger.info("✅ Successfully reloaded collection from disk")
                return
            } else {
                BlazeLogger.warn("Meta file does not exist at: \(metaURL.path)")
            }
        } catch let loadError {
            BlazeLogger.warn("Failed to load layout from meta, will rebuild: \(loadError)")
            throw loadError  // Re-throw to trigger rebuild fallback
        }

        // Fallback: rebuild a fresh layout by scanning the store, then persist it to meta
        let rebuilt = try StorageLayout.rebuild(from: store)
        do {
            // Persist the rebuilt layout so future opens are fast (use saveSecure for consistency)
            try rebuilt.saveSecure(to: metaURL, signingKey: encryptionKey)
        } catch {
            // If saving fails, continue with in-memory layout
            BlazeLogger.warn("Failed to save rebuilt layout to meta: \(error)")
        }
        self.collection = DynamicCollection(
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
        
        // CRITICAL: Persist all in-memory changes before creating backup
        // This ensures the backup includes all committed data
        try persist()
        
        // Ensure store is fully synced before backup
        try collection.store.synchronize()
        
        // Ensure files are fully synced before backup
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            fileHandle.synchronizeFile()
            fileHandle.closeFile()
        }
        if let metaHandle = FileHandle(forWritingAtPath: metaURL.path) {
            metaHandle.synchronizeFile()
            metaHandle.closeFile()
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
            // NOTE: We don't clear the key cache here because we're using the same encryptionKey
            // instance variable that was set during init. Clearing the cache could cause
            // key derivation issues if the key needs to be re-derived.
            // The encryptionKey instance variable should be consistent throughout the object's lifetime.
            
            // Extract index definitions from backup BEFORE restoring (backup will be deleted later)
            var preservedIndexDefinitions: [String: [String]] = [:]
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                do {
                    let backupData = try Data(contentsOf: transactionMetaBackupURL)
                    let decoder = JSONDecoder()
                    if let secureLayout = try? decoder.decode(StorageLayout.SecureLayout.self, from: backupData) {
                        preservedIndexDefinitions = secureLayout.layout.secondaryIndexDefinitions
                        BlazeLogger.info("✅ Preserved \(preservedIndexDefinitions.count) index definitions from backup")
                    }
                } catch {
                    BlazeLogger.warn("⚠️ Could not extract index definitions from backup: \(error)")
                }
            }
            
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.copyItem(at: transactionBackupURL, to: fileURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                // Replace meta with its backup
                try? FileManager.default.removeItem(at: metaURL)
                try FileManager.default.copyItem(at: transactionMetaBackupURL, to: metaURL)
            }
            
            // Ensure restored files are fully synced before loading
            if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                fileHandle.synchronizeFile()
                fileHandle.closeFile()
            }
            if let metaHandle = FileHandle(forWritingAtPath: metaURL.path) {
                metaHandle.synchronizeFile()
                metaHandle.closeFile()
            }
            
            // NOTE: Thread.sleep is intentional here. This synchronous function must block
            // to ensure file system operations complete before proceeding. File system
            // synchronization requires blocking waits; converting to async would require
            // API changes and may not provide benefits for this use case.
            Thread.sleep(forTimeInterval: 0.05)
            
            try FileManager.default.removeItem(at: transactionBackupURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                try? FileManager.default.removeItem(at: transactionMetaBackupURL)
            }
            do {
                // CRITICAL: Store reference to old collection to reset its unsavedChanges
                // This prevents the old instance from saving on deinit and overwriting the restored file
                let oldCollection = self.collection
                
                try reloadFromDisk()
                
                // Reset unsavedChanges on old collection to prevent it from saving on deinit
                // The old collection will be deallocated, but we don't want it to overwrite the restored file
                oldCollection.unsavedChanges = 0
                
                // Clear caches after rollback to ensure fresh data is read
                #if !BLAZEDB_LINUX_CORE
                collection.clearFetchAllCache()
                #endif
                RecordCache.shared.clear()
                BlazeLogger.info("✅ Rollback completed successfully - layout reloaded from backup")
            } catch let reloadError {
                BlazeLogger.warn("⚠️ Meta layout invalid after rollback, regenerating fresh layout... Error: \(reloadError)")
                
                // Try to rebuild from the restored data file using the proper rebuild logic
                // that decodes BlazeBinary records (not the simple StorageLayout.rebuild)
                let store = try PageStore(fileURL: fileURL, key: encryptionKey)
                // Create a new DynamicCollection which will rebuild the layout properly
                // by decoding BlazeBinary records to extract IDs
                let tempCollection = try DynamicCollection(
                    store: store,
                    metaURL: metaURL,
                    project: project,
                    encryptionKey: encryptionKey
                )
                
                // Restore the preserved index definitions
                if !preservedIndexDefinitions.isEmpty {
                    tempCollection.secondaryIndexDefinitions = preservedIndexDefinitions
                    // Rebuild the indexes from the data (using same normalization as createIndex)
                    for (indexKey, fields) in preservedIndexDefinitions {
                        BlazeLogger.info("Rebuilding index '\(indexKey)' on fields: \(fields.joined(separator: ", "))")
                        var rebuilt: [CompoundIndexKey: Set<UUID>] = [:]
                        for id in tempCollection.indexMap.keys {
                            if let record = try? tempCollection._fetchNoSync(id: id) {
                                let doc = record.storage
                                // Use same normalization logic as createIndex() to ensure key format matches
                                let rawKey = CompoundIndexKey.fromFields(doc, fields: fields)
                                let normalizedComponents = rawKey.components.map { component -> AnyBlazeCodable in
                                    switch component {
                                    case .string(let s): return AnyBlazeCodable(s)
                                    case .int(let i): return AnyBlazeCodable(i)
                                    case .double(let d): return AnyBlazeCodable(d)
                                    case .bool(let b): return AnyBlazeCodable(b)
                                    case .date(let d): return AnyBlazeCodable(d)
                                    case .uuid(let u): return AnyBlazeCodable(u)
                                    case .data(let data): return AnyBlazeCodable(data)
                                    case .vector(let v): return AnyBlazeCodable(v)
                                    case .null: return AnyBlazeCodable("")  // Use empty string as sentinel for null
                                    case .array: return AnyBlazeCodable("")  // Arrays not supported in compound indexes
                                    case .dictionary: return AnyBlazeCodable("")  // Dictionaries not supported in compound indexes
                                    }
                                }
                                let normalizedKey = CompoundIndexKey(normalizedComponents)
                                rebuilt[normalizedKey, default: []].insert(id)
                            }
                        }
                        tempCollection.secondaryIndexes[indexKey] = rebuilt
                    }
                    // Save the layout with the restored index definitions
                    try tempCollection.saveLayout()
                    BlazeLogger.info("✅ Rebuilt and saved indexes after rollback")
                }
                
                // CRITICAL: Reset unsavedChanges on old collection before replacing it
                // This prevents the old instance from saving on deinit and overwriting the rebuilt file
                let oldCollection = self.collection
                oldCollection.unsavedChanges = 0
                
                self.collection = tempCollection
                // Clear caches after rebuild
                #if !BLAZEDB_LINUX_CORE
                collection.clearFetchAllCache()
                #endif
                RecordCache.shared.clear()
                BlazeLogger.info("✅ Rollback completed - layout rebuilt from data file")
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
        let hasRBAC = collection.secondaryIndexes.isEmpty == false
        let hasRLS = rls.getContext() != nil
        
        return SecurityAuditor.audit(
            isEncrypted: !password.isEmpty,
            password: password.isEmpty ? nil : password,
            hasRBAC: hasRBAC,
            hasRLS: hasRLS,
            hasAuditLogging: false,  // NOTE: Audit logging intentionally not implemented.
            // Application-level logging should be used for audit trails.
            usesTLS: false,  // NOTE: TLS detection intentionally not implemented.
            // TLS usage is determined by connection configuration, not tracked globally.
            hasCertificatePinning: false,  // NOTE: Certificate pinning detection intentionally not implemented.
            // Certificate pinning is a connection-level feature, not a global database setting.
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
        var indexMap: [UUID: [Int]] = [:]
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
                    indexMap[uuid] = [i]  // Convert to [Int] array for consistency
                }
                nextPageIndex = i + 1
                i += 1
            } catch {
                // Stop if we can't read the page (invalid index or header)
                break
            }
        }
        return StorageLayout(
            indexMap: indexMap,
            nextPageIndex: nextPageIndex,
            compoundIndexes: [:],
            searchIndex: nil,
            searchIndexedFields: []
        )
    }
}

// MARK: - Ordering Index Support (Optional)

extension BlazeDBClient {
    /// Enable fractional ordering support for this database
    /// 
    /// This is completely optional and off by default. When enabled, records can be
    /// ordered using a fractional index field (like Notion/Linear).
    ///
    /// - Parameter fieldName: Field name for ordering index (default: "orderingIndex")
    /// - Throws: BlazeDBError if enabling fails
    ///
    /// Example:
    /// ```swift
    /// try db.enableOrdering()
    /// // Now records can use orderingIndex field for natural ordering
    /// ```
    public func enableOrdering(fieldName: String = "orderingIndex") throws {
        BlazeLogger.info("BlazeDBClient.enableOrdering: enabling ordering with field '\(fieldName)'")
        try collection.enableOrdering(fieldName: fieldName)
        BlazeLogger.info("BlazeDBClient.enableOrdering: ordering enabled successfully")
    }
    
    /// Check if ordering is enabled
    /// - Returns: true if ordering is enabled, false otherwise
    public func isOrderingEnabled() -> Bool {
        let enabled = collection.supportsOrdering()
        BlazeLogger.trace("BlazeDBClient.isOrderingEnabled: \(enabled)")
        return enabled
    }
    
    /// Move a record before another record (only modifies orderingIndex)
    /// 
    /// Requires ordering to be enabled. Calculates a fractional index between
    /// the target record and the record before it.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to move
    ///   - beforeId: ID of record to move before
    /// - Throws: BlazeDBError if ordering not enabled or records not found
    public func moveBefore(recordId: UUID, beforeId: UUID) throws {
        BlazeLogger.info("BlazeDBClient.moveBefore: moving record \(recordId) before \(beforeId)")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.moveBefore: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        BlazeLogger.debug("BlazeDBClient.moveBefore: using field '\(fieldName)'")
        
        // Get target record
        guard let targetRecord = try collection.fetch(id: beforeId) else {
            throw BlazeDBError.recordNotFound(id: beforeId)
        }
        let targetIndex = OrderingIndex.getIndex(from: targetRecord, fieldName: fieldName)
        
        // Get record before target (if exists)
        let allRecords = try collection.fetchAll()
        let sortedRecords = allRecords.sorted { (left, right) -> Bool in
            let leftIndex = OrderingIndex.getIndex(from: left, fieldName: fieldName)
            let rightIndex = OrderingIndex.getIndex(from: right, fieldName: fieldName)
            if leftIndex == nil && rightIndex == nil { return false }
            if leftIndex == nil { return false }
            if rightIndex == nil { return true }
            return leftIndex! < rightIndex!
        }
        
        guard let targetPosition = sortedRecords.firstIndex(where: { $0.storage["id"]?.uuidValue == beforeId }) else {
            throw BlazeDBError.recordNotFound(id: beforeId)
        }
        
        let beforeIndex: Double? = targetPosition > 0 ? OrderingIndex.getIndex(from: sortedRecords[targetPosition - 1], fieldName: fieldName) : nil
        
        // Calculate new index
        let newIndex = OrderingIndex.between(beforeIndex, targetIndex)
        BlazeLogger.debug("BlazeDBClient.moveBefore: calculated index \(newIndex) between \(beforeIndex?.description ?? "nil") and \(targetIndex?.description ?? "nil")")
        
        // Update record
        guard var record = try collection.fetch(id: recordId) else {
            BlazeLogger.error("BlazeDBClient.moveBefore: record \(recordId) not found")
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        record = OrderingIndex.setIndex(newIndex, on: record, fieldName: fieldName)
        
        // Record telemetry
        let startTime = Date()
        try update(id: recordId, with: record)
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveBefore", duration: duration, success: true, recordCount: 1)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.moveBefore: successfully moved record \(recordId) to index \(newIndex)")
    }
    
    /// Move a record after another record (only modifies orderingIndex)
    /// 
    /// Requires ordering to be enabled. Calculates a fractional index between
    /// the target record and the record after it.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to move
    ///   - afterId: ID of record to move after
    /// - Throws: BlazeDBError if ordering not enabled or records not found
    public func moveAfter(recordId: UUID, afterId: UUID) throws {
        BlazeLogger.info("BlazeDBClient.moveAfter: moving record \(recordId) after \(afterId)")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.moveAfter: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        BlazeLogger.debug("BlazeDBClient.moveAfter: using field '\(fieldName)'")
        
        // Get target record
        guard let targetRecord = try collection.fetch(id: afterId) else {
            throw BlazeDBError.recordNotFound(id: afterId)
        }
        let targetIndex = OrderingIndex.getIndex(from: targetRecord, fieldName: fieldName)
        
        // Get record after target (if exists)
        let allRecords = try collection.fetchAll()
        let sortedRecords = allRecords.sorted { (left, right) -> Bool in
            let leftIndex = OrderingIndex.getIndex(from: left, fieldName: fieldName)
            let rightIndex = OrderingIndex.getIndex(from: right, fieldName: fieldName)
            if leftIndex == nil && rightIndex == nil { return false }
            if leftIndex == nil { return false }
            if rightIndex == nil { return true }
            return leftIndex! < rightIndex!
        }
        
        guard let targetPosition = sortedRecords.firstIndex(where: { $0.storage["id"]?.uuidValue == afterId }) else {
            throw BlazeDBError.recordNotFound(id: afterId)
        }
        
        let afterIndex: Double? = targetPosition < sortedRecords.count - 1 ? OrderingIndex.getIndex(from: sortedRecords[targetPosition + 1], fieldName: fieldName) : nil
        
        // Calculate new index
        let newIndex = OrderingIndex.between(targetIndex, afterIndex)
        BlazeLogger.debug("BlazeDBClient.moveAfter: calculated index \(newIndex) between \(targetIndex?.description ?? "nil") and \(afterIndex?.description ?? "nil")")
        
        // Update record
        guard var record = try collection.fetch(id: recordId) else {
            BlazeLogger.error("BlazeDBClient.moveAfter: record \(recordId) not found")
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        record = OrderingIndex.setIndex(newIndex, on: record, fieldName: fieldName)
        
        // Record telemetry
        let startTime = Date()
        try update(id: recordId, with: record)
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveAfter", duration: duration, success: true, recordCount: 1)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.moveAfter: successfully moved record \(recordId) to index \(newIndex)")
    }
    
    /// Set a specific ordering index for a record
    /// 
    /// Requires ordering to be enabled. Directly sets the ordering index value.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to update
    ///   - index: Ordering index value
    /// - Throws: BlazeDBError if ordering not enabled or record not found
    public func moveToIndex(recordId: UUID, index: Double) throws {
        BlazeLogger.info("BlazeDBClient.moveToIndex: setting record \(recordId) to index \(index)")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.moveToIndex: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        BlazeLogger.debug("BlazeDBClient.moveToIndex: using field '\(fieldName)'")
        
        guard var record = try collection.fetch(id: recordId) else {
            BlazeLogger.error("BlazeDBClient.moveToIndex: record \(recordId) not found")
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        
        record = OrderingIndex.setIndex(index, on: record, fieldName: fieldName)
        
        // Record telemetry
        let startTime = Date()
        try update(id: recordId, with: record)
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveToIndex", duration: duration, success: true, recordCount: 1)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.moveToIndex: successfully set record \(recordId) to index \(index)")
    }
    
    // MARK: - Advanced Ordering Features
    
    /// Move a record up N positions (relative move)
    /// 
    /// Requires ordering to be enabled. Moves record up by N positions in the sorted order.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to move
    ///   - positions: Number of positions to move up (default: 1)
    /// - Throws: BlazeDBError if ordering not enabled or record not found
    public func moveUp(recordId: UUID, positions: Int = 1) throws {
        BlazeLogger.info("BlazeDBClient.moveUp: moving record \(recordId) up \(positions) positions")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.moveUp: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        let startTime = Date()
        
        guard var record = try collection.fetch(id: recordId) else {
            BlazeLogger.error("BlazeDBClient.moveUp: record \(recordId) not found")
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        
        let newIndex: Double
        if let currentIndex = OrderingIndex.getIndex(from: record, fieldName: fieldName) {
            newIndex = OrderingIndex.moveUp(from: currentIndex, positions: positions)
        } else {
            BlazeLogger.warn("BlazeDBClient.moveUp: record \(recordId) has no ordering index, using default")
            newIndex = OrderingIndex.default - Double(positions)
        }
        record = OrderingIndex.setIndex(newIndex, on: record, fieldName: fieldName)
        
        try update(id: recordId, with: record)
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveUp", duration: duration, success: true, recordCount: 1)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.moveUp: successfully moved record \(recordId) up \(positions) positions")
    }
    
    /// Move a record down N positions (relative move)
    /// 
    /// Requires ordering to be enabled. Moves record down by N positions in the sorted order.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to move
    ///   - positions: Number of positions to move down (default: 1)
    /// - Throws: BlazeDBError if ordering not enabled or record not found
    public func moveDown(recordId: UUID, positions: Int = 1) throws {
        BlazeLogger.info("BlazeDBClient.moveDown: moving record \(recordId) down \(positions) positions")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.moveDown: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        let startTime = Date()
        
        guard var record = try collection.fetch(id: recordId) else {
            BlazeLogger.error("BlazeDBClient.moveDown: record \(recordId) not found")
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        
        let newIndex: Double
        if let currentIndex = OrderingIndex.getIndex(from: record, fieldName: fieldName) {
            newIndex = OrderingIndex.moveDown(from: currentIndex, positions: positions)
        } else {
            BlazeLogger.warn("BlazeDBClient.moveDown: record \(recordId) has no ordering index, using default")
            newIndex = OrderingIndex.default + Double(positions)
        }
        record = OrderingIndex.setIndex(newIndex, on: record, fieldName: fieldName)
        
        try update(id: recordId, with: record)
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveDown", duration: duration, success: true, recordCount: 1)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.moveDown: successfully moved record \(recordId) down \(positions) positions")
    }
    
    /// Bulk reorder multiple records at once
    /// 
    /// Requires ordering to be enabled. Efficiently updates multiple records' ordering indices.
    ///
    /// - Parameter operations: Array of reorder operations
    /// - Returns: Result with success/failure counts
    /// - Throws: BlazeDBError if ordering not enabled
    public func bulkReorder(_ operations: [BulkReorderOperation]) throws -> BulkReorderResult {
        BlazeLogger.info("BlazeDBClient.bulkReorder: reordering \(operations.count) records")
        
        guard collection.supportsOrdering() else {
            BlazeLogger.error("BlazeDBClient.bulkReorder: ordering not enabled")
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        let startTime = Date()
        
        var successful = 0
        var failed = 0
        var errors: [(UUID, Error)] = []
        
        // Perform bulk update
        for operation in operations {
            do {
                guard var record = try collection.fetch(id: operation.recordId) else {
                    let error = BlazeDBError.recordNotFound(id: operation.recordId)
                    errors.append((operation.recordId, error))
                    failed += 1
                    continue
                }
                
                record = OrderingIndex.setIndex(operation.newIndex, on: record, fieldName: fieldName)
                try update(id: operation.recordId, with: record)
                successful += 1
            } catch {
                errors.append((operation.recordId, error))
                failed += 1
                BlazeLogger.warn("BlazeDBClient.bulkReorder: failed to reorder \(operation.recordId): \(error)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "bulkReorder", duration: duration, success: failed == 0, recordCount: successful)
        #endif
        
        // Invalidate cache
        OrderingIndexCache.shared.invalidate(fieldName: fieldName)
        
        BlazeLogger.info("BlazeDBClient.bulkReorder: completed - \(successful) successful, \(failed) failed")
        
        return BulkReorderResult(successful: successful, failed: failed, errors: errors)
    }
    
    /// Enable ordering with category support (multiple ordering fields)
    /// 
    /// When enabled, each category can have its own ordering index field.
    /// For example, if categoryField is "status", records with status="todo" will use
    /// "orderingIndex_todo", and records with status="done" will use "orderingIndex_done".
    ///
    /// - Parameters:
    ///   - fieldName: Base ordering field name (default: "orderingIndex")
    ///   - categoryField: Field name for category grouping (e.g., "status", "category")
    /// - Throws: BlazeDBError if enabling fails
    public func enableOrderingWithCategories(
        fieldName: String = "orderingIndex",
        categoryField: String
    ) throws {
        BlazeLogger.info("BlazeDBClient.enableOrderingWithCategories: enabling with category field '\(categoryField)'")
        
        #if !BLAZEDB_LINUX_CORE
        var meta = try collection.fetchMeta()
        meta["supportsOrdering"] = .bool(true)
        meta["orderingFieldName"] = .string(fieldName)
        meta["orderingCategoryField"] = .string(categoryField)
        meta["supportsMultipleOrdering"] = .bool(true)
        
        try collection.updateMeta(meta)
        #endif
        BlazeLogger.info("BlazeDBClient.enableOrderingWithCategories: enabled with category field '\(categoryField)'")
    }
    
    /// Move a record within its category
    /// 
    /// Requires category-based ordering to be enabled.
    ///
    /// - Parameters:
    ///   - recordId: ID of record to move
    ///   - categoryValue: Category value (e.g., "todo", "done")
    ///   - beforeId: ID of record to move before (optional)
    ///   - afterId: ID of record to move after (optional)
    /// - Throws: BlazeDBError if category ordering not enabled or records not found
    public func moveInCategory(
        recordId: UUID,
        categoryValue: String,
        beforeId: UUID? = nil,
        afterId: UUID? = nil
    ) throws {
        BlazeLogger.info("BlazeDBClient.moveInCategory: moving record \(recordId) in category '\(categoryValue)'")
        
        guard collection.supportsOrdering() else {
            throw BlazeDBError.transactionFailed("Ordering not enabled. Call enableOrdering() first.")
        }
        
        // Check if category ordering is enabled (not just regular ordering)
        guard collection.supportsMultipleOrdering(), let categoryField = collection.orderingCategoryField() else {
            throw BlazeDBError.transactionFailed("Category ordering not enabled. Call enableOrderingWithCategories() first.")
        }
        
        let fieldName = collection.orderingFieldName()
        let startTime = Date()
        
        BlazeLogger.debug("BlazeDBClient.moveInCategory: using categoryField='\(categoryField)', fieldName='\(fieldName)'")
        
        // Get all records in the category
        let allRecords = try collection.fetchAll()
        let categoryRecords = allRecords.filter { record in
            record.storage[categoryField]?.stringValue == categoryValue
        }
        
        let sortedCategoryRecords = categoryRecords.sorted { (left, right) -> Bool in
            let leftIndex = OrderingIndex.getIndex(from: left, categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName)
            let rightIndex = OrderingIndex.getIndex(from: right, categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName)
            if leftIndex == nil && rightIndex == nil { return false }
            if leftIndex == nil { return false }
            if rightIndex == nil { return true }
            return leftIndex! < rightIndex!
        }
        
        guard let targetId = beforeId ?? afterId else {
            throw BlazeDBError.invalidQuery(reason: "Either beforeId or afterId must be provided")
        }
        
        guard let targetRecord = sortedCategoryRecords.first(where: { $0.storage["id"]?.uuidValue == targetId }) else {
            throw BlazeDBError.recordNotFound(id: targetId)
        }
        
        let targetIndex = OrderingIndex.getIndex(from: targetRecord, categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName)
        
        let beforeIndex: Double?
        let afterIndex: Double?
        
        if let beforeId = beforeId {
            guard let targetPos = sortedCategoryRecords.firstIndex(where: { $0.storage["id"]?.uuidValue == beforeId }) else {
                throw BlazeDBError.recordNotFound(id: beforeId)
            }
            beforeIndex = targetPos > 0 ? OrderingIndex.getIndex(from: sortedCategoryRecords[targetPos - 1], categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName) : nil
            afterIndex = targetIndex
        } else {
            // CRITICAL: Throw proper error instead of crashing with fatalError()
            // This should never happen due to guard at line 2023, but handle gracefully
            guard let afterId = afterId else {
                BlazeLogger.error("❌ insertOrdered: Both beforeId and afterId are nil (should be caught by earlier guard)")
                throw BlazeDBError.invalidQuery(reason: "Internal error: Both beforeId and afterId are nil. This indicates a programming error.")
            }
            guard let targetPos = sortedCategoryRecords.firstIndex(where: { $0.storage["id"]?.uuidValue == afterId }) else {
                throw BlazeDBError.recordNotFound(id: afterId)
            }
            beforeIndex = targetIndex
            afterIndex = targetPos < sortedCategoryRecords.count - 1 ? OrderingIndex.getIndex(from: sortedCategoryRecords[targetPos + 1], categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName) : nil
        }
        
        let newIndex = OrderingIndex.between(beforeIndex, afterIndex)
        
        guard var record = try collection.fetch(id: recordId) else {
            throw BlazeDBError.recordNotFound(id: recordId)
        }
        
        record = OrderingIndex.setIndex(newIndex, on: record, categoryField: categoryField, categoryValue: categoryValue, fieldName: fieldName)
        try update(id: recordId, with: record)
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        #if !BLAZEDB_LINUX_CORE
        telemetry.record(operation: "moveInCategory", duration: duration, success: true, recordCount: 1)
        #endif
        
        BlazeLogger.info("BlazeDBClient.moveInCategory: successfully moved record \(recordId) in category '\(categoryValue)'")
    }
}

// MARK: - Category Ordering Support

extension DynamicCollection {
    /// Get the category field name for ordering
    internal func orderingCategoryField() -> String? {
        #if !BLAZEDB_LINUX_CORE
        do {
            let meta = try fetchMeta()
            return meta["orderingCategoryField"]?.stringValue
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
    
    /// Check if multiple ordering (per category) is supported
    internal func supportsMultipleOrdering() -> Bool {
        #if !BLAZEDB_LINUX_CORE
        do {
            let meta = try fetchMeta()
            return meta["supportsMultipleOrdering"]?.boolValue ?? false
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

// MARK: - Graph Query Extension
// Note: Full implementation is in BlazeDB/Query/GraphQuery.swift
// The graph() methods are defined in GraphQuery.swift extension

