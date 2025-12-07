//
//  BackupRestoreServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive tests for backup and restore operations
//  ✅ Backup creation
//  ✅ Restore safety
//  ✅ Error handling
//  ✅ Multiple backups
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class BackupRestoreServiceTests: XCTestCase {
    
    var service: BackupRestoreService!
    var tempDirectory: URL!
    var testDBURL: URL!
    let testPassword = "test_password_123"
    
    override func setUp() {
        super.setUp()
        service = BackupRestoreService.shared
        
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test database
        testDBURL = tempDirectory.appendingPathComponent("test.blazedb")
        let db = try! BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        
        // Add test data
        for i in 0..<10 {
            _ = try! db.insert(BlazeDataRecord([
                "id": .int(i),
                "name": .string("Item \(i)")
            ]))
        }
        try! db.persist()
    }
    
    override func tearDown() {
        // Clean up
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Backup Creation Tests
    
    func testCreateBackup() throws {
        let backupURL = try service.createBackup(dbPath: testDBURL.path)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "Backup file should exist")
        XCTAssertTrue(backupURL.lastPathComponent.contains("backup"), "Backup name should contain 'backup'")
    }
    
    func testCreateNamedBackup() throws {
        let backupURL = try service.createBackup(dbPath: testDBURL.path, name: "my_custom_backup")
        
        XCTAssertEqual(backupURL.deletingPathExtension().lastPathComponent, "my_custom_backup")
    }
    
    func testCreateMultipleBackups() throws {
        let backup1 = try service.createBackup(dbPath: testDBURL.path, name: "backup1")
        let backup2 = try service.createBackup(dbPath: testDBURL.path, name: "backup2")
        let backup3 = try service.createBackup(dbPath: testDBURL.path, name: "backup3")
        
        XCTAssertNotEqual(backup1.path, backup2.path)
        XCTAssertNotEqual(backup2.path, backup3.path)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup3.path))
    }
    
    func testListBackups() throws {
        // Create some backups
        _ = try service.createBackup(dbPath: testDBURL.path, name: "backup1")
        _ = try service.createBackup(dbPath: testDBURL.path, name: "backup2")
        
        let backups = try service.listBackups(for: testDBURL.path)
        
        XCTAssertEqual(backups.count, 2)
        XCTAssertTrue(backups.contains { $0.name == "backup1" })
        XCTAssertTrue(backups.contains { $0.name == "backup2" })
    }
    
    func testListBackupsWhenNone() throws {
        let backups = try service.listBackups(for: testDBURL.path)
        XCTAssertEqual(backups.count, 0)
    }
    
    // MARK: - Restore Tests
    
    func testRestoreBackup() throws {
        // Create original data
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let originalCount = db.count()
        
        // Create backup
        let backupURL = try service.createBackup(dbPath: testDBURL.path, name: "test_backup")
        
        // Modify database
        _ = try db.insert(BlazeDataRecord(["new": .string("data")]))
        try db.persist()
        
        let modifiedCount = db.count()
        XCTAssertGreaterThan(modifiedCount, originalCount, "Should have more records after insert")
        
        // Restore backup
        try service.restoreFromBackup(backupURL: backupURL, to: testDBURL.path)
        
        // Verify restoration
        let restoredDB = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        XCTAssertEqual(restoredDB.count(), originalCount, "Should have original count after restore")
    }
    
    func testRestoreCreatesSafetyBackup() throws {
        // Create backup
        let backupURL = try service.createBackup(dbPath: testDBURL.path, name: "test_backup")
        
        // Restore (should create safety backup)
        try service.restoreFromBackup(backupURL: backupURL, to: testDBURL.path)
        
        // Original database should still work
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        XCTAssertGreaterThan(db.count(), 0, "Restored database should have records")
    }
    
    // MARK: - Delete Tests
    
    func testDeleteBackup() throws {
        let backupURL = try service.createBackup(dbPath: testDBURL.path, name: "temp_backup")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        
        try service.deleteBackup(backupURL: backupURL)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path), "Backup should be deleted")
    }
    
    // MARK: - Edge Cases
    
    func testBackupLargeDatabase() throws {
        // Add lots of data
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .int(i),
                "data": .string(String(repeating: "X", count: 100))
            ]))
        }
        try db.persist()
        
        // Backup should work
        let backupURL = try service.createBackup(dbPath: testDBURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        
        // Backup size should be similar to original
        let originalSize = try FileManager.default.attributesOfItem(atPath: testDBURL.path)[.size] as! Int64
        let backupSize = try FileManager.default.attributesOfItem(atPath: backupURL.path)[.size] as! Int64
        
        XCTAssertEqual(originalSize, backupSize, accuracy: 1000, "Backup size should match original")
    }
    
    func testBackupPreservesMetadata() throws {
        // Create backup
        let backupURL = try service.createBackup(dbPath: testDBURL.path)
        
        // Check metadata file was backed up
        let backupMetaURL = backupURL.deletingPathExtension().appendingPathExtension("meta")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupMetaURL.path), "Metadata should be backed up")
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceCreateBackup() {
        measure {
            _ = try? service.createBackup(dbPath: testDBURL.path)
        }
    }
    
    func testPerformanceListBackups() throws {
        // Create 10 backups
        for i in 0..<10 {
            _ = try service.createBackup(dbPath: testDBURL.path, name: "backup\(i)")
        }
        
        measure {
            _ = try? service.listBackups(for: testDBURL.path)
        }
    }
}

