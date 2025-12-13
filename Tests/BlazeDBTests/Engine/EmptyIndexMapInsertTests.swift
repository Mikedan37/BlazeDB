//
//  EmptyIndexMapInsertTests.swift
//  BlazeDBTests
//
//  Tests for inserting first record when indexMap is empty
//
//  Created by Auto on 2025-11-27.
//

import XCTest
@testable import BlazeDB

final class EmptyIndexMapInsertTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFirstRecordInsert_EmptyDatabase() throws {
        // Create completely fresh database
        let dbURL = tempDir.appendingPathComponent("test_empty.blazedb")
        try? FileManager.default.removeItem(at: dbURL) // Ensure it doesn't exist
        
        let db = try BlazeDBClient(name: "Test", fileURL: dbURL, password: "TestPassword123!")
        
        // Database should be empty
        XCTAssertEqual(db.count(), 0)
        
        // Insert first record - this should work
        let firstRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "key": .string("value")
        ])
        let id = try db.insert(firstRecord)
        
        // Database should now have 1 record
        XCTAssertEqual(db.count(), 1)
        
        // Should be able to retrieve it
        let retrieved = try db.fetch(id: id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.storage["key"]?.stringValue, "value")
    }
    
    func testFirstRecordInsert_WithSpecificID() throws {
        // Create completely fresh database
        let dbURL = tempDir.appendingPathComponent("test_empty_id.blazedb")
        try? FileManager.default.removeItem(at: dbURL)
        
        let db = try BlazeDBClient(name: "Test", fileURL: dbURL, password: "TestPassword123!")
        
        // Database should be empty
        XCTAssertEqual(db.count(), 0)
        
        // Insert first record with specific ID - this should work
        let specificID = UUID()
        let firstRecord = BlazeDataRecord([
            "id": .uuid(specificID),
            "key": .string("value")
        ])
        try db.insert(firstRecord, id: specificID)
        
        // Database should now have 1 record
        XCTAssertEqual(db.count(), 1)
        
        // Should be able to retrieve it
        let retrieved = try db.fetch(id: specificID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.storage["key"]?.stringValue, "value")
    }
    
    func testFirstRecordInsert_VerifyIndexMapInitialized() throws {
        // Create completely fresh database
        let dbURL = tempDir.appendingPathComponent("test_indexmap_init.blazedb")
        try? FileManager.default.removeItem(at: dbURL)
        
        let db = try BlazeDBClient(name: "Test", fileURL: dbURL, password: "TestPassword123!")
        
        // Verify indexMap is empty initially
        XCTAssertEqual(db.collection.indexMap.count, 0)
        
        // Insert first record
        let firstRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "key": .string("value")
        ])
        let id = try db.insert(firstRecord)
        
        // Verify indexMap is now initialized with the record
        XCTAssertEqual(db.collection.indexMap.count, 1)
        XCTAssertNotNil(db.collection.indexMap[id])
    }
}

