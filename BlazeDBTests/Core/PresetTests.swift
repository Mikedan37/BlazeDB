//
//  PresetTests.swift
//  BlazeDBTests
//
//  Tests for preset open methods (openForCLI, openForDaemon, openForTesting)
//

import XCTest
@testable import BlazeDBCore

final class PresetTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - openForCLI Tests
    
    func testOpenForCLI_Succeeds() throws {
        let db = try BlazeDBClient.openForCLI(name: "clitest", password: "test-password")
        XCTAssertNotNil(db)
        XCTAssertEqual(db.name, "clitest")
    }
    
    func testOpenForCLI_UsesDefaultDirectory() throws {
        let db = try BlazeDBClient.openForCLI(name: "clitest", password: "test-password")
        let expectedDir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertTrue(db.fileURL.path.contains(expectedDir.path))
    }
    
    // MARK: - openForDaemon Tests
    
    func testOpenForDaemon_Succeeds() throws {
        let db = try BlazeDBClient.openForDaemon(name: "daemontest", password: "test-password")
        XCTAssertNotNil(db)
        XCTAssertEqual(db.name, "daemontest")
    }
    
    func testOpenForDaemon_UsesDefaultDirectory() throws {
        let db = try BlazeDBClient.openForDaemon(name: "daemontest", password: "test-password")
        let expectedDir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertTrue(db.fileURL.path.contains(expectedDir.path))
    }
    
    // MARK: - openForTesting Tests
    
    func testOpenForTesting_Succeeds() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        XCTAssertNotNil(db)
        XCTAssertEqual(db.name, "testdb")
    }
    
    func testOpenForTesting_UsesTemporaryDirectory() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        let tempDir = FileManager.default.temporaryDirectory
        XCTAssertTrue(db.fileURL.path.contains(tempDir.path))
    }
    
    func testOpenForTesting_DefaultName() throws {
        let db = try BlazeDBClient.openForTesting(password: "test-password")
        XCTAssertNotNil(db)
        // Name should be UUID-based
        XCTAssertFalse(db.name.isEmpty)
    }
    
    func testOpenForTesting_CanInsertAndQuery() throws {
        let db = try BlazeDBClient.openForTesting(name: "testdb", password: "test-password")
        
        // Insert
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        XCTAssertNotNil(id)
        
        // Query
        let results = try db.query()
            .where("name", equals: .string("Test"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1)
    }
}
