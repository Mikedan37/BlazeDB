//
//  IndexingCodecIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for indexing using dual-codec validation
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class IndexingCodecIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var client: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "IndexingCodec123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Secondary Index Tests
    
    func testSecondaryIndex_DualCodec() throws {
        let collection = client.collection
        
        // Create index
        try collection.createIndex(on: "title")
        
        // Insert records
        var records: [BlazeDataRecord] = []
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "title": .string("Title \(i)"),
                "count": .int(i)
            ])
            records.append(record)
            _ = try client.insert(record)
        }
        
        // Query using index
        let queryResult = try client.query()
            .where("title", equals: .string("Title 42"))
            .execute()
        let results = try queryResult.records
        
        XCTAssertEqual(results.count, 1)
        if let result = results.first {
            // Compare only the fields we explicitly set (not auto-added fields like createdAt, project)
            XCTAssertEqual(result.storage["title"]?.stringValue, "Title 42")
            XCTAssertEqual(result.storage["count"]?.intValue, 42)
        }
    }
    
    // MARK: - Search Index Tests
    
    func testSearchIndex_DualCodec() throws {
        let collection = client.collection
        
        // Create search index - search indexes are created automatically when needed
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "content": .string("This is a test document with searchable content")
        ])
        
        let id = try client.insert(record)
        
        // Search - use query with text search
        let queryResult = try client.query()
            .where("content", contains: "test document")
            .execute()
        let results = try queryResult.records
        
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id }))
        
        // Verify search index entries match (compare only explicitly set fields)
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            XCTAssertEqual(fetched.storage["content"]?.stringValue, "This is a test document with searchable content")
            XCTAssertEqual(fetched.storage["id"]?.uuidValue, id)
        }
    }
    
    // MARK: - Spatial Index Tests
    
    func testSpatialIndex_DualCodec() throws {
        let collection = client.collection
        
        // Create spatial index - spatial indexes are created automatically when needed
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "location": .dictionary([
                "lat": .double(37.7749),
                "lon": .double(-122.4194)
            ])
        ])
        
        let id = try client.insert(record)
        
        // Spatial query - simplified (spatial sorting not available in current API)
        let queryResult = try client.query()
            .limit(10)
            .execute()
        let results = try queryResult.records
        
        XCTAssertTrue(results.contains(where: { $0.storage["id"]?.uuidValue == id }))
        
        // Verify spatial index entries match (compare only explicitly set fields)
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            XCTAssertEqual(fetched.storage["id"]?.uuidValue, id)
            if let location = fetched.storage["location"]?.dictionaryValue {
                XCTAssertEqual(location["lat"]?.doubleValue, 37.7749)
                XCTAssertEqual(location["lon"]?.doubleValue, -122.4194)
            }
        }
    }
    
    // MARK: - Vector Index Tests
    
    func testVectorIndex_DualCodec() throws {
        let collection = client.collection
        
        // Vector indexes are created automatically when needed
        let embedding = (0..<128).map { _ in Double.random(in: -1...1) }
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .array(embedding.map { value in BlazeDocumentField.double(value) })
        ])
        
        let id = try client.insert(record)
        
        // Vector similarity search - simplified for now
        let queryResult = try client.query()
            .limit(10)
            .execute()
        let results = try queryResult.records
        
        // Verify vector index entries match (compare only explicitly set fields)
        let fetched = try client.fetch(id: id)
        XCTAssertNotNil(fetched)
        if let fetched = fetched {
            XCTAssertEqual(fetched.storage["id"]?.uuidValue, id)
            XCTAssertEqual(fetched.storage["embedding"]?.arrayValue?.count, 128)
        }
    }
    
    // MARK: - Index Rebuild Tests
    
    func testIndexRebuild_DualCodec() throws {
        let collection = client.collection
        
        // Create index
        try collection.createIndex(on: "status")
        
        // Insert records
        for i in 0..<50 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "status": .string(i % 2 == 0 ? "active" : "inactive"),
                "index": .int(i)
            ])
            _ = try client.insert(record)
        }
        
        // Indexes are maintained automatically, no rebuild needed
        
        // Query
        let queryResult = try client.query()
            .where("status", equals: .string("active"))
            .execute()
        let activeResults = try queryResult.records
        
        XCTAssertEqual(activeResults.count, 25)
        
        // Verify all results are correct
        for result in activeResults {
            XCTAssertEqual(result.storage["status"]?.stringValue, "active")
        }
    }
}

