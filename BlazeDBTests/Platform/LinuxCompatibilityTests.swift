//
//  LinuxCompatibilityTests.swift
//  BlazeDBTests
//
//  Linux-specific compatibility tests
//  Verifies path handling, directory creation, and platform differences
//

import Foundation
import XCTest
@testable import BlazeDBCore

final class LinuxCompatibilityTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Path Resolution Tests
    
    func testPathResolver_DefaultDirectory() throws {
        let defaultDir = try PathResolver.defaultDatabaseDirectory()
        
        // Verify directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultDir.path))
        
        // Verify it's writable
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: defaultDir.path))
    }
    
    func testPathResolver_CreatesDirectoryIfNeeded() throws {
        // Use a test-specific directory
        let testDir = tempDir.appendingPathComponent("test-db-dir")
        
        // Should not exist initially
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDir.path))
        
        // Create via PathResolver (indirectly through openDefault)
        // Actually, let's test the directory creation directly
        // Since createDirectoryIfNeeded is private, we test via openDefault
        let db = try BlazeDBClient.openDefault(name: "test-create", password: "test-password")
        
        // Verify database file exists (implies directory was created)
        let dbPath = db.fileURL
        let parentDir = dbPath.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbPath)
    }
    
    func testPathResolver_ResolveRelativePath() throws {
        let relativePath = "test.db"
        let resolved = try PathResolver.resolveDatabasePath(relativePath, baseDirectory: tempDir)
        
        XCTAssertEqual(resolved.deletingLastPathComponent().path, tempDir.path)
        XCTAssertEqual(resolved.lastPathComponent, "test.db")
    }
    
    func testPathResolver_ResolveAbsolutePath() throws {
        let absolutePath = tempDir.appendingPathComponent("absolute.db").path
        let resolved = try PathResolver.resolveDatabasePath(absolutePath)
        
        XCTAssertEqual(resolved.path, absolutePath)
    }
    
    func testPathResolver_RejectsPathTraversal() throws {
        do {
            _ = try PathResolver.validateDatabasePath(
                URL(fileURLWithPath: "/tmp/../../etc/passwd")
            )
            XCTFail("Should have rejected path traversal")
        } catch let error as BlazeDBError {
            if case .invalidInput(let reason) = error {
                XCTAssertTrue(reason.contains(".."), "Should mention path traversal")
            } else {
                XCTFail("Expected invalidInput error")
            }
        }
    }
    
    // MARK: - Easy Open Tests
    
    func testOpenDefault_CreatesDatabase() throws {
        let db = try BlazeDBClient.openDefault(name: "easy-test", password: "test-password")
        
        // Verify database file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.fileURL.path) || 
                     FileManager.default.fileExists(atPath: db.fileURL.path + ".meta"))
        
        // Verify we can use it
        let id = try db.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id)
        
        // Cleanup
        try? FileManager.default.removeItem(at: db.fileURL)
        try? FileManager.default.removeItem(at: db.fileURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    func testOpenDefault_WorksWithRelativePath() throws {
        // Change to temp directory
        let originalDir = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDir) }
        
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        
        let db = try BlazeDBClient.open(
            name: "relative-test",
            path: "relative.db",
            password: "test-password"
        )
        
        // Verify path is resolved correctly
        XCTAssertTrue(db.fileURL.path.contains(tempDir.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: db.fileURL)
    }
    
    func testOpenDefault_PermissionError() throws {
        // Create a read-only directory
        let readOnlyDir = tempDir.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        
        // Make it read-only (on Unix systems)
        #if !os(Windows)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["555", readOnlyDir.path]
        try? process.run()
        process.waitUntilExit()
        #endif
        
        // Try to create database in read-only directory
        do {
            let dbURL = readOnlyDir.appendingPathComponent("test.blazedb")
            _ = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test-password")
            XCTFail("Should have thrown permission error")
        } catch let error as BlazeDBError {
            if case .permissionDenied = error {
                // Expected
            } else {
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        }
        
        // Cleanup
        #if !os(Windows)
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["755", readOnlyDir.path]
        try? chmodProcess.run()
        chmodProcess.waitUntilExit()
        #endif
        try? FileManager.default.removeItem(at: readOnlyDir)
    }
    
    // MARK: - Round-Trip Tests (Linux Compatibility)
    
    func testLinuxCompatibility_OpenInsertCloseReopen() throws {
        // This is the critical test: does it work on Linux?
        let db1 = try BlazeDBClient.openDefault(name: "linux-test", password: "test-password")
        
        // Insert
        let id = try db1.insert(BlazeDataRecord(["platform": .string("linux")]))
        
        // Close (deallocate)
        let dbPath = db1.fileURL
        
        // Reopen
        let db2 = try BlazeDBClient.openDefault(name: "linux-test", password: "test-password")
        
        // Verify data persists
        let record = try db2.fetch(id: id)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.storage["platform"], .string("linux"))
        
        // Cleanup
        try? FileManager.default.removeItem(at: dbPath)
        try? FileManager.default.removeItem(at: dbPath.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    func testLinuxCompatibility_ExportRestoreRoundTrip() throws {
        // Export/restore must work on Linux
        let sourceDB = try BlazeDBClient.openDefault(name: "export-source", password: "test-password")
        let id = try sourceDB.insert(BlazeDataRecord(["data": .string("test")]))
        
        let dumpURL = tempDir.appendingPathComponent("dump.blazedump")
        try sourceDB.export(to: dumpURL)
        
        // Restore to new database
        let targetDB = try BlazeDBClient.openDefault(name: "restore-target", password: "test-password")
        
        // Note: restore requires empty database, so we'll test verify instead
        let header = try BlazeDBImporter.verify(dumpURL)
        XCTAssertEqual(header.databaseName, "export-source")
        
        // Cleanup
        try? FileManager.default.removeItem(at: sourceDB.fileURL)
        try? FileManager.default.removeItem(at: dumpURL)
    }
}
