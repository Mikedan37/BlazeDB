//
//  DXHappyPathTests.swift
//  BlazeDBTests
//
//  Tests for happy path DX convenience methods
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DXHappyPathTests: XCTestCase {
    
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
    
    // MARK: - openTemporary Tests
    
    func testOpenTemporary_WritesAndReads() throws {
        let db = try BlazeDBClient.openTemporary(password: "TestPassword-123!")
        defer { try? FileManager.default.removeItem(at: db.fileURL) }
        
        // Write
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        XCTAssertNotNil(id)
        
        // Read
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record)
        XCTAssertEqual(try record?.string("name"), "Test")
    }
    
    // MARK: - openOrCreate Tests
    
    func testOpenOrCreate_CreatesDirectory() throws {
        // Should create database if it doesn't exist
        let db = try BlazeDBClient.openOrCreate(name: "testdb", password: "TestPassword-123!")
        
        // Verify database file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: try db.fileURL.path))
        
        // Can insert records
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        XCTAssertNotNil(id)
    }
    
    // MARK: - insertMany Tests
    
    func testInsertMany_InsertsAllRecords() throws {
        let db = try BlazeDBClient.openTemporary(password: "TestPassword-123!")
        defer { try? FileManager.default.removeItem(at: db.fileURL) }
        
        let records = (1...10).map { i in
            BlazeDataRecord(["id": .int(i), "name": .string("Item \(i)")])
        }
        
        let ids = try db.insertMany(records)
        XCTAssertEqual(ids.count, 10)
        
        // Verify all records exist
        for id in ids {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record)
        }
    }
    
    // MARK: - withDatabase Tests
    
    func testWithDatabase_ExecutesBlock() throws {
        var executed = false
        
        try BlazeDBClient.withDatabase(name: "testdb", password: "TestPassword-123!") { db in
            executed = true
            let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
            XCTAssertNotNil(id)
        }
        
        XCTAssertTrue(executed)
    }
}
