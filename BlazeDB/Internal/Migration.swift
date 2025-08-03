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
        let meta = try metaStore.fetchMeta()
        return meta["schemaVersion"]?.intValue ?? 0
    }

    /// 💾 Writes the schema version to the meta section
    private func saveSchemaVersion(_ version: Int) throws {
        try metaStore.updateMeta(["schemaVersion": .int(version)])
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

        for (id, record) in allRecords {
            var migrated = record

            // Example: Add new field if missing
            if migrated["createdAt"] == nil {
                migrated["createdAt"] = .date(Date())
            }

            // Example: Rename fields
            // if migrated.removeValue(forKey: "oldField") != nil {
            //     migrated["newField"] = .string("migrated")
            // }

            if migrated != record {
                try update(id: id, with: migrated)
                updated += 1
            }
        }

        print("🔁 Migration updated \(updated) records")
    }
}
