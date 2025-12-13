//
//  QueryOptimizationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for query optimizations:
//  1. Field projection (.project())
//  2. Record caching
//  3. Lazy decoding for large fields
//

import XCTest
@testable import BlazeDB

final class QueryOptimizationTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        RecordCache.shared.clear()  // Clear cache between tests
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Opt-\(testID).blazedb")
        
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "opt_test_\(testID)", fileURL: tempURL, password: "QueryOptimizationTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.persist()
        RecordCache.shared.clear()
        db = nil
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Field Projection Tests
    
    func testFieldProjection_ReturnsOnlySpecifiedFields() throws {
        // Insert record with many fields
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "email": .string("test@example.com"),
            "age": .int(30),
            "status": .string("active"),
            "metadata": .dictionary(["key1": .string("value1"), "key2": .string("value2")]),
            "tags": .array([.string("tag1"), .string("tag2")])
        ]))
        
        // Query with projection
        let result = try db.query()
            .project("id", "name", "status")
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        
        let projected = records.first!
        XCTAssertEqual(projected.storage.count, 3)
        XCTAssertNotNil(projected.storage["id"])
        XCTAssertNotNil(projected.storage["name"])
        XCTAssertNotNil(projected.storage["status"])
        XCTAssertNil(projected.storage["email"])
        XCTAssertNil(projected.storage["age"])
        XCTAssertNil(projected.storage["metadata"])
        XCTAssertNil(projected.storage["tags"])
    }
    
    func testFieldProjection_WithFilters() throws {
        // Insert multiple records
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)"),
                "status": .string(i < 3 ? "active" : "inactive"),
                "value": .int(i * 10)
            ]))
        }
        
        // Query with projection and filter
        let result = try db.query()
            .project("id", "name")
            .where("status", equals: .string("active"))
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 3)
        
        for record in records {
            XCTAssertEqual(record.storage.count, 2)
            XCTAssertNotNil(record.storage["id"])
            XCTAssertNotNil(record.storage["name"])
            XCTAssertNil(record.storage["status"])  // Filtered but not projected
            XCTAssertNil(record.storage["value"])
        }
    }
    
    func testFieldProjection_WithSorting() throws {
        // Insert records
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)"),
                "priority": .int(5 - i)
            ]))
        }
        
        // Query with projection and sorting
        let result = try db.query()
            .project("name", "priority")
            .orderBy("priority", descending: false)
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 5)
        
        // Verify sorted order
        for (index, record) in records.enumerated() {
            XCTAssertEqual(record.storage["priority"]?.intValue, index + 1)
            XCTAssertEqual(record.storage.count, 2)  // Only projected fields
        }
    }
    
    func testFieldProjection_WithLimit() throws {
        // Insert records
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)"),
                "value": .int(i)
            ]))
        }
        
        // Query with projection and limit
        let result = try db.query()
            .project("name")
            .limit(3)
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 3)
        
        for record in records {
            XCTAssertEqual(record.storage.count, 1)  // Only "name"
            XCTAssertNotNil(record.storage["name"])
        }
    }
    
    func testFieldProjection_EmptyProjection() throws {
        // Insert record
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ]))
        
        // Query with empty projection (should return empty records)
        let result = try db.query()
            .project([])
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first!.storage.count, 0)
    }
    
    func testFieldProjection_NonExistentFields() throws {
        // Insert record
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ]))
        
        // Query projecting non-existent fields
        let result = try db.query()
            .project("id", "name", "nonexistent")
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first!.storage.count, 2)  // Only existing fields
        XCTAssertNotNil(records.first!.storage["id"])
        XCTAssertNotNil(records.first!.storage["name"])
        XCTAssertNil(records.first!.storage["nonexistent"])
    }
    
    // MARK: - Record Caching Tests
    
    func testRecordCache_CachesDecodedRecords() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Cached Record"),
            "value": .int(42)
        ]))
        
        // First fetch (cache miss)
        let stats1 = RecordCache.shared.getStats()
        let record1 = try db.fetch(id: recordID)
        XCTAssertNotNil(record1)
        
        let stats2 = RecordCache.shared.getStats()
        XCTAssertEqual(stats2.misses, stats1.misses + 1)
        
        // Second fetch (cache hit)
        let record2 = try db.fetch(id: recordID)
        XCTAssertNotNil(record2)
        XCTAssertEqual(record1?.storage, record2?.storage)
        
        let stats3 = RecordCache.shared.getStats()
        XCTAssertEqual(stats3.hits, stats2.hits + 1)
        XCTAssertGreaterThan(stats3.hitRate, 0.0)
    }
    
    func testRecordCache_InvalidatesOnUpdate() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Original")
        ]))
        
        // Fetch (caches record)
        _ = try db.fetch(id: recordID)
        let stats1 = RecordCache.shared.getStats()
        XCTAssertEqual(stats1.size, 1)
        
        // Update record
        try db.update(id: recordID, with: BlazeDataRecord([
            "name": .string("Updated")
        ]))
        
        // Cache should be invalidated
        let stats2 = RecordCache.shared.getStats()
        XCTAssertEqual(stats2.size, 0)  // Cache cleared
        
        // Fetch again (should get updated value)
        let record = try db.fetch(id: recordID)
        XCTAssertEqual(record?.storage["name"]?.stringValue, "Updated")
    }
    
    func testRecordCache_InvalidatesOnDelete() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("To Delete")
        ]))
        
        // Fetch (caches record)
        _ = try db.fetch(id: recordID)
        let stats1 = RecordCache.shared.getStats()
        XCTAssertEqual(stats1.size, 1)
        
        // Delete record
        try db.delete(id: recordID)
        
        // Cache should be invalidated
        let stats2 = RecordCache.shared.getStats()
        XCTAssertEqual(stats2.size, 0)
        
        // Fetch should return nil
        let record = try db.fetch(id: recordID)
        XCTAssertNil(record)
    }
    
    func testRecordCache_ExpiresOldEntries() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Expiring")
        ]))
        
        // Set short max age
        RecordCache.shared.setMaxAge(0.1)  // 100ms
        
        // Fetch (caches record)
        _ = try db.fetch(id: recordID)
        let stats1 = RecordCache.shared.getStats()
        XCTAssertEqual(stats1.size, 1)
        
        // Wait for expiration
        Thread.sleep(forTimeInterval: 0.2)
        
        // Fetch again (should be cache miss due to expiration)
        _ = try db.fetch(id: recordID)
        let stats2 = RecordCache.shared.getStats()
        XCTAssertGreaterThan(stats2.misses, stats1.misses)
    }
    
    func testRecordCache_EvictsWhenFull() throws {
        // Set small cache size
        RecordCache.shared.setMaxSize(3)
        
        // Insert and fetch 5 records
        var recordIDs: [UUID] = []
        for i in 0..<5 {
            let id = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)")
            ]))
            recordIDs.append(id)
            _ = try db.fetch(id: id)
        }
        
        // Cache should only have 3 records (evicted oldest)
        let stats = RecordCache.shared.getStats()
        XCTAssertLessThanOrEqual(stats.size, 3)
        XCTAssertGreaterThan(stats.evictions, 0)
    }
    
    func testRecordCache_Statistics() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Stats Test")
        ]))
        
        // Multiple fetches
        for _ in 0..<5 {
            _ = try db.fetch(id: recordID)
        }
        
        let stats = RecordCache.shared.getStats()
        XCTAssertGreaterThan(stats.hits, 0)
        XCTAssertGreaterThan(stats.hitRate, 0.0)
        XCTAssertLessThanOrEqual(stats.hitRate, 1.0)
    }
    
    // MARK: - Lazy Field Decoding Tests
    
    func testLazyFieldRecord_DecodesSmallFieldsImmediately() throws {
        let smallData = Data(repeating: 0x42, count: 100)  // 100 bytes (small)
        let largeData = Data(repeating: 0x99, count: 5000)  // 5KB (large)
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "smallData": .data(smallData),
            "largeData": .data(largeData)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let lazyRecord = try LazyFieldRecord(encodedData: encoded, fieldSizeThreshold: 1024)
        
        // Small fields should be decoded immediately
        XCTAssertNotNil(lazyRecord["id"])
        XCTAssertNotNil(lazyRecord["name"])
        XCTAssertNotNil(lazyRecord["smallData"])
        
        // Large field should be lazy
        XCTAssertTrue(lazyRecord.isLazy(field: "largeData"))
    }
    
    func testLazyFieldRecord_DecodesLargeFieldsOnDemand() throws {
        let largeData = Data(repeating: 0x99, count: 5000)
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(largeData)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let lazyRecord = try LazyFieldRecord(encodedData: encoded, fieldSizeThreshold: 1024)
        
        // Large field should be lazy initially
        XCTAssertTrue(lazyRecord.isLazy(field: "largeData"))
        
        // Access large field (triggers decode)
        let decoded = lazyRecord["largeData"]
        XCTAssertNotNil(decoded)
        
        // Should no longer be lazy
        XCTAssertFalse(lazyRecord.isLazy(field: "largeData"))
        
        // Verify data matches
        if case .data(let data) = decoded! {
            XCTAssertEqual(data, largeData)
        } else {
            XCTFail("Expected data field")
        }
    }
    
    func testLazyFieldRecord_AllFieldsDecodesEverything() throws {
        let largeData = Data(repeating: 0x99, count: 5000)
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(largeData)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let lazyRecord = try LazyFieldRecord(encodedData: encoded, fieldSizeThreshold: 1024)
        
        // Get all fields (forces decode of lazy fields)
        let allFields = try lazyRecord.allFields()
        
        XCTAssertEqual(allFields.count, 3)
        XCTAssertNotNil(allFields["id"])
        XCTAssertNotNil(allFields["name"])
        XCTAssertNotNil(allFields["largeData"])
        
        // Should no longer be lazy
        XCTAssertFalse(lazyRecord.isLazy(field: "largeData"))
    }
    
    func testLazyFieldRecord_ToRecordDecodesEverything() throws {
        let largeData = Data(repeating: 0x99, count: 5000)
        
        let originalRecord = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(largeData)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(originalRecord)
        let lazyRecord = try LazyFieldRecord(encodedData: encoded, fieldSizeThreshold: 1024)
        
        // Convert to full record
        let fullRecord = try lazyRecord.toRecord()
        
        XCTAssertEqual(fullRecord.storage.count, 3)
        XCTAssertEqual(fullRecord.storage["id"], originalRecord.storage["id"])
        XCTAssertEqual(fullRecord.storage["name"], originalRecord.storage["name"])
        XCTAssertEqual(fullRecord.storage["largeData"], originalRecord.storage["largeData"])
    }
    
    func testLazyFieldRecord_LargeStringFields() throws {
        let largeString = String(repeating: "A", count: 5000)  // 5KB string
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeText": .string(largeString)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let lazyRecord = try LazyFieldRecord(encodedData: encoded, fieldSizeThreshold: 1024)
        
        // Large string should be lazy
        XCTAssertTrue(lazyRecord.isLazy(field: "largeText"))
        
        // Access it
        let decoded = lazyRecord["largeText"]
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.stringValue, largeString)
    }
    
    // MARK: - Integration Tests
    
    func testProjectionWithCaching() throws {
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "email": .string("test@example.com"),
            "metadata": .dictionary(["key": .string("value")])
        ]))
        
        // First query with projection
        let result1 = try db.query()
            .project("id", "name")
            .where("id", equals: .uuid(recordID))
            .execute()
        
        let records1 = try result1.records
        XCTAssertEqual(records1.first!.storage.count, 2)
        
        // Second query (should use cache, but still project)
        let result2 = try db.query()
            .project("id", "name")
            .where("id", equals: .uuid(recordID))
            .execute()
        
        let records2 = try result2.records
        XCTAssertEqual(records2.first!.storage.count, 2)
        
        // Verify cache was used
        let stats = RecordCache.shared.getStats()
        XCTAssertGreaterThan(stats.hits, 0)
    }
    
    func testLazyFieldsWithProjection() throws {
        let largeData = Data(repeating: 0x99, count: 5000)
        
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "largeData": .data(largeData)
        ]))
        
        // Query with projection (excludes large field)
        let result = try db.query()
            .project("id", "name")
            .where("id", equals: .uuid(recordID))
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.first!.storage.count, 2)
        XCTAssertNil(records.first!.storage["largeData"])
    }
    
    func testAllOptimizationsTogether() throws {
        let largeData = Data(repeating: 0x99, count: 5000)
        
        // Insert records
        var recordIDs: [UUID] = []
        for i in 0..<10 {
            let id = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("Record \(i)"),
                "status": .string(i < 5 ? "active" : "inactive"),
                "largeData": .data(largeData)
            ]))
            recordIDs.append(id)
        }
        
        // Query with projection, filter, and sorting
        // This should use cache for repeated fetches and projection for memory efficiency
        let result = try db.query()
            .project("id", "name", "status")
            .where("status", equals: .string("active"))
            .orderBy("name", descending: false)
            .limit(5)
            .execute()
        
        let records = try result.records
        XCTAssertEqual(records.count, 5)
        
        // Verify projection
        for record in records {
            XCTAssertEqual(record.storage.count, 3)
            XCTAssertNil(record.storage["largeData"])  // Not projected
        }
        
        // Verify cache was used
        let stats = RecordCache.shared.getStats()
        XCTAssertGreaterThan(stats.hits + stats.misses, 0)
    }
    
    func testProjectionPerformance_MemoryReduction() throws {
        // Insert record with many fields
        let recordID = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "field1": .string("Value 1"),
            "field2": .string("Value 2"),
            "field3": .string("Value 3"),
            "field4": .string("Value 4"),
            "field5": .string("Value 5"),
            "field6": .string("Value 6"),
            "field7": .string("Value 7"),
            "field8": .string("Value 8"),
            "field9": .string("Value 9"),
            "field10": .string("Value 10")
        ]))
        
        // Query without projection
        let result1 = try db.query()
            .where("id", equals: .uuid(recordID))
            .execute()
        
        let fullRecord = try result1.records.first!
        let fullFieldCount = fullRecord.storage.count
        
        // Query with projection (only 2 fields)
        let result2 = try db.query()
            .project("id", "field1")
            .where("id", equals: .uuid(recordID))
            .execute()
        
        let projectedRecord = try result2.records.first!
        let projectedFieldCount = projectedRecord.storage.count
        
        // Projected record should have fewer fields
        XCTAssertEqual(projectedFieldCount, 2)
        XCTAssertLessThan(projectedFieldCount, fullFieldCount)
    }
}

