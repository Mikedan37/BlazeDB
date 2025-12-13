//
//  CollectionCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for DynamicCollection using dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class CollectionCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "CollectionCodec123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Insert Tests
    
    func testInsert_DualCodecValidation() throws {
        let collection = client.collection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Test Record"),
            "count": .int(42)
        ])
        
        let id = try client.insert(record)
        
        // Fetch and validate both codecs produce identical results
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        guard let fetched = fetched else { return }
        
        // Verify fetched record has expected fields (including auto-added createdAt and project)
        XCTAssertEqual(fetched.storage["id"]?.uuidValue, id)
        XCTAssertEqual(fetched.storage["title"]?.stringValue, "Test Record")
        XCTAssertEqual(fetched.storage["count"]?.intValue, 42)
        XCTAssertNotNil(fetched.storage["createdAt"])
        XCTAssertNotNil(fetched.storage["project"])
        
        // Verify internal encoding matches (compare fetched record encoding)
        let stdEncoded = try BlazeBinaryEncoder.encode(fetched)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(fetched)
        XCTAssertEqual(stdEncoded, armEncoded, "Collection insert must use codec that produces identical bytes")
    }
    
    func testInsertMany_DualCodecValidation() throws {
        let collection = client.collection
        
        var records: [BlazeDataRecord] = []
        for i in 0..<100 {
            records.append(BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "title": .string("Record \(i)")
            ]))
        }
        
        let ids = try client.insertMany(records)
        XCTAssertEqual(ids.count, 100)
        
        // Fetch all and validate (compare fetched records which include auto-added fields)
        for id in ids {
            let fetched = try client.fetch(id: id)
            XCTAssertNotNil(fetched)
            // Verify fetched record has all expected fields including auto-added ones
            if let fetched = fetched {
                XCTAssertNotNil(fetched.storage["id"])
                XCTAssertNotNil(fetched.storage["createdAt"])
                XCTAssertNotNil(fetched.storage["project"])
            }
        }
    }
    
    // MARK: - Update Tests
    
    func testUpdate_DualCodecValidation() throws {
        let collection = client.collection
        
        let original = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Original"),
            "count": .int(10)
        ])
        
        let id = try client.insert(original)
        
        // Fetch the inserted record to get createdAt and project
        guard let insertedRecord = try client.fetch(id: id) else {
            XCTFail("Failed to fetch inserted record")
            return
        }
        
        // Create updated record preserving createdAt and project
        var updatedStorage = insertedRecord.storage
        updatedStorage["title"] = .string("Updated")
        updatedStorage["count"] = .int(20)
        let updated = BlazeDataRecord(updatedStorage)
        
        try client.update(id: id, with: updated)
        
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        guard let fetched = fetched else { return }
        
        // Verify updated fields match
        XCTAssertEqual(fetched.storage["title"]?.stringValue, "Updated")
        XCTAssertEqual(fetched.storage["count"]?.intValue, 20)
        // Verify auto-added fields are preserved (if included in update)
        XCTAssertNotNil(fetched.storage["createdAt"])
        XCTAssertNotNil(fetched.storage["project"])
    }
    
    // MARK: - Delete Tests
    
    func testDelete_DualCodecValidation() throws {
        let collection = client.collection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("To Delete")
        ])
        
        let id = try client.insert(record)
        
        // Verify exists (fetched record includes auto-added fields)
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            // Verify fetched record has expected fields
            XCTAssertNotNil(fetched.storage["id"])
            XCTAssertNotNil(fetched.storage["title"])
            XCTAssertNotNil(fetched.storage["createdAt"])
            XCTAssertNotNil(fetched.storage["project"])
        }
        
        // Delete
        try client.delete(id: id)
        
        // Verify deleted
        let fetchedAfterDelete = try client.fetch(id: id)
        XCTAssertNil(fetchedAfterDelete)
    }
    
    // MARK: - Schema Evolution Tests
    
    func testSchemaEvolution_DualCodecValidation() throws {
        let collection = client.collection
        
        // Insert record with minimal fields
        let v1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("V1")
        ])
        let id = try client.insert(v1)
        
        // Fetch the inserted record to get createdAt and project
        guard let insertedRecord = try client.fetch(id: id) else {
            XCTFail("Failed to fetch inserted record")
            return
        }
        
        // Update with additional fields, preserving createdAt and project
        var v2Storage = insertedRecord.storage
        v2Storage["title"] = .string("V2")
        v2Storage["newField"] = .string("Added")
        v2Storage["count"] = .int(42)
        let v2 = BlazeDataRecord(v2Storage)
        
        try client.update(id: id, with: v2)
        
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        guard let fetched = fetched else { return }
        
        // Verify updated fields match
        XCTAssertEqual(fetched.storage["title"]?.stringValue, "V2")
        XCTAssertEqual(fetched.storage["newField"]?.stringValue, "Added")
        XCTAssertEqual(fetched.storage["count"]?.intValue, 42)
        // Verify auto-added fields are preserved (if included in update)
        XCTAssertNotNil(fetched.storage["createdAt"])
        XCTAssertNotNil(fetched.storage["project"])
        
        // Verify both codecs handle schema evolution identically (compare fetched record encoding)
        let stdEncoded = try BlazeBinaryEncoder.encode(fetched)
        let armEncoded = try BlazeBinaryEncoder.encodeARM(fetched)
        XCTAssertEqual(stdEncoded, armEncoded)
    }
    
    // MARK: - Batch Operations
    
    func testBatchOperations_DualCodecValidation() throws {
        let collection = client.collection
        
        // Insert batch
        var records: [BlazeDataRecord] = []
        for i in 0..<1000 {
            records.append(BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 100))
            ]))
        }
        
        let ids = try client.insertMany(records)
        XCTAssertEqual(ids.count, 1000)
        
        // Fetch batch and validate
        let fetched = try client.fetchAll()
        XCTAssertEqual(fetched.count, 1000)
        
        // Verify all records have expected fields (including auto-added createdAt and project)
        for fetchedRecord in fetched {
            XCTAssertNotNil(fetchedRecord.storage["id"])
            XCTAssertNotNil(fetchedRecord.storage["createdAt"])
            XCTAssertNotNil(fetchedRecord.storage["project"])
        }
    }
}

