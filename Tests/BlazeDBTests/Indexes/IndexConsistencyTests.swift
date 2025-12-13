//
//  IndexConsistencyTests.swift
//  BlazeDBTests
//
//  Index Consistency Tests: Verify consistency across primary index, secondary indexes,
//  full-text indexes, spatial indexes, ordering indexes, and vector indexes.
//  For each operation: Insert → index.has(id) must be true,
//  Delete → index.has(id) must be false,
//  Update → index reflects new fields,
//  Move ordering → ordering index sorted and stable.
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class IndexConsistencyTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexConsistency-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "index_consistency_test_\(testID)", fileURL: tempURL, password: "IndexConsistencyTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Primary Index Consistency
    
    func testPrimaryIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Primary Index - Insert")
        
        let collection = db.collection as! DynamicCollection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Primary index (indexMap) should contain the ID
        XCTAssertTrue(collection.indexMap.keys.contains(id), "Primary index should contain inserted ID")
        
        print("  ✅ Primary index consistent after insert")
    }
    
    func testPrimaryIndex_Delete() throws {
        print("\n🔍 INDEX CONSISTENCY: Primary Index - Delete")
        
        let collection = db.collection as! DynamicCollection
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        // Verify in index
        XCTAssertTrue(collection.indexMap.keys.contains(id), "Primary index should contain ID before delete")
        
        // Delete
        try db.delete(id: id)
        
        // Verify removed from index
        XCTAssertFalse(collection.indexMap.keys.contains(id), "Primary index should not contain deleted ID")
        
        print("  ✅ Primary index consistent after delete")
    }
    
    // MARK: - Secondary Index Consistency
    
    func testSecondaryIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Secondary Index - Insert")
        
        let collection = db.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "status")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("active")
        ])
        let id = try db.insert(record)
        
        // Verify in secondary index
        let indexed = try collection.fetch(byIndexedField: "status", value: "active")
        let indexedIDs = Set(indexed.compactMap { $0.storage["id"]?.uuidValue })
        
        XCTAssertTrue(indexedIDs.contains(id), "Secondary index should contain inserted ID")
        
        print("  ✅ Secondary index consistent after insert")
    }
    
    func testSecondaryIndex_Update() throws {
        print("\n🔍 INDEX CONSISTENCY: Secondary Index - Update")
        
        let collection = db.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "status")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("pending")
        ])
        let id = try db.insert(record)
        
        // Update status
        try db.update(id: id, with: BlazeDataRecord(["status": .string("done")]))
        
        // Verify old value removed, new value added
        let pending = try collection.fetch(byIndexedField: "status", value: "pending")
        let done = try collection.fetch(byIndexedField: "status", value: "done")
        
        let pendingIDs = Set(pending.compactMap { $0.storage["id"]?.uuidValue })
        let doneIDs = Set(done.compactMap { $0.storage["id"]?.uuidValue })
        
        XCTAssertFalse(pendingIDs.contains(id), "Old index entry should be removed")
        XCTAssertTrue(doneIDs.contains(id), "New index entry should exist")
        
        print("  ✅ Secondary index consistent after update")
    }
    
    func testSecondaryIndex_Delete() throws {
        print("\n🔍 INDEX CONSISTENCY: Secondary Index - Delete")
        
        let collection = db.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "category")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "category": .string("important")
        ])
        let id = try db.insert(record)
        
        // Verify in index
        let before = try collection.fetch(byIndexedField: "category", value: "important")
        let beforeIDs = Set(before.compactMap { $0.storage["id"]?.uuidValue })
        XCTAssertTrue(beforeIDs.contains(id), "Index should contain ID before delete")
        
        // Delete
        try db.delete(id: id)
        
        // Verify removed from index
        let after = try collection.fetch(byIndexedField: "category", value: "important")
        let afterIDs = Set(after.compactMap { $0.storage["id"]?.uuidValue })
        XCTAssertFalse(afterIDs.contains(id), "Index should not contain deleted ID")
        
        print("  ✅ Secondary index consistent after delete")
    }
    
    // MARK: - Full-Text Index Consistency
    
    func testFullTextIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Full-Text Index - Insert")
        
        let collection = db.collection as! DynamicCollection
        
        // Enable full-text search
        try collection.enableSearch(on: ["title"])
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("BlazeDB is fast")
        ])
        let id = try db.insert(record)
        
        // Verify searchable
        let searchResults = try db.query()
            .search("BlazeDB", in: ["title"])
        
        let resultIDs = Set(searchResults.compactMap { $0.record.storage["id"]?.uuidValue })
        XCTAssertTrue(resultIDs.contains(id), "Full-text index should contain inserted record")
        
        print("  ✅ Full-text index consistent after insert")
    }
    
    func testFullTextIndex_Update() throws {
        print("\n🔍 INDEX CONSISTENCY: Full-Text Index - Update")
        
        let collection = db.collection as! DynamicCollection
        
        // Enable full-text search
        try collection.enableSearch(on: ["title"])
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "title": .string("Old title")
        ])
        let id = try db.insert(record)
        
        // Update title
        try db.update(id: id, with: BlazeDataRecord(["title": .string("New title")]))
        
        // Verify old text removed, new text searchable
        let oldSearchResults = try db.query()
            .search("Old", in: ["title"])
        let newSearchResults = try db.query()
            .search("New", in: ["title"])
        
        let oldIDs = Set(oldSearchResults.compactMap { $0.record.storage["id"]?.uuidValue })
        let newIDs = Set(newSearchResults.compactMap { $0.record.storage["id"]?.uuidValue })
        
        XCTAssertFalse(oldIDs.contains(id), "Old text should not be searchable")
        XCTAssertTrue(newIDs.contains(id), "New text should be searchable")
        
        print("  ✅ Full-text index consistent after update")
    }
    
    // MARK: - Spatial Index Consistency
    
    func testSpatialIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Spatial Index - Insert")
        
        // Enable spatial index
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "lat": .double(37.7749),
            "lon": .double(-122.4194)
        ])
        let id = try db.insert(record)
        
        // Verify spatial query works
        let results = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
            .execute()
        
        let records = try results.records
        let resultIDs = Set(records.compactMap { $0.storage["id"]?.uuidValue })
        XCTAssertTrue(resultIDs.contains(id), "Spatial index should contain inserted record")
        
        print("  ✅ Spatial index consistent after insert")
    }
    
    func testSpatialIndex_Update() throws {
        print("\n🔍 INDEX CONSISTENCY: Spatial Index - Update")
        
        // Enable spatial index
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "lat": .double(37.7749),
            "lon": .double(-122.4194)
        ])
        let id = try db.insert(record)
        
        // Update location
        try db.update(id: id, with: BlazeDataRecord([
            "lat": .double(40.7128),
            "lon": .double(-74.0060)
        ]))
        
        // Verify old location removed, new location searchable
        let oldResults = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
            .execute()
        let newResults = try db.query()
            .withinRadius(latitude: 40.7128, longitude: -74.0060, radiusMeters: 1000)
            .execute()
        
        let oldRecords = try oldResults.records
        let newRecords = try newResults.records
        let oldIDs = Set(oldRecords.compactMap { $0.storage["id"]?.uuidValue })
        let newIDs = Set(newRecords.compactMap { $0.storage["id"]?.uuidValue })
        
        XCTAssertFalse(oldIDs.contains(id), "Old location should not be in spatial index")
        XCTAssertTrue(newIDs.contains(id), "New location should be in spatial index")
        
        print("  ✅ Spatial index consistent after update")
    }
    
    // MARK: - Vector Index Consistency
    
    func testVectorIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Vector Index - Insert")
        
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        let vector: VectorEmbedding = [0.1, 0.2, 0.3, 0.4, 0.5]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .data(vectorData)
        ])
        let id = try db.insert(record)
        
        // Verify vector index stats
        let stats = db.getVectorIndexStats()
        XCTAssertNotNil(stats, "Vector index should exist")
        XCTAssertGreaterThanOrEqual(stats?.totalVectors ?? 0, 1, "Vector index should contain inserted vector")
        
        print("  ✅ Vector index consistent after insert")
    }
    
    func testVectorIndex_Delete() throws {
        print("\n🔍 INDEX CONSISTENCY: Vector Index - Delete")
        
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        let vector: VectorEmbedding = [0.1, 0.2, 0.3]
        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "embedding": .data(vectorData)
        ])
        let id = try db.insert(record)
        
        // Get initial count
        let beforeStats = db.getVectorIndexStats()
        let beforeCount = beforeStats?.totalVectors ?? 0
        
        // Delete
        try db.delete(id: id)
        
        // Verify removed from index
        let afterStats = db.getVectorIndexStats()
        let afterCount = afterStats?.totalVectors ?? 0
        
        XCTAssertEqual(afterCount, beforeCount - 1, "Vector index should have one less vector after delete")
        
        print("  ✅ Vector index consistent after delete")
    }
    
    // MARK: - Ordering Index Consistency
    
    func testOrderingIndex_Insert() throws {
        print("\n🔍 INDEX CONSISTENCY: Ordering Index - Insert")
        
        // Enable ordering
        try db.enableOrdering(fieldName: "orderingIndex")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "orderingIndex": .double(100.0),
            "name": .string("Item 1")
        ])
        let id = try db.insert(record)
        
        // Verify ordering works
        let results = try db.query()
            .orderBy("orderingIndex", descending: false)
            .execute()
        
        let records = try results.records
        let resultIDs = records.compactMap { $0.storage["id"]?.uuidValue }
        XCTAssertTrue(resultIDs.contains(id), "Ordering index should contain inserted record")
        
        print("  ✅ Ordering index consistent after insert")
    }
    
    func testOrderingIndex_Move() throws {
        print("\n🔍 INDEX CONSISTENCY: Ordering Index - Move")
        
        // Enable ordering
        try db.enableOrdering(fieldName: "orderingIndex")
        
        // Insert records
        let id1 = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "orderingIndex": .double(100.0),
            "name": .string("Item 1")
        ]))
        let id2 = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "orderingIndex": .double(200.0),
            "name": .string("Item 2")
        ]))
        
        // Move id2 before id1
        try db.moveBefore(recordId: id2, beforeId: id1)
        
        // Verify ordering
        let results = try db.query()
            .orderBy("orderingIndex", descending: false)
            .execute()
        
        let records = try results.records
        let resultIDs = records.compactMap { $0.storage["id"]?.uuidValue }
        let index1 = resultIDs.firstIndex(of: id1)!
        let index2 = resultIDs.firstIndex(of: id2)!
        
        XCTAssertLessThan(index2, index1, "id2 should come before id1 after move")
        
        print("  ✅ Ordering index consistent after move")
    }
    
    // MARK: - Cross-Index Validation
    
    func testCrossIndex_AllIndexesMatch() throws {
        print("\n🔍 INDEX CONSISTENCY: Cross-Index Validation")
        
        let collection = db.collection as! DynamicCollection
        
        // Create multiple indexes
        try collection.createIndex(on: "status")
        try collection.enableSearch(on: ["title"])
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("active"),
            "title": .string("Test Record"),
            "lat": .double(37.7749),
            "lon": .double(-122.4194)
        ])
        let id = try db.insert(record)
        
        // Verify all indexes contain the record
        let secondaryResults = try collection.fetch(byIndexedField: "status", value: "active")
        let searchResults = try db.query()
            .search("Test", in: ["title"])
        let spatialResults = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
            .execute()
        
        let secondaryIDs = Set(secondaryResults.compactMap { $0.storage["id"]?.uuidValue })
        let searchIDs = Set(searchResults.compactMap { $0.record.storage["id"]?.uuidValue })
        let spatialRecords = try spatialResults.records
        let spatialIDs = Set(spatialRecords.compactMap { $0.storage["id"]?.uuidValue })
        
        XCTAssertTrue(secondaryIDs.contains(id), "Secondary index should contain record")
        XCTAssertTrue(searchIDs.contains(id), "Full-text index should contain record")
        XCTAssertTrue(spatialIDs.contains(id), "Spatial index should contain record")
        
        print("  ✅ All indexes consistent with each other")
    }
    
    func testCrossIndex_IndexDriftDetection() throws {
        print("\n🔍 INDEX CONSISTENCY: Index Drift Detection")
        
        let collection = db.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "category")
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<10 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "category": .string("test"),
                "index": .int(i)
            ])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        // Verify all records in index
        let indexed = try collection.fetch(byIndexedField: "category", value: "test")
        let indexedIDs = Set(indexed.compactMap { $0.storage["id"]?.uuidValue })
        let insertedIDs = Set(ids)
        
        XCTAssertEqual(indexedIDs, insertedIDs, "All inserted records should be in index (no drift)")
        
        print("  ✅ No index drift detected")
    }
}

