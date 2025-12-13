//
//  ComprehensiveFeatureTests.swift
//  BlazeDBTests
//
//  Integration tests for all features working together
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class ComprehensiveFeatureTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_comprehensive_\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "TestComprehensive", fileURL: tempURL, password: "ComprehensiveFeatureTest123!")
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
    
    func testLazyDecodingWithProjection() throws {
        // Enable lazy decoding
        try db.enableLazyDecoding()
        
        // Insert large record (reduced size to fit within page limit with field table overhead)
        // Field table adds ~100-200 bytes, so we use 3500 bytes to stay under 4046 byte limit
        let largeData = Data(repeating: 0xFF, count: 3_500)
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(largeData)
        ]))
        
        // Query with projection (should use lazy decoding)
        let results = try db.query()
            .project("id", "name")
            .where("id", equals: .uuid(id))
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertNotNil(records.first?.storage["name"])
        // largeData should not be decoded
    }
    
    func testVectorAndSpatialHybrid() throws {
        // Enable both indexes
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert records with both vector and spatial data
        let vector: VectorEmbedding = [0.1, 0.2, 0.3]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let id = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "latitude": .double(37.7749),
            "longitude": .double(-122.4194),
            "embedding": .data(vectorData)
        ]))
        
        // Query with both vector and spatial
        let results = try db.query()
            .vectorAndSpatial(
                vectorField: "embedding",
                vectorEmbedding: vector,
                latitude: 37.7749,
                longitude: -122.4194,
                radiusMeters: 1000
            )
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.storage["id"]?.uuidValue, id)
    }
    
    func testTriggersWithLazyDecoding() throws {
        // Enable lazy decoding
        try db.enableLazyDecoding()
        
        // Set up trigger
        var triggerFired = false
        db.onInsert { record, modified, ctx in
            triggerFired = true
            // Access fields (should work with lazy decoding)
            _ = record.storage["name"]
        }
        
        // Insert record
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ]))
        
        XCTAssertTrue(triggerFired)
    }
    
    func testQueryPlannerWithMultipleIndexes() throws {
        // Enable multiple indexes
        try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Insert records with vectors and locations
        var insertedIds: [UUID] = []
        for i in 0..<100 {
            let vector: VectorEmbedding = [Float(i) * 0.01, Float(i) * 0.02]
            let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
            
            let id = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "latitude": .double(37.7749 + Double(i) * 0.001),
                "longitude": .double(-122.4194 + Double(i) * 0.001),
                "embedding": .data(vectorData)
            ]))
            insertedIds.append(id)
        }
        
        // Query that uses planner - use a vector that should match multiple records
        // Use [0.5, 1.0] which matches record i=50, and also has high similarity with nearby vectors
        // Record i=50 is at (37.7749 + 0.05, -122.4194 + 0.05) ≈ 5.5km from center
        // Increase radius to 10000m to ensure it's included
        let queryVector: VectorEmbedding = [0.5, 1.0]  // Matches record i=50 exactly
        let results = try db.query()
            .vectorAndSpatial(
                vectorField: "embedding",
                vectorEmbedding: queryVector,
                latitude: 37.7749,
                longitude: -122.4194,
                radiusMeters: 10000,  // 10km radius to include record i=50
                vectorLimit: 100,      // Get top 100 vector matches
                vectorThreshold: 0.0   // No minimum threshold - accept all matches
            )
            .execute()
        
        // Planner should choose optimal strategy
        let records = try results.records
        
        // Debug: Check if we got any results
        if records.count == 0 {
            // Try just vector search to see if that works
            let vectorOnlyResults = try db.query()
                .vectorNearest(field: "embedding", to: queryVector, limit: 100, threshold: 0.0)
                .execute()
            let vectorOnlyRecords = try vectorOnlyResults.records
            print("DEBUG: Vector-only search found \(vectorOnlyRecords.count) records")
            
            // Try just spatial search
            let spatialOnlyResults = try db.query()
                .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 10000)
                .execute()
            let spatialOnlyRecords = try spatialOnlyResults.records
            print("DEBUG: Spatial-only search found \(spatialOnlyRecords.count) records")
            
            // Check spatial index stats
            if let stats = db.getSpatialIndexStats() {
                print("DEBUG: Spatial index stats - total records: \(stats.totalRecords)")
            } else {
                print("DEBUG: Spatial index stats are nil")
            }
            
            // Check if spatial index exists
            if let collection = db.collection as? DynamicCollection {
                print("DEBUG: Spatial index exists: \(collection.spatialIndex != nil)")
                print("DEBUG: Cached spatial indexed fields: \(collection.cachedSpatialIndexedFields != nil)")
            }
        }
        
        XCTAssertGreaterThan(records.count, 0, "Should find at least one record matching both vector and spatial criteria")
    }
    
    func testEventTriggersWithVectorIndex() throws {
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        // Set up trigger that uses vector index
        var triggerFired = false
        db.onInsert { record, modified, ctx in
            triggerFired = true
            // Trigger can access vector index
            let stats = try? self.db.getVectorIndexStats()
            XCTAssertNotNil(stats)
        }
        
        // Insert record with vector
        let vector: VectorEmbedding = [0.1, 0.2, 0.3]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .data(vectorData)
        ]))
        
        XCTAssertTrue(triggerFired)
    }
}

