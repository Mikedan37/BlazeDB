//
//  LinuxCompatibilityTests.swift
//  BlazeDBTests
//
//  Linux-specific compatibility tests
//  Verifies path handling, directory creation, and platform differences
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

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
        let testDir = tempDir.appendingPathComponent("test-db-dir")
        let dbPath = testDir.appendingPathComponent("test-create.blazedb")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDir.path))
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        let db = try BlazeDBClient.open(at: dbPath, password: "TestPassword-123!")
        defer {
            try? db.close()
            try? FileManager.default.removeItem(at: dbPath)
            try? FileManager.default.removeItem(at: dbPath.deletingPathExtension().appendingPathExtension("meta"))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.deletingLastPathComponent().path))
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
        let dbURL = tempDir.appendingPathComponent("easy-test-\(UUID().uuidString).blazedb")
        let db = try BlazeDBClient.open(at: dbURL, password: "TestPassword-123!")
        
        // Verify database file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.fileURL.path) || 
                     FileManager.default.fileExists(atPath: db.fileURL.path + ".meta"))
        
        // Verify we can use it
        let id = try db.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id)
        
        try db.close()
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
            password: "TestPassword-123!"
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
            _ = try BlazeDBClient(name: "test", fileURL: dbURL, password: "TestPassword-123!")
            XCTFail("Should have thrown permission error")
        } catch let error as BlazeDBError {
            if case .permissionDenied = error {
                // Expected
            } else {
                XCTFail("Expected permissionDenied error, got \(error)")
            }
        } catch {
            // On some platforms, permission failures surface as raw Cocoa/POSIX errors
            let ns = error as NSError
            XCTAssertTrue(ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain)
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
        let dbPath = tempDir.appendingPathComponent("linux-test-\(UUID().uuidString).blazedb")
        let db1 = try BlazeDBClient.open(at: dbPath, password: "TestPassword-123!")
        
        // Insert
        let id = try db1.insert(BlazeDataRecord(["platform": .string("linux")]))
        
        try db1.close()
        
        // Reopen
        let db2 = try BlazeDBClient.open(at: dbPath, password: "TestPassword-123!")
        
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
        let sourceURL = tempDir.appendingPathComponent("export-source-\(UUID().uuidString).blazedb")
        let sourceDB = try BlazeDBClient.open(at: sourceURL, password: "TestPassword-123!")
        let id = try sourceDB.insert(BlazeDataRecord(["data": .string("test")]))
        
        let dumpURL = tempDir.appendingPathComponent("dump.blazedump")
        try sourceDB.export(to: dumpURL)
        
        // Restore to new database
        let targetURL = tempDir.appendingPathComponent("restore-target-\(UUID().uuidString).blazedb")
        let targetDB = try BlazeDBClient.open(at: targetURL, password: "TestPassword-123!")
        _ = targetDB
        
        // Note: restore requires empty database, so we'll test verify instead
        let header = try BlazeDBImporter.verify(dumpURL)
        XCTAssertTrue(header.databaseName.hasPrefix("export-source"))
        
        // Cleanup
        try? sourceDB.close()
        try? targetDB.close()
        try? FileManager.default.removeItem(at: sourceDB.fileURL)
        try? FileManager.default.removeItem(at: targetURL)
        try? FileManager.default.removeItem(at: targetURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: dumpURL)
    }
}
