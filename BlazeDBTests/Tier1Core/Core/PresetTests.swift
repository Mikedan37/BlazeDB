//
//  PresetTests.swift
//  BlazeDBTests
//
//  Tests for preset open methods (openForCLI, openForDaemon, openForTesting)
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PresetTests: XCTestCase {
    
    private var tempDir: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func uniqueName(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
    
    // MARK: - openForCLI Tests
    
    func testOpenForCLI_Succeeds() throws {
        let db = try BlazeDBClient.openForCLI(name: uniqueName("clitest"), password: "TestPassword-123!")
        defer { try? db.close() }
        XCTAssertNotNil(db)
        XCTAssertTrue(db.name.hasPrefix("clitest-"))
    }
    
    func testOpenForCLI_UsesDefaultDirectory() throws {
        let db = try BlazeDBClient.openForCLI(name: uniqueName("clitest"), password: "TestPassword-123!")
        defer { try? db.close() }
        let expectedDir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertTrue(db.fileURL.path.contains(expectedDir.path))
    }
    
    // MARK: - openForDaemon Tests
    
    func testOpenForDaemon_Succeeds() throws {
        let db = try BlazeDBClient.openForDaemon(name: uniqueName("daemontest"), password: "TestPassword-123!")
        defer { try? db.close() }
        XCTAssertNotNil(db)
        XCTAssertTrue(db.name.hasPrefix("daemontest-"))
    }
    
    func testOpenForDaemon_UsesDefaultDirectory() throws {
        let db = try BlazeDBClient.openForDaemon(name: uniqueName("daemontest"), password: "TestPassword-123!")
        defer { try? db.close() }
        let expectedDir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertTrue(db.fileURL.path.contains(expectedDir.path))
    }
    
    // MARK: - openForTesting Tests
    
    func testOpenForTesting_Succeeds() throws {
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        XCTAssertNotNil(db)
        XCTAssertTrue(db.name.hasPrefix("testdb-"))
    }
    
    func testOpenForTesting_UsesTemporaryDirectory() throws {
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        let systemTemp = FileManager.default.temporaryDirectory
        XCTAssertTrue(db.fileURL.path.contains(systemTemp.path))
    }
    
    func testOpenForTesting_DefaultName() throws {
        let db = try BlazeDBClient.openForTesting(password: "TestPassword-123!")
        defer { try? db.close() }
        XCTAssertNotNil(db)
        // Name should be UUID-based
        XCTAssertFalse(db.name.isEmpty)
    }
    
    func testOpenForTesting_CanInsertAndQuery() throws {
        let db = try BlazeDBClient.openForTesting(name: uniqueName("testdb"), password: "TestPassword-123!")
        defer { try? db.close() }
        
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
