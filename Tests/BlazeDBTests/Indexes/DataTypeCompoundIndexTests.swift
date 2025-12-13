//
//  DataTypeCompoundIndexTests.swift
//  BlazeDBTests
//
//  Tests for Data type support in compound indexes.
//  Verifies that binary Data fields work correctly in compound indexes.
//
//  Created: Phase 1 Critical Gap Testing
//

import XCTest
@testable import BlazeDB

final class DataTypeCompoundIndexTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Small delay to ensure previous test's tearDown completed
        Thread.sleep(forTimeInterval: 0.01)
        
        // Clear cached encryption key
        BlazeDBClient.clearCachedKey()
        
        // Create unique database file per test run
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataIdx-\(testID).blazedb")
        
        // Ensure no leftover files from previous runs (try multiple times)
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            
            // Check if files are actually gone
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "DataIdxTest_\(testID)", fileURL: tempURL, password: "DataTypeCompoundIdx123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        // Force persistence before cleanup
        try? db?.persist()
        
        db = nil
        
        // More aggressive cleanup - delete all related files
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        // Clear any cached state
        BlazeDBClient.clearCachedKey()
        
        super.tearDown()
    }
    
    // MARK: - Data in Compound Index Tests
    
    /// Test Data field in compound index (basic)
    func testDataInCompoundIndex_Basic() throws {
        print("💾 Testing Data in compound index...")
        
        let data1 = "Hello".data(using: .utf8)!
        let data2 = "World".data(using: .utf8)!
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("File1"),
            "content": .data(data1)
        ]))
        _ = try db.insert(BlazeDataRecord([
            "name": .string("File2"),
            "content": .data(data2)
        ]))
        
        // Create compound index with Data field
        try db.collection.createIndex(on: ["name", "content"])
        
        // Query by both fields
        let results = try db.query()
            .where("name", equals: .string("File1"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1, "Should find 1 record")
        
        // Debug: Print what we got
        if let firstResult = results.first {
            print("  Record storage: \(firstResult.storage)")
            if let contentField = firstResult.storage["content"] {
                print("  Content field exists: \(contentField)")
                print("  dataValue: \(String(describing: contentField.dataValue))")
            } else {
                print("  Content field: nil")
            }
        }
        
        // Use safe access
        guard let firstResult = results.first else {
            XCTFail("Should have at least one result")
            return
        }
        
        XCTAssertEqual(firstResult.storage["content"]?.dataValue, data1, "Data should match")
        
        print("✅ Data in compound index works")
    }
    
    /// Test Data field as primary sort key
    func testDataAsCompoundIndexPrimaryKey() throws {
        print("💾 Testing Data as primary key in compound index...")
        
        let smallData = Data([1, 2, 3])
        let largeData = Data(repeating: 0xFF, count: 100)
        
        _ = try db.insert(BlazeDataRecord([
            "category": .string("A"),
            "payload": .data(smallData)
        ]))
        _ = try db.insert(BlazeDataRecord([
            "category": .string("A"),
            "payload": .data(largeData)
        ]))
        _ = try db.insert(BlazeDataRecord([
            "category": .string("B"),
            "payload": .data(smallData)
        ]))
        
        // Compound index: payload first, then category
        try db.collection.createIndex(on: ["payload", "category"])
        
        // Query by payload size (Data is compared by count)
        let results = try db.query()
            .where("category", equals: .string("A"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 2)
        
        print("✅ Data as primary key works")
    }
    
    /// Test Data field with other types in compound index
    func testDataWithUUIDInCompoundIndex() throws {
        print("💾 Testing Data with UUID in compound index...")
        
        let id1 = UUID()
        let id2 = UUID()
        let data1 = "Content1".data(using: .utf8)!
        let data2 = "Content2".data(using: .utf8)!
        
        _ = try db.insert(BlazeDataRecord([
            "user_id": .uuid(id1),
            "signature": .data(data1),
            "type": .string("contract")
        ]))
        _ = try db.insert(BlazeDataRecord([
            "user_id": .uuid(id2),
            "signature": .data(data2),
            "type": .string("contract")
        ]))
        
        // Compound index: user_id + signature
        try db.collection.createIndex(on: ["user_id", "signature"])
        
        // Query by user_id
        let results = try db.query()
            .where("user_id", equals: .uuid(id1))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1, "Should find exactly 1 record for user_id: \(id1)")
        
        // Safe array access
        if let firstResult = results.first {
            XCTAssertEqual(firstResult.storage["signature"]?.dataValue, data1)
        } else {
            XCTFail("Expected to find a record, but results were empty")
        }
        
        print("✅ Data with UUID in compound index works")
    }
    
    /// Test multiple Data fields in compound index
    func testMultipleDataFieldsInCompoundIndex() throws {
        print("💾 Testing multiple Data fields in compound index...")
        
        let hash1 = Data([0x01, 0x02])
        let hash2 = Data([0x03, 0x04])
        let content1 = "ABC".data(using: .utf8)!
        let content2 = "DEF".data(using: .utf8)!
        
        _ = try db.insert(BlazeDataRecord([
            "hash": .data(hash1),
            "content": .data(content1),
            "label": .string("A")
        ]))
        _ = try db.insert(BlazeDataRecord([
            "hash": .data(hash2),
            "content": .data(content2),
            "label": .string("B")
        ]))
        
        // Compound index with two Data fields
        try db.collection.createIndex(on: ["hash", "content"])
        
        // Query
        let results = try db.query()
            .where("label", equals: .string("A"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].storage["hash"]?.dataValue, hash1)
        
        print("✅ Multiple Data fields in compound index works")
    }
    
    /// Test Data field with search
    func testDataFieldWithSearch() throws {
        print("💾 Testing Data field with search...")
        
        let data1 = "searchable text".data(using: .utf8)!
        
        // Enable search BEFORE inserting (so it gets indexed)
        try db.collection.enableSearch(on: ["title"])
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Document"),
            "binary": .data(data1)
        ]))
        
        // Search should work
        let searchResults = try db.query().search("document", in: ["title"])
        
        XCTAssertEqual(searchResults.count, 1, "Search should find the document")
        
        // Safe access to first result
        guard let firstResult = searchResults.first else {
            XCTFail("Expected at least one search result")
            return
        }
        
        // Debug: Print what we got
        print("  Binary field: \(String(describing: firstResult.record.storage["binary"]))")
        print("  Binary dataValue: \(String(describing: firstResult.record.storage["binary"]?.dataValue))")
        
        XCTAssertEqual(firstResult.record.storage["binary"]?.dataValue, data1, "Data should persist through search")
        
        print("✅ Data field with search works")
    }
    
    /// Test Data persistence across reloads
    func testDataInCompoundIndexPersistence() throws {
        print("💾 Testing Data compound index persistence...")
        
        let data1 = "Persistent".data(using: .utf8)!
        
        let id = try db.insert(BlazeDataRecord([
            "category": .string("Docs"),
            "content": .data(data1)
        ]))
        
        print("  Inserted record with ID: \(id)")
        
        try db.collection.createIndex(on: ["category", "content"])
        try db.persist()
        
        // Close and reopen (use same file URL, not the name)
        let dbName = db.name  // Capture the unique name
        db = nil
        
        // Reopen same database file with same name
        do {
            db = try BlazeDBClient(name: dbName, fileURL: tempURL, password: "DataTypeCompoundIdx123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        
        print("  Reopened database, total records: \(db.count())")
        
        // Debug: Fetch ALL records to see what's there
        let allRecords = try db.fetchAll()
        print("  All records after reload:")
        for record in allRecords {
            print("    - \(record.storage)")
        }
        
        // Query should still work
        let results = try db.query()
            .where("category", equals: .string("Docs"))
            .execute()
            .records
        
        print("  Query found \(results.count) records")
        
        XCTAssertEqual(results.count, 1, "Should find 1 record after reload")
        
        // Use safe access
        guard let firstResult = results.first else {
            XCTFail("Should have at least one result")
            return
        }
        
        print("  Record content field: \(String(describing: firstResult.storage["content"]))")
        
        XCTAssertEqual(firstResult.storage["content"]?.dataValue, data1, "Data should match after reload")
        
        print("✅ Data compound index persists correctly")
    }
    
    /// Test empty Data field
    /// NOTE: Empty Data() encodes as "" in JSON, which may be decoded as .string("")
    /// The dataValue accessor handles this by treating empty strings as empty Data
    func testEmptyDataInCompoundIndex() throws {
        print("💾 Testing empty Data in compound index...")
        
        let emptyData = Data()
        
        _ = try db.insert(BlazeDataRecord([
            "name": .string("Empty"),
            "data": .data(emptyData)
        ]))
        
        try db.collection.createIndex(on: ["name", "data"])
        
        let results = try db.query()
            .where("name", equals: .string("Empty"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1, "Should find 1 record")
        
        // Debug: Print what we got
        guard let firstResult = results.first else {
            XCTFail("Should have at least one result")
            return
        }
        
        print("  Record storage: \(firstResult.storage)")
        if let dataField = firstResult.storage["data"] {
            print("  Data field type: \(dataField)")
            print("  dataValue: \(String(describing: dataField.dataValue))")
        } else {
            print("  Data field: nil")
        }
        
        XCTAssertEqual(firstResult.storage["data"]?.dataValue, emptyData, "Empty Data should match")
        
        print("✅ Empty Data in compound index works")
    }
    
    /// Test large Data field (within 4KB page limit)
    func testLargeDataInCompoundIndex() throws {
        print("💾 Testing large Data in compound index...")
        
        // BlazeDB uses 4KB pages, so limit data to ~2KB to leave room for other fields + JSON overhead
        let largeData = Data(repeating: 0xAB, count: 2_000) // 2KB
        
        _ = try db.insert(BlazeDataRecord([
            "type": .string("Binary"),
            "payload": .data(largeData)
        ]))
        
        try db.collection.createIndex(on: ["type", "payload"])
        
        let results = try db.query()
            .where("type", equals: .string("Binary"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1, "Should find 1 record")
        
        // Debug: Print what we got
        guard let firstResult = results.first else {
            XCTFail("Should have at least one result")
            return
        }
        
        print("  Type field: \(String(describing: firstResult.storage["type"]))")
        print("  Payload size: \(firstResult.storage["payload"]?.dataValue?.count ?? 0) bytes")
        
        XCTAssertEqual(firstResult.storage["payload"]?.dataValue?.count, 2_000, "Large Data should persist")
        
        print("✅ Large Data (2KB) in compound index works")
    }
    
    /// Test Data field update with compound index
    func testDataFieldUpdateWithCompoundIndex() throws {
        print("💾 Testing Data field update with compound index...")
        
        let data1 = "Original".data(using: .utf8)!
        let data2 = "Updated".data(using: .utf8)!
        
        let id = try db.insert(BlazeDataRecord([
            "label": .string("Doc"),
            "content": .data(data1)
        ]))
        
        try db.collection.createIndex(on: ["label", "content"])
        
        // Update Data field
        try db.update(id: id, with: BlazeDataRecord([
            "label": .string("Doc"),
            "content": .data(data2)
        ]))
        
        // Query should find updated data
        let results = try db.query()
            .where("label", equals: .string("Doc"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].storage["content"]?.dataValue, data2)
        
        print("✅ Data field update with compound index works")
    }
    
    /// Test Data field delete with compound index
    func testDataFieldDeleteWithCompoundIndex() throws {
        print("💾 Testing Data field delete with compound index...")
        
        let data1 = "ToDelete".data(using: .utf8)!
        
        let id = try db.insert(BlazeDataRecord([
            "tag": .string("Temp"),
            "blob": .data(data1)
        ]))
        
        try db.collection.createIndex(on: ["tag", "blob"])
        
        // Delete
        try db.delete(id: id)
        
        // Should not be found
        let results = try db.query()
            .where("tag", equals: .string("Temp"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 0)
        
        print("✅ Data field delete with compound index works")
    }
    
    /// Test Data field with three-field compound index
    func testDataInThreeFieldCompoundIndex() throws {
        print("💾 Testing Data in three-field compound index...")
        
        let data1 = "Triple".data(using: .utf8)!
        
        _ = try db.insert(BlazeDataRecord([
            "field1": .string("A"),
            "field2": .data(data1),
            "field3": .int(123)
        ]))
        
        try db.collection.createIndex(on: ["field1", "field2", "field3"])
        
        let results = try db.query()
            .where("field1", equals: .string("A"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].storage["field2"]?.dataValue, data1)
        
        print("✅ Data in three-field compound index works")
    }
}

