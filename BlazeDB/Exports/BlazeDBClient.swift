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

public enum BlazeDBError: Error {
    case transactionFailed(String)
    case migrationFailed(String)
}

public enum BlazeCorruptionError: Error {
    case corrupt
}

// MARK: - BlazeDBClient

public final class BlazeDBClient {
    private var collection: DynamicCollection
    public let name: String
    private static var cachedKey: SymmetricKey?
    private let writeLock = NSLock()
    private var inSafeWrite = false

    // For reloads
    private let fileURL: URL
    private let metaURL: URL
    private let project: String
    private let encryptionKey: SymmetricKey

    // MARK: - Init
    public init(name: String, fileURL: URL, password: String, project: String = "Default") throws {
        self.name = name
        self.fileURL = fileURL
        self.metaURL = fileURL.deletingPathExtension().appendingPathExtension("meta")
        self.project = UserDefaults.standard.string(forKey: "activeProject") ?? project

        // 🔑 Derive or reuse key
        let key: SymmetricKey
        if let cached = BlazeDBClient.cachedKey {
            key = cached
            print("🔐 Using cached key")
        } else {
            key = try KeyManager.getKey(from: .password(password))
            BlazeDBClient.cachedKey = key
            print("🔐 Derived and cached key")
        }
        self.encryptionKey = key

        // Init store + collection
        let store = try PageStore(fileURL: fileURL)
        self.collection = try DynamicCollection(store: store,
                                                metaURL: metaURL,
                                                project: self.project,
                                                encryptionKey: key)

        try performMigrationIfNeeded()
        try replayTransactionLogIfNeeded()
    }

