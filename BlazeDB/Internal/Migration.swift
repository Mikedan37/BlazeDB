//  Migration.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.


import Foundation

extension BlazeDBClient {

    /// Runs migration logic if the DB file's schema version is outdated
    func performMigrationIfNeeded() throws {
        let currentVersion = 1
        let existingVersion = try loadSchemaVersion()

        if existingVersion < currentVersion {
            try backupBeforeMigration(version: existingVersion)
            try autoMigrateFields()
            try saveSchemaVersion(currentVersion)
        }
    }

    /// 🧠 Reads schema version from the DB file or defaults to 0
    private func loadSchemaVersion() throws -> Int {
        #if !BLAZEDB_LINUX_CORE
        let meta = try collection.fetchMeta()
        return meta["schemaVersion"]?.intValue ?? 0
        #else
        // Linux: Schema version not supported, default to 0
        return 0
        #endif
    }

    /// 💾 Writes the schema version to the meta section
    private func saveSchemaVersion(_ version: Int) throws {
        #if !BLAZEDB_LINUX_CORE
        try collection.updateMeta(["schemaVersion": .int(version)])
        #else
        // Linux: Schema version not supported, no-op
        #endif
    }

    /// 🛡️ Backup DB file before applying migration
    private func backupBeforeMigration(version: Int) throws {
        let dir = fileURL.deletingLastPathComponent()
        let backupURL = dir.appendingPathComponent("backup_v\(version)_\(UUID().uuidString).blazedb")
        let backupMetaURL = dir.appendingPathComponent("backup_v\(version)_\(UUID().uuidString).meta")
        
        // Copy database file
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        
        // Copy meta file if it exists
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try? FileManager.default.copyItem(at: metaURL, to: backupMetaURL)
        }
    }

    /// ⚙️ Automatically reconciles field additions/removals
    private func autoMigrateFields() throws {
        let allRecords = try fetchAll()
        var updated = 0

        for record in allRecords {
            guard let id = record.storage["id"]?.uuidValue else { continue }
            var migrated = record.storage

            // Example: Add new field if missing
            if migrated["createdAt"] == nil {
                migrated["createdAt"] = .date(Date())
            }

            // Example: Rename fields
            // if migrated.removeValue(forKey: "oldField") != nil {
            //     migrated["newField"] = .string("migrated")
            // }

            if migrated != record.storage {
                try update(id: id, with: BlazeDataRecord(migrated))
                updated += 1
            }
        }

        BlazeLogger.info("Migration updated \(updated) records")
    }
}
