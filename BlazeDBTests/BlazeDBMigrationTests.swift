//  BlazeDBMigrationTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

@MainActor
final class BlazeDBMigrationTests: XCTestCase {
    
    func testAddRemoveRenameFieldsMigration() throws {
        // Initial schema version
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("migrationtest.blazedb")
        try? FileManager.default.removeItem(at: fileURL)
        
        // Create database with initial record
        var db = try BlazeDBClient(name: "TestDB", fileURL: fileURL, password: "test123")
        var record = BlazeDataRecord([
            "title": .string("World"),
            "value": .int(42)
        ])
        let id = try db.insert(record)
        print("Inserted record with id: \(id)")
        
        // Simulate app relaunch with new schema
        db = try BlazeDBClient(name: "TestDB", fileURL: fileURL, password: "test123")
        
        // Define expected schema update
        db.expectedSchema = [
            "title": .string(""),
            "value": .int(0),
            "createdAt": .date(.now),
            "status": .string("open")
        ]
        
        try db.performMigrationIfNeeded()
        
        guard let record = try db.fetch(id: id) else {
            print("Unable to fetch Database")
            return
        }
        
        XCTAssertNotNil(record["createdAt"])
        XCTAssertNotNil(record["status"])
        XCTAssertEqual(record["status"], .string("open"))
        print("Auto-migrated new fields onto old record")
    }
    
    func testBackupBeforeMigration() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("backuptest.blazedb")
        try? FileManager.default.removeItem(at: fileURL)
        
        var db = try BlazeDBClient(name: "BackupTestDB", fileURL: fileURL, password: "backupme")
        _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
        
        db = try BlazeDBClient(name: "BackupTestDB", fileURL: fileURL, password: "backupme")
        db.expectedSchema = ["x": .int(1), "newField": .string("")]
        try db.performMigrationIfNeeded()
        
        print("📁 Listing all files in temporary directory:")
        let tempFiles = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        for file in tempFiles {
            print(" - \(file)")
        }

        // Search recursively for any backup_v1 file under the temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        var foundBackup: URL? = nil
        
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent.starts(with: "backup_v") &&
               (file.pathExtension == "blazedb" || file.pathExtension == "meta") {
                foundBackup = file
                break
            }
        }
        
        XCTAssertNotNil(foundBackup, "Expected backup not found anywhere under \(tempDir.path)")
        if let backup = foundBackup {
            print("✅ Backup created at: \(backup.path)")
        }
    }
    
}