    public convenience init(name: String, fileURL: URL, password: String) throws {
        try self.init(name: name, fileURL: fileURL, password: password, project: "Default")
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
            print("⚠️ Skipping log, no active transaction in progress.")
            return
        }
        let entry: [String: Any] = [
            "operation": operation,
            "payload": payload.mapValues { $0.serializedString() },
            "timestamp": Date().iso8601
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: entry, options: [])
            if FileManager.default.fileExists(atPath: transactionLogURL.path) {
                let handle = try FileHandle(forWritingTo: transactionLogURL)
                handle.seekToEndOfFile()
                handle.write(data + "\n".data(using: .utf8)!)
                try handle.close()
            } else {
                try data.write(to: transactionLogURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                     ofItemAtPath: transactionLogURL.path)
            }
        } catch {
            print("🧨 Failed to log transaction:", error)
        }
    }

    public func replayTransactionLogIfNeeded() throws {
        let logURL = transactionLogURL
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        guard let data = try? Data(contentsOf: logURL),
              let contents = String(data: data, encoding: .utf8) else { return }

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
                print("⚠️ Skipping corrupted log entry: \(error)")
            }
        }
        try? FileManager.default.removeItem(at: logURL)
    }

    // MARK: - CRUD

    public func insert(_ data: BlazeDataRecord) throws -> UUID {
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

        try performSafeWrite { _ = try collection.insert(record) }
        appendToTransactionLog("insert", payload: record.storage)
        return id
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
    }

    public func fetch(id: UUID) throws -> BlazeDataRecord? {
        try collection.fetch(id: id)
    }

    public func fetchAll() throws -> [BlazeDataRecord] {
        try collection.fetchAll()
    }

    public func update(id: UUID, with data: BlazeDataRecord) throws {
        if getenv("BLAZEDB_CRASH_BEFORE_UPDATE") != nil {
            print("💥 Simulating crash before update (BLAZEDB_CRASH_BEFORE_UPDATE set)")
            throw NSError(domain: "BlazeDBCrashSimulation", code: 999, userInfo: [
                NSLocalizedDescriptionKey: "Simulated crash before update"
            ])
        }
        try performSafeWrite { try collection.update(id: id, with: data) }
        appendToTransactionLog("update", payload: data.storage)
    }

    public func delete(id: UUID) throws {
        try performSafeWrite { try collection.delete(id: id) }
        appendToTransactionLog("delete", payload: ["id": .string(id.uuidString)])
    }

    public func softDelete(id: UUID) throws {
        try collection.update(id: id, with: BlazeDataRecord(["isDeleted": .bool(true)]))
    }

    public func purge() throws {
        try collection.purge()
    }

    public func rawDump() throws -> [Int: Data] {
        try collection.rawDump()
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
        let backupURL = dir.appendingPathComponent("transaction_backup.blazedb")
        let backupMetaURL = dir.appendingPathComponent("transaction_backup.meta")

        // Clean old backups
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.removeItem(at: backupMetaURL)

        // 🔑 Backup both db and meta *before the write begins*
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }

        do {
            try block()
            // Success → clean up
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupMetaURL)
        } catch {
            print("🧨 Rolling back to backup due to error: \(error)")
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
                print("⚠️ Meta layout invalid after rollback, regenerating fresh layout...")
                let store = try PageStore(fileURL: fileURL)
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
        print("🔄 Reloading database from disk after rollback...")

        // Reopen the PageStore from the restored file
        let store = try PageStore(fileURL: fileURL)

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
            print("⚠️ Failed to load layout from meta, will rebuild: \(error)")
        }

        // Fallback: rebuild a fresh layout by scanning the store, then persist it to meta
        let rebuilt = try StorageLayout.rebuild(from: store)
        do {
            // Persist the rebuilt layout so future opens are fast
            try rebuilt.save(to: metaURL)
        } catch {
            // If saving fails, continue with in-memory layout
            print("⚠️ Failed to save rebuilt layout to meta: \(error)")
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

    public func commitTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            try FileManager.default.removeItem(at: transactionBackupURL)
            if FileManager.default.fileExists(atPath: transactionMetaBackupURL.path) {
                try FileManager.default.removeItem(at: transactionMetaBackupURL)
            }
            // 🔄 Reload in-memory state to match committed files
            do {
                try reloadFromDisk()
                print("🔄 Reloaded database from disk after commit.")
            } catch {
                print("⚠️ Failed to reload database after commit: \(error)")
                let store = try PageStore(fileURL: fileURL)
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
            throw BlazeDBError.transactionFailed("No transaction in progress")
        }
    }

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
                print("⚠️ Meta layout invalid after rollback, regenerating fresh layout...")
                let store = try PageStore(fileURL: fileURL)
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

    internal var expectedSchema: [String: BlazeDocumentField] = [
        "id": .string(""),
        "createdAt": .date(Date()),
        "title": .string(""),
        "status": .string("open")
    ]

    func performMigrationIfNeeded() throws {
        let currentVersion = 1
        let existingVersion = try loadSchemaVersion()
        if existingVersion < currentVersion {
            try backupBeforeMigration(version: existingVersion)
            try autoMigrateFields()
            try renameLegacyFields()
            try saveSchemaVersion(currentVersion)
        }
    }

    private func loadSchemaVersion() throws -> Int {
        let meta = try metaStore.fetchMeta()
        if case let .int(version)? = meta["schemaVersion"] { return version }
        return 0
    }

    private func saveSchemaVersion(_ version: Int) throws {
        try metaStore.updateMeta(["schemaVersion": .int(version)])
    }

    private func backupBeforeMigration(version: Int) throws {
        // Deterministic name to satisfy tests and ops scripts
        let dir = fileURL.deletingLastPathComponent()
        let backupURL = dir.appendingPathComponent("backup_v\(version).blazedb")
        let backupMetaURL = dir.appendingPathComponent("backup_v\(version).meta")
        // Overwrite if they already exist
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: backupMetaURL.path) {
            try FileManager.default.removeItem(at: backupMetaURL)
        }
        // Backup database file
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        // Backup meta file if it exists
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }
    }

    private func autoMigrateFields() throws {
        for var record in try fetchAll() {
            guard case let .string(idStr)? = record.storage["id"],
                  let id = UUID(uuidString: idStr) else { continue }
            var didMigrate = false
            for (k, v) in expectedSchema where record.storage[k] == nil {
                record.storage[k] = v; didMigrate = true
            }
            if didMigrate { try update(id: id, with: record) }
        }
    }

    private func renameLegacyFields() throws {
        for var record in try fetchAll() {
            guard case let .string(idStr)? = record.storage["id"],
                  let id = UUID(uuidString: idStr) else { continue }
            if let old = record.storage["summary"] {
                record.storage["title"] = old
                record.storage.removeValue(forKey: "summary")
                try update(id: id, with: record)
            }
        }
    }
}

// MARK: - Integrity validation

extension BlazeDBClient {
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
        return StorageLayout(indexMap: indexMap, nextPageIndex: nextPageIndex, secondaryIndexes: [:])
    }
}
