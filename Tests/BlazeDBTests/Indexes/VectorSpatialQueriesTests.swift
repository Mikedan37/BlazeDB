//
//  VectorSpatialQueriesTests.swift
//  BlazeDBTests
//
//  Tests for vector + spatial combined queries
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class VectorSpatialQueriesTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.vector.spatial.blazedb")
        do {
            db = try BlazeDBClient(name: "TestVectorSpatial", fileURL: dbURL, password: "VectorSpatialTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
        try! db.enableSpatialIndex(on: "latitude", lonField: "longitude")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testVectorNearest() throws {
        // Create vector embedding
        let embedding: VectorEmbedding = [0.1, 0.2, 0.3, 0.4]
        let embeddingData = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
        
        // Insert record with vector
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "text": .string("I feel anxious"),
            "moodEmbedding": .data(embeddingData)
        ]))
        
        // Query with vector similarity
        let results = try db.query()
            .vectorNearest(field: "moodEmbedding", to: embedding, limit: 10)
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Should find similar records")
    }
    
    func testVectorAndSpatial() throws {
        // Create vector embedding
        let embedding: VectorEmbedding = [0.1, 0.2, 0.3]
        let embeddingData = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
        
        // Insert record with vector and location
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "text": .string("Anxious at gym"),
            "moodEmbedding": .data(embeddingData),
            "latitude": .double(37.7750),
            "longitude": .double(-122.4195)
        ]))
        
        // Combined vector + spatial query
        let results = try db.query()
            .vectorAndSpatial(
                vectorField: "moodEmbedding",
                vectorEmbedding: embedding,
                latitude: 37.7749,
                longitude: -122.4194,
                radiusMeters: 2000
            )
            .execute()
        
        let records = try results.records
        XCTAssertGreaterThan(records.count, 0, "Should find records matching both criteria")
    }
}

