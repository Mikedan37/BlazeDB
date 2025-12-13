//
//  QueryCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for query engine using dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class QueryCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    var collection: DynamicCollection!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "QueryCodecTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        collection = client.collection
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Filter Tests
    
    func testFilter_DualCodec() throws {
        // Insert test data
        var records: [BlazeDataRecord] = []
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "count": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ])
            records.append(record)
            _ = try client.insert(record)
        }
        
        // Query with filter
        let queryResult = try client.query()
            .where("status", equals: .string("active"))
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 50)
        
        // Verify all results match filter
        for result in results {
            XCTAssertEqual(result.storage["status"]?.stringValue, "active")
            
            // Verify record matches original
            if let id = result.storage["id"]?.uuidValue {
                if let originalIndex = records.firstIndex(where: { $0.storage["id"]?.uuidValue == id }) {
                    assertRecordsEqual(records[originalIndex], result)
                }
            }
        }
    }
    
    // MARK: - Sort Tests
    
    func testSort_DualCodec() throws {
        // Insert test data
        var records: [BlazeDataRecord] = []
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "order": .int(100 - i) // Reverse order
            ])
            records.append(record)
            _ = try client.insert(record)
        }
        
        // Query with sort
        let queryResult = try client.query()
            .orderBy("order", descending: false)
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 100)
        
        // Verify sorted order
        for i in 0..<results.count - 1 {
            let current = results[i].storage["order"]?.intValue ?? 0
            let next = results[i + 1].storage["order"]?.intValue ?? 0
            XCTAssertLessThanOrEqual(current, next)
        }
    }
    
    // MARK: - Range Tests
    
    func testRange_DualCodec() throws {
        // Insert test data
        var records: [BlazeDataRecord] = []
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ])
            records.append(record)
            _ = try client.insert(record)
        }
        
        // Query with range
        let queryResult = try client.query()
            .where("value", greaterThanOrEqual: .int(10))
            .where("value", lessThanOrEqual: .int(20))
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 11) // 10 through 20 inclusive
        
        // Verify all results are in range
        for result in results {
            let value = result.storage["value"]?.intValue ?? -1
            XCTAssertGreaterThanOrEqual(value, 10)
            XCTAssertLessThanOrEqual(value, 20)
        }
    }
    
    // MARK: - Full-Text Search Tests
    
    func testFullTextSearch_DualCodec() throws {
        // Insert test data
        let record1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "content": .string("Swift programming language")
        ])
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "content": .string("Python programming language")
        ])
        let record3 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "content": .string("JavaScript web development")
        ])
        
        let id1 = try client.insert(record1)
        let id2 = try client.insert(record2)
        let id3 = try client.insert(record3)
        
        // Full-text search using query
        let queryResult = try client.query()
            .where("content", contains: "programming")
            .execute()
        let results = try queryResult.records
        
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id1 }))
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id2 }))
        XCTAssertFalse(results.contains(where: { $0.storage["id"]?.uuidValue == id3 }))
        
        // Verify results match
        let fetched1 = try client.fetch(id: id1)
        let fetched2 = try client.fetch(id: id2)
        
        XCTAssertNotNil(fetched1)
        XCTAssertNotNil(fetched2)
        if let fetched1 = fetched1, let fetched2 = fetched2 {
            XCTAssertEqual(record1.storage, fetched1.storage)
            XCTAssertEqual(record2.storage, fetched2.storage)
        }
    }
    
    // MARK: - Prefix Search Tests
    
    func testPrefixSearch_DualCodec() throws {
        // Insert test data
        var records: [BlazeDataRecord] = []
        for prefix in ["apple", "application", "apply", "banana", "band"] {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "word": .string(prefix)
            ])
            records.append(record)
            _ = try client.insert(record)
        }
        
        // Prefix search using custom filter
        let queryResult = try client.query()
            .where { record in
                guard let word = record.storage["word"]?.stringValue else { return false }
                return word.hasPrefix("app")
            }
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 3) // apple, application, apply
        
        // Verify all results match prefix
        for result in results {
            let word = result.storage["word"]?.stringValue ?? ""
            XCTAssertTrue(word.hasPrefix("app"))
        }
    }
    
    // MARK: - Tag Search Tests
    
    func testTagSearch_DualCodec() throws {
        // Insert test data
        let record1 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "tags": .array([.string("swift"), .string("ios")])
        ])
        let record2 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "tags": .array([.string("swift"), .string("server")])
        ])
        let record3 = BlazeDataRecord([
            "id": .uuid(UUID()),
            "tags": .array([.string("python"), .string("server")])
        ])
        
        let id1 = try client.insert(record1)
        let id2 = try client.insert(record2)
        let id3 = try client.insert(record3)
        
        // Tag search - find records where tags array contains "swift"
        let queryResult = try client.query()
            .where { record in
                guard case .array(let tags) = record.storage["tags"] else { return false }
                return tags.contains(.string("swift"))
            }
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id1 }))
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id2 }))
        XCTAssertFalse(results.contains(where: { $0.storage["id"]?.uuidValue == id3 }))
    }
    
    // MARK: - Complex Query Tests
    
    func testComplexQuery_DualCodec() throws {
        // Insert test data
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "category": .string(i < 50 ? "A" : "B"),
                "price": .double(Double(i)),
                "active": .bool(i % 2 == 0)
            ])
            _ = try client.insert(record)
        }
        
        // Complex query: category A, price > 20, active = true
        let queryResult = try client.query()
            .where("category", equals: .string("A"))
            .where("price", greaterThan: .double(20.0))
            .where("active", equals: .bool(true))
            .orderBy("price", descending: false)
            .execute()
        let results = try queryResult.records
        
        // Verify results
        for result in results {
            XCTAssertEqual(result.storage["category"]?.stringValue, "A")
            XCTAssertGreaterThan(result.storage["price"]?.doubleValue ?? -1, 20.0)
            XCTAssertEqual(result.storage["active"]?.boolValue, true)
        }
    }
}

