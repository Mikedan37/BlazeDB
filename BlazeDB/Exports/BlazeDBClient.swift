//  BlazeDBClient.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit

extension BlazeDocumentField {
    func serializedString() -> String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return String(v)
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .uuid(let v): return v.uuidString
        case .array(let arr): return "[\(arr.map { $0.serializedString() }.joined(separator: ", "))]"
        case .dictionary(let dict): return "{\(dict.map { "\($0): \($1.serializedString())" }.joined(separator: ", "))}"
        }
    }
}


extension Date {
    var iso8601: String {
        return ISO8601DateFormatter().string(from: self)
    }
}

/// A convenience wrapper for working with a dynamic BlazeDB collection.
public final class BlazeDBClient {
    private let collection: DynamicCollection
    public let name: String
    private static var cachedKey: SymmetricKey?

    public init(name: String, fileURL: URL, password: String) throws {
        self.name = name
        let key: SymmetricKey
        if let cached = BlazeDBClient.cachedKey {
            key = cached
            print("🔐 Using cached key")
        } else {
            key = try KeyManager.getKey(from: .password(password))
            BlazeDBClient.cachedKey = key
            print("🔐 Derived and cached key")
        }
        print("🔑 Key SHA256: \(key.withUnsafeBytes { Data($0).sha256().map { String(format: "%02x", $0) }.joined() })")
        let metaURL = fileURL.deletingPathExtension().appendingPathExtension("meta")
        print("📂 DB Path:", fileURL.path)
        print("📂 Meta Path:", metaURL.path)
        let store = try PageStore(fileURL: fileURL)
        print("📄 Initialized PageStore")
        let activeProject = UserDefaults.standard.string(forKey: "activeProject") ?? "Default"
        print("📁 Active Project:", activeProject)
        self.collection = try DynamicCollection(store: store, metaURL: metaURL, project: activeProject, encryptionKey: key)
        try self.performMigrationIfNeeded()
        print("📚 DynamicCollection ready")
        try replayTransactionLogIfNeeded()
    }

    private var transactionLogURL: URL {
        return fileURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
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
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: transactionLogURL.path)
            }
        } catch {
            print("🧨 Failed to log transaction:", error)
        }
    }

    public func replayTransactionLogIfNeeded() throws {
        let logURL = transactionLogURL
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }

        let data = try Data(contentsOf: logURL)
        guard let contents = String(data: data, encoding: .utf8) else { return }

        let entries = contents.split(separator: "\n").map { String($0) }
        for entryString in entries {
            guard let entryData = entryString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: entryData) as? [String: Any],
                  let operation = json["operation"] as? String,
                  let payload = json["payload"] as? [String: String] else { continue }

            let restored = payload.mapValues { BlazeDocumentField.string($0) } // Simplified decoding
            switch operation {
            case "insert":
                _ = try? insert(BlazeDataRecord(restored))
            case "update":
                if let idString = restored["id"], case let .string(idStr) = idString,
                   let id = UUID(uuidString: idStr) {
                    try? update(id: id, with: BlazeDataRecord(restored))
                }
            case "delete":
                if let idString = restored["id"], case let .string(idStr) = idString,
                   let id = UUID(uuidString: idStr) {
                    try? delete(id: id)
                }
            default:
                continue
            }
        }

        try FileManager.default.removeItem(at: logURL)
        print("🔁 Replayed and cleared transaction log")
    }

    public func insert(_ data: BlazeDataRecord) throws -> UUID {
        var record = data
        let id: UUID
        if let idField = record.storage["id"],
           case let .string(idStr) = idField,
           let parsed = UUID(uuidString: idStr) {
            id = parsed
        } else {
            id = UUID()
            record.storage["id"] = .string(id.uuidString)
        }
        try performSafeWrite {
            try collection.insert(record)
        }
        print("➕ Inserted record with ID:", id)
        appendToTransactionLog("insert", payload: record.storage)
        return id
    }

    public func fetch(id: UUID) throws -> BlazeDataRecord? {
        print("🔍 Fetching record with ID:", id)
        guard let fetched = try collection.fetch(id: id) else { return nil }
        return fetched
    }

    public func fetchAll() throws -> [BlazeDataRecord] {
        let all = try collection.fetchAll()
        print("📦 Loaded", all.count, "records from DB")
        return all
    }

    public func update(id: UUID, with data: BlazeDataRecord) throws {
        try performSafeWrite {
            try collection.update(id: id, with: data)
        }
        appendToTransactionLog("update", payload: data.storage)
    }

    public func delete(id: UUID) throws {
        try performSafeWrite {
            try collection.delete(id: id)
        }
        print("❌ Deleted record with ID:", id)
        appendToTransactionLog("delete", payload: ["id": .string(id.uuidString)])
    }

    public func softDelete(id: UUID) throws {
        try collection.update(id: id, with: BlazeDataRecord(["isDeleted": .bool(true)]))
        print("🧼 Soft-deleted record with ID:", id)
    }

    public func purge() throws {
        print("🧹 Purging soft-deleted records")
        try collection.purge()
    }

    public func rawDump() throws -> [Int: Data] {
        let dump = try collection.rawDump()
        print("🧾 Dumped", dump.count, "raw pages")
        return dump
    }
    // MARK: - Internal computed properties
    internal var metaStore: any MetaStore {
        return collection
    }

    internal var fileURL: URL {
        return collection.fileURL
    }

    /// MARK: - Experimental Transaction API
    ///
    /// Usage:
    /// 1. Call `beginTransaction()` to snapshot the DB.
    /// 2. Do your inserts/updates/deletes.
    /// 3. Call `commitTransaction()` to delete snapshot.
    /// If crash occurs before commit, DB will rollback to snapshot.
    /// All writes inside a transaction are journaled to `txn_log.json`.

    private var transactionBackupURL: URL {
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("txn_in_progress.blazedb")
    }

    public func beginTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            throw NSError(domain: "BlazeDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transaction already in progress"])
        }
        try FileManager.default.copyItem(at: fileURL, to: transactionBackupURL)
        print("🟢 Began transaction")
    }

    public func commitTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            try FileManager.default.removeItem(at: transactionBackupURL)
            print("✅ Committed transaction")
        } else {
            throw NSError(domain: "BlazeDB", code: 2, userInfo: [NSLocalizedDescriptionKey: "No transaction in progress"])
        }
    }

    public func rollbackTransaction() throws {
        if FileManager.default.fileExists(atPath: transactionBackupURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.copyItem(at: transactionBackupURL, to: fileURL)
            try FileManager.default.removeItem(at: transactionBackupURL)
            print("🔁 Rolled back transaction")
        } else {
            throw NSError(domain: "BlazeDB", code: 3, userInfo: [NSLocalizedDescriptionKey: "No transaction to roll back"])
        }
    }
}

