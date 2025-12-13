//
//  VectorIndexIntegrationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for vector index integration
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class VectorIndexIntegrationTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_vector_\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "TestVector", fileURL: tempURL, password: "VectorIndexTest123!")
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
    
    func testEnableVectorIndex() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Verify index exists
        XCTAssertNotNil(db.collection.vectorIndex)
        XCTAssertEqual(db.collection.cachedVectorIndexedField, "embedding")
    }
    
    func testVectorIndexOnInsert() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert record with vector
        let vector: VectorEmbedding = [0.1, 0.2, 0.3, 0.4, 0.5]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "embedding": .data(vectorData)
        ])
        
        let id = try db.insert(record)
        
        // Verify vector is in index
        let stats = db.getVectorIndexStats()
        XCTAssertEqual(stats?.totalVectors, 1)
        
        // Query using vector index
        let results = try db.query()
            .vectorNearest(field: "embedding", to: vector, limit: 10)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.storage["id"]?.uuidValue, id)
    }
    
    func testVectorIndexOnUpdate() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert record
        let vector1: VectorEmbedding = [0.1, 0.2, 0.3]
        let vectorData1 = vector1.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .data(vectorData1)
        ]))
        
        // Update with new vector
        let vector2: VectorEmbedding = [0.4, 0.5, 0.6]
        let vectorData2 = vector2.withUnsafeBufferPointer { Data(buffer: $0) }
        
        try db.update(id: id, with: BlazeDataRecord(["embedding": .data(vectorData2)]))
        
        // Query with new vector
        let results = try db.query()
            .vectorNearest(field: "embedding", to: vector2, limit: 10)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
    }
    
    func testVectorIndexOnDelete() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert record
        let vector: VectorEmbedding = [0.1, 0.2, 0.3]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .data(vectorData)
        ]))
        
        // Delete record
        try db.delete(id: id)
        
        // Verify vector removed from index
        let stats = db.getVectorIndexStats()
        XCTAssertEqual(stats?.totalVectors, 0)
    }
    
    func testVectorIndexPersistence() throws {
        // Enable vector index and insert records
        try db.enableVectorIndex(fieldName: "embedding")
        
        for i in 0..<10 {
            let vector: VectorEmbedding = [Float(i) * 0.1, Float(i) * 0.2, Float(i) * 0.3]
            let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "embedding": .data(vectorData)
            ]))
        }
        
        // Close and reopen
        let metaURL = db.collection.metaURLPath
        db = nil
        
        db = try BlazeDBClient(name: "TestVector", fileURL: tempURL, password: "VectorIndexTest123!")
        
        // Verify vector index field is preserved
        XCTAssertEqual(db.collection.cachedVectorIndexedField, "embedding")
        
        // Rebuild index
        try db.rebuildVectorIndex()
        
        // Verify index has vectors
        let stats = db.getVectorIndexStats()
        XCTAssertEqual(stats?.totalVectors, 10)
    }
    
    func testVectorIndexPerformance() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert 1000 records
        let startTime = Date()
        for i in 0..<1000 {
            let vector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
            let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "embedding": .data(vectorData)
            ]))
        }
        let insertTime = Date().timeIntervalSince(startTime)
        print("Inserted 1000 vectors in \(insertTime * 1000)ms")
        
        // Query using vector index
        let queryVector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
        let queryStart = Date()
        let results = try db.query()
            .vectorNearest(field: "embedding", to: queryVector, limit: 10)
            .execute()
        let queryTime = Date().timeIntervalSince(queryStart)
        
        let records = try results.records
        print("Vector query (indexed) took \(queryTime * 1000)ms, found \(records.count) results")
        XCTAssertLessThan(queryTime, 1.0)  // Should be fast with index
        XCTAssertGreaterThan(records.count, 0)  // Should find some results
    }
}

