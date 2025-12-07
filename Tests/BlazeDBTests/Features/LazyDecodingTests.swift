//
//  LazyDecodingTests.swift
//  BlazeDBTests
//
//  Tests for lazy decoding feature
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class LazyDecodingTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try! BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "LazyDecodingTest123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testLazyDecodingEnabled() throws {
        // Enable lazy decoding
        try db.enableLazyDecoding()
        XCTAssertTrue(db.isLazyDecodingEnabled(), "Lazy decoding should be enabled")
        
        // Disable lazy decoding
        try db.disableLazyDecoding()
        XCTAssertFalse(db.isLazyDecodingEnabled(), "Lazy decoding should be disabled")
    }
    
    func testFieldProjectionWithLazyDecoding() throws {
        // Insert record with many fields
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "description": .string("Long description " + String(repeating: "x", count: 1000)),
            "data": .data(Data(repeating: 0xFF, count: 5000)),
            "metadata": .string(String(repeating: "meta", count: 500))
        ])
        let id = try db.insert(record)
        
        // Query with projection (only name field)
        let results = try db.query()
            .project("name")
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertNotNil(records.first?.storage["name"])
        // Large fields should not be decoded
        XCTAssertNil(records.first?.storage["data"])
        XCTAssertNil(records.first?.storage["description"])
    }
    
    func testBackwardCompatibility() throws {
        // Insert record (v1/v2 format)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Should still decode correctly
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.storage["name"]?.stringValue, "Test")
    }
    
    func testLazyRecordAccess() throws {
        try db.enableLazyDecoding()
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(Data(repeating: 0xFF, count: 10000))
        ])
        let id = try db.insert(record)
        
        // Fetch with lazy decoding
        guard let lazyRecord: LazyBlazeRecord = try db.collection.fetchLazy(id: id) else {
            XCTFail("Should return lazy record when lazy decoding enabled")
            return
        }
        
        // Access small field (decoded immediately)
        let name = lazyRecord["name"]
        XCTAssertNotNil(name)
        
        // Large field not yet decoded
        XCTAssertFalse(lazyRecord.isDecoded("largeData"))
        
        // Access large field (decodes on-demand)
        let largeData = lazyRecord["largeData"]
        XCTAssertNotNil(largeData)
        XCTAssertTrue(lazyRecord.isDecoded("largeData"))
    }
}