// MARK: - Corruption & Integrity Validation

public enum BlazeCorruptionError: Error {
    case layoutChecksumMismatch
    case invalidFieldTypes
    case corruptHeader
}

extension BlazeDBClient {
    public func validateDatabaseIntegrity() throws {
        let layout = try StorageLayout.load(from: fileURL)

        // 1. Check layout checksum (if you're tracking hashes)
        if !layout.checksumMatchesStoredValue() {
            throw BlazeCorruptionError.layoutChecksumMismatch
        }

        // 2. Check field type consistency (optional but smart)
        for field in layout.fields {
            if !field.isValidType() {
                throw BlazeCorruptionError.invalidFieldTypes
            }
        }

        // 3. Optional: validate DB header/magic bytes
        if !layout.headerIsValid() {
            throw BlazeCorruptionError.corruptHeader
        }
    }
}

// MARK: - StorageLayout Helpers

extension StorageLayout {
    func checksumMatchesStoredValue() -> Bool {
        // TODO: implement hash comparison (SHA256?) of raw layout vs saved checksum
        return true // Placeholder
    }

    func headerIsValid() -> Bool {
        // TODO: Add actual magic byte or version consistency check
        return true
    }
}

extension FieldDefinition {
    func isValidType() -> Bool {
        switch self.typeName {
        case "string", "int", "double", "bool", "uuid", "date":
            return true
        default:
            return false
        }
    }
}

// MARK: - MetaStore Conformance

extension BlazeDBClient: MetaStore {
    public func fetchMeta() throws -> [String: BlazeDocumentField] {
        return try collection.fetchMeta()
    }

    public func updateMeta(_ newMeta: [String: BlazeDocumentField]) throws {
        try collection.updateMeta(newMeta)
    }
}

// 🔧 BlazeDB Migration Utilities

extension BlazeDBClient {

    /// 🧬 Defines the expected schema for all records
    private var expectedSchema: [String: BlazeDocumentField] {
        return [
            "id": .string(""),
            "createdAt": .date(Date()),
            "title": .string(""),
            "status": .string("open")
        ]
    }

    /// Runs migration logic if the DB file's schema version is outdated
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

    /// 🧠 Reads schema version from the DB file or defaults to 0
    private func loadSchemaVersion() throws -> Int {
        let meta = try metaStore.fetchMeta()
        if let versionField = meta["schemaVersion"], case let .int(version) = versionField {
            return version
        }
        return 0
    }

    /// 💾 Writes the schema version to the meta section
    private func saveSchemaVersion(_ version: Int) throws {
        try metaStore.updateMeta(["schemaVersion": BlazeDocumentField.int(version)])
    }

    /// 🛡️ Backup DB file before applying migration
    private func backupBeforeMigration(version: Int) throws {
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("backup_v\(version).blazedb")
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    /// ⚙️ Automatically reconciles field additions/removals
    private func autoMigrateFields() throws {
        let allRecords = try fetchAll()
        var updated = 0

        for var record in allRecords {
            guard let idField = record.storage["id"],
                  case let .string(idStr) = idField,
                  let id = UUID(uuidString: idStr) else {
                continue
            }

            var didMigrate = false

            for (key, expectedValue) in expectedSchema {
                if record.storage[key] == nil {
                    record.storage[key] = expectedValue
                    didMigrate = true
                }
            }

            if didMigrate {
                try update(id: id, with: record)
                updated += 1
            }
        }

        print("🔁 Migration updated \(updated) records")
    }

    /// 🔤 Renames legacy field names if needed
    private func renameLegacyFields() throws {
        let allRecords = try fetchAll()
        var updated = 0

        for var record in allRecords {
            guard let idField = record.storage["id"],
                  case let .string(idStr) = idField,
                  let id = UUID(uuidString: idStr) else {
                continue
            }

            var didRename = false

            if let oldField = record.storage["summary"] {
                record.storage["title"] = oldField
                record.storage.removeValue(forKey: "summary")
                didRename = true
            }

            if didRename {
                try update(id: id, with: record)
                updated += 1
            }
        }

        print("🔤 Renamed legacy fields in \(updated) records")
    }

    // MARK: - Safe Write Helper
    private func performSafeWrite(_ block: () throws -> Void) throws {
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("transaction_backup.blazedb")

        // Backup before risky op
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: backupURL)

        do {
            try block()
            try FileManager.default.removeItem(at: backupURL)
        } catch {
            print("🧨 Rolling back to backup due to error: \(error)")
            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.copyItem(at: backupURL, to: fileURL)
            throw error
        }
    }
}
