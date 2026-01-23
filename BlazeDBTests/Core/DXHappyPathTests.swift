//
//  DXHappyPathTests.swift
//  BlazeDBTests
//
//  Tests for happy path DX convenience methods
//

import XCTest
@testable import BlazeDBCore

final class DXHappyPathTests: XCTestCase {
    
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
    
    // MARK: - openTemporary Tests
    
    func testOpenTemporary_WritesAndReads() throws {
        let db = try BlazeDBClient.openTemporary(password: "test-password")
        defer { try? FileManager.default.removeItem(at: db.fileURL) }
        
        // Write
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        XCTAssertNotNil(id)
        
        // Read
        let record = try db.fetch(id: id)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.string("name"), "Test")
    }
    
    // MARK: - openOrCreate Tests
    
    func testOpenOrCreate_CreatesDirectory() throws {
        // Should create database if it doesn't exist
        let db = try BlazeDBClient.openOrCreate(name: "testdb", password: "test-password")
        
        // Verify database file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.fileURL.path))
        
        // Can insert records
        let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
        XCTAssertNotNil(id)
    }
    
    // MARK: - insertMany Tests
    
    func testInsertMany_InsertsAllRecords() throws {
        let db = try BlazeDBClient.openTemporary(password: "test-password")
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
        
        try BlazeDBClient.withDatabase(name: "testdb", password: "test-password") { db in
            executed = true
            let id = try db.insert(BlazeDataRecord(["name": .string("Test")]))
            XCTAssertNotNil(id)
        }
        
        XCTAssertTrue(executed)
    }
}
