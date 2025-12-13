//
//  EdgeCaseTests.swift
//  BlazeDBTests
//
//  Edge case tests for empty data, large data, concurrent access
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class EdgeCaseTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_edge_\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "TestEdge", fileURL: tempURL, password: "EdgeCaseTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.collection.destroy()
        try? FileManager.default.removeItem(at: tempURL)
        db = nil
        super.tearDown()
    }
    
    func testEmptyDatabase() throws {
        // Query empty database
        let results = try db.query().execute()
        let records = try results.records
        XCTAssertEqual(records.count, 0)
        
        // Query with filters
        let filtered = try db.query()
            .where("name", equals: .string("test"))
            .execute()
        let filteredRecords = try filtered.records
        XCTAssertEqual(filteredRecords.count, 0)
    }
    
    func testEmptyFields() throws {
        // Insert record with empty fields
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "emptyString": .string(""),
            "emptyData": .data(Data()),
            "emptyArray": .array([])
        ]))
        
        // Query should work
        let results = try db.query()
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
    }
    
    func testVeryLargeFields() throws {
        // Insert record with large field (2KB - within page size limit)
        let largeData = Data(repeating: 0xFF, count: 2_000)
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "largeData": .data(largeData)
        ]))
        
        // Query should work
        let results = try db.query()
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        if case .data(let data) = records.first?.storage["largeData"] {
            XCTAssertEqual(data.count, 2_000)
        } else {
            XCTFail("Large data field not found")
        }
    }
    
    func testManyFields() throws {
        // Insert record with many fields (200 fields - within page size limit)
        var fields: [String: BlazeDocumentField] = ["id": .uuid(UUID())]
        for i in 0..<200 {
            fields["field\(i)"] = .string("value\(i)")
        }
        
        let id = try db.insert(BlazeDataRecord(fields))
        
        // Query should work
        let results = try db.query()
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        // 200 custom fields + id + createdAt + project = 203
        XCTAssertEqual(records.first?.storage.count, 203)
    }
    
    func testConcurrentReads() throws {
        // Insert records
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i)
            ]))
        }
        
        // Concurrent reads
        let expectation = XCTestExpectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 10
        
        for _ in 0..<10 {
            DispatchQueue.global().async {
                do {
                    let results = try self.db.query()
                        .where("index", equals: .int(500))
                        .execute()
                    let records = try results.records
                    XCTAssertEqual(records.count, 1)
                } catch {
                    XCTFail("Concurrent read failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testConcurrentReadWrite() throws {
        // Concurrent reads and writes
        let expectation = XCTestExpectation(description: "Concurrent read/write")
        expectation.expectedFulfillmentCount = 20
        
        // Writers
        for i in 0..<10 {
            DispatchQueue.global().async {
                do {
                    _ = try self.db.insert(BlazeDataRecord([
                        "id": .uuid(UUID()),
                        "thread": .int(i)
                    ]))
                } catch {
                    XCTFail("Concurrent write failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        // Readers
        for _ in 0..<10 {
            DispatchQueue.global().async {
                do {
                    let results = try self.db.query().execute()
                    _ = try results.records
                } catch {
                    XCTFail("Concurrent read failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testNilFields() throws {
        // Insert record (missing fields are nil)
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
            // "optional" field is missing (nil)
        ]))
        
        // Query with nil check
        let results = try db.query()
            .whereNil("optional")
            .execute()
        
        let records = try results.records
        XCTAssertTrue(records.contains { $0.storage["id"]?.uuidValue == id })
    }
    
    func testSpecialCharacters() throws {
        // Insert record with special characters
        let specialString = "Test\n\t\r\"'\\\0\u{0000}"
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "special": .string(specialString)
        ]))
        
        // Query should work
        let results = try db.query()
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        if case .string(let value) = records.first?.storage["special"] {
            XCTAssertEqual(value, specialString)
        } else {
            XCTFail("Special string not preserved")
        }
    }
    
    func testUnicodeFields() throws {
        // Insert record with unicode
        let unicodeString = "测试 🚀 日本語"
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "unicode": .string(unicodeString)
        ]))
        
        // Query should work
        let results = try db.query()
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        if case .string(let value) = records.first?.storage["unicode"] {
            XCTAssertEqual(value, unicodeString)
        } else {
            XCTFail("Unicode string not preserved")
        }
    }
}

