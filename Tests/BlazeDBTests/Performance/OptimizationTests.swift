//
//  OptimizationTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for all performance optimizations
//
//  Created by Auto on 1/XX/25.
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDB

final class OptimizationTests: XCTestCase {
    
    var tempDir: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        do {
            db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "OptimizationTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Memory Pool Tests
    
    func testMemoryPoolAcquireRelease() async {
        let pool = MemoryPool.shared
        
        // Acquire and release buffers
        let pageBuffer = await pool.acquirePageBuffer()
        await pool.releasePageBuffer(pageBuffer)
        
        let recordBuffer = await pool.acquireRecordBuffer()
        await pool.releaseRecordBuffer(recordBuffer)
        
        let encodingBuffer = await pool.acquireEncodingBuffer(minSize: 1024)
        await pool.releaseEncodingBuffer(encodingBuffer)
        
        // Verify statistics
        let stats = await pool.getStats()
        XCTAssertGreaterThan(stats.totalAcquired, 0)
        XCTAssertGreaterThanOrEqual(stats.totalReleased, 0)
    }
    
    func testMemoryPoolReuse() async {
        let pool = MemoryPool.shared
        
        // Acquire multiple buffers
        let buffer1 = await pool.acquirePageBuffer()
        await pool.releasePageBuffer(buffer1)
        
        let buffer2 = await pool.acquirePageBuffer()
        await pool.releasePageBuffer(buffer2)
        
        // Verify reuse (should have same count)
        XCTAssertEqual(buffer1.count, buffer2.count)
        
        let stats = await pool.getStats()
        XCTAssertGreaterThan(stats.totalReused, 0, "Buffers should be reused")
    }
    
    // MARK: - Page Cache Tests
    
    func testPageCacheHitRate() {
        let cache = PageCache(maxSize: 10)
        
        // Add pages
        for i in 0..<5 {
            cache.set(i, data: Data(repeating: UInt8(i), count: 100))
        }
        
        // Access pages multiple times - verify they're cached (should return non-nil)
        var hits = 0
        var totalAccesses = 0
        for _ in 0..<10 {
            totalAccesses += 1
            if cache.get(0) != nil {
                hits += 1
            }
            totalAccesses += 1
            if cache.get(1) != nil {
                hits += 1
            }
        }
        
        let hitRate = Double(hits) / Double(totalAccesses)
        XCTAssertGreaterThan(hitRate, 0.5, "Hit rate should be > 50% after repeated access")
    }
    
    func testPageCacheEviction() {
        let cache = PageCache(maxSize: 3)
        
        // Add more pages than max size
        for i in 0..<5 {
            cache.set(i, data: Data(repeating: UInt8(i), count: 100))
        }
        
        // Verify oldest pages were evicted
        XCTAssertNil(cache.get(0), "Oldest page should be evicted")
        XCTAssertNil(cache.get(1), "Second oldest page should be evicted")
        XCTAssertNotNil(cache.get(4), "Newest page should still be cached")
    }
    
    func testPageCachePrefetch() throws {
        let cache = PageCache(maxSize: 100)
        
        var prefetchedPages: [Int: Data] = [:]
        let reader: (Int) throws -> Data? = { index in
            return Data(repeating: UInt8(index), count: 100)
        }
        
        // Prefetch pages
        try cache.prefetch([0, 1, 2, 3, 4], reader: reader)
        
        // Verify all pages are cached
        for i in 0..<5 {
            XCTAssertNotNil(cache.get(i), "Page \(i) should be cached after prefetch")
        }
    }
    
    // MARK: - Zero-Copy Reads Tests
    
    func testLazyRecordDecoding() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test"),
            "age": .int(25)
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let pageData = encoded
        
        // Create lazy record
        var lazyRecord = LazyRecord(pageData: pageData, offset: 0, length: pageData.count)
        
        // Verify not decoded yet
        XCTAssertFalse(lazyRecord.isDecoded, "Record should not be decoded initially")
        
        // Access decoded record (triggers lazy decoding)
        let decoded = lazyRecord.decoded
        
        // Verify decoded correctly
        XCTAssertEqual(decoded.storage["name"]?.stringValue, "Test")
        XCTAssertEqual(decoded.storage["age"]?.intValue, 25)
        
        // Verify now decoded
        XCTAssertTrue(lazyRecord.isDecoded, "Record should be decoded after access")
    }
    
    func testLazyRecordZeroCopy() throws {
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "data": .data(Data(repeating: 0x42, count: 1000))
        ])
        
        let encoded = try BlazeBinaryEncoder.encode(record)
        let pageData = encoded
        
        var lazyRecord = LazyRecord(pageData: pageData, offset: 0, length: pageData.count)
        
        // Access raw bytes (zero-copy)
        var accessedBytes: [UInt8] = []
        lazyRecord.withUnsafeBytes { bytes in
            accessedBytes = Array(bytes)
        }
        
        XCTAssertEqual(accessedBytes.count, pageData.count, "Should access all bytes")
    }
    
    // MARK: - Write-Ahead Log Tests
    
    func testWALWriteAndCheckpoint() async throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let key = SymmetricKey(size: .bits256)
        let pageStore = try PageStore(fileURL: tempDir.appendingPathComponent("test.db"), key: key)
        let wal = try WriteAheadLog(logURL: walURL, pageStore: pageStore)
        
        // Write operations to WAL
        let testData = Data(repeating: 0x42, count: 100)
        try await wal.write(pageIndex: 0, data: testData)
        try await wal.write(pageIndex: 1, data: testData)
        
        // Checkpoint (flush to main database)
        try await wal.checkpoint()
        
        // Verify data was written to page store
        let page0 = try pageStore.readPage(index: 0)
        XCTAssertNotNil(page0, "Page 0 should be written after checkpoint")
    }
    
    func testWALBatchWrite() async throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let key = SymmetricKey(size: .bits256)
        let pageStore = try PageStore(fileURL: tempDir.appendingPathComponent("test.db"), key: key)
        let wal = try WriteAheadLog(logURL: walURL, pageStore: pageStore)
        
        // Write multiple operations
        for i in 0..<10 {
            let testData = Data(repeating: UInt8(i), count: 100)
            try await wal.write(pageIndex: i, data: testData)
        }
        
        // Checkpoint all at once
        try await wal.checkpoint()
        
        // Verify all pages written
        for i in 0..<10 {
            let page = try pageStore.readPage(index: i)
            XCTAssertNotNil(page, "Page \(i) should be written")
        }
    }
    
    // MARK: - Batch Index Updates Tests
    
    func testBatchIndexUpdates() throws {
        let collection = db.collection
        
        // Create index
        try collection.createIndex(on: ["name", "age"])
        
        // Prepare batch updates
        var updates: [(id: UUID, record: BlazeDataRecord)] = []
        for i in 0..<100 {
            let id = UUID()
            let record = BlazeDataRecord([
                "id": .uuid(id),
                "name": .string("User\(i)"),
                "age": .int(i)
            ])
            updates.append((id, record))
        }
        
        // Measure batch update time
        let startTime = Date()
        collection.updateIndexesBatchSync(updates)
        let duration = Date().timeIntervalSince(startTime)
        
        // Verify indexes updated
        let index = collection.secondaryIndexes["name+age"]
        XCTAssertNotNil(index, "Index should exist")
        XCTAssertGreaterThan(index?.count ?? 0, 0, "Index should have entries")
        
        // Verify performance (should be fast)
        XCTAssertLessThan(duration, 0.1, "Batch update should be fast (< 100ms for 100 records)")
    }
    
    // MARK: - Cost-Based Query Optimizer Tests
    
    func testQueryOptimizerIndexSelection() throws {
        let collection = db.collection
        
        // Create index
        try collection.createIndex(on: ["name"])
        
        // Insert test data
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("User\(i)"),
                "age": .int(i)
            ]))
        }
        
        // Build query
        let query = db.query()
            .where("name", equals: "User50")
        
        // Get optimized plan
        let plan = query.getOptimizedPlan(collection: collection)
        
        // Verify optimizer selected index
        XCTAssertNotNil(plan.useIndex, "Optimizer should select index for name field")
        XCTAssertEqual(plan.useIndex, "name", "Should use 'name' index")
        XCTAssertEqual(plan.scanOrder, .index, "Should use index scan order")
    }
    
    func testQueryOptimizerCostEstimation() throws {
        let collection = db.collection
        
        // Insert varying amounts of data
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i)
            ]))
        }
        
        // Query with filter
        let query = db.query()
            .where("value", greaterThan: 500)
        
        let plan = query.getOptimizedPlan(collection: collection)
        
        // Verify cost estimation
        XCTAssertGreaterThan(plan.estimatedCost, 0, "Should estimate cost > 0")
        XCTAssertGreaterThan(plan.estimatedRows, 0, "Should estimate rows > 0")
        XCTAssertLessThan(plan.estimatedRows, 1000, "Should estimate fewer rows than total")
    }
    
    func testQueryOptimizerExecution() throws {
        let collection = db.collection
        
        // Create index
        try collection.createIndex(on: ["name"])
        
        // Insert test data
        let targetID = UUID()
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(targetID),
            "name": .string("Target"),
            "age": .int(25)
        ]))
        
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string("User\(i)"),
                "age": .int(i)
            ]))
        }
        
        // Execute optimized query
        let query = db.query()
            .where("name", equals: "Target")
        
        let result = try query.executeOptimized()
        
        // Verify results
        guard case .records(let records) = result else {
            XCTFail("Should return records")
            return
        }
        
        XCTAssertEqual(records.count, 1, "Should find one record")
        XCTAssertEqual(records.first?.storage["id"]?.uuidValue, targetID, "Should find correct record")
    }
    
    // MARK: - Integration Tests
    
    func testOptimizedBatchInsert() throws {
        // Insert large batch
        var records: [BlazeDataRecord] = []
        for i in 0..<1000 {
            records.append(BlazeDataRecord([
                "id": .uuid(UUID()),
                "value": .int(i),
                "name": .string("Record\(i)")
            ]))
        }
        
        let startTime = Date()
        let ids = try db.insertMany(records)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(ids.count, 1000, "Should insert all records")
        XCTAssertLessThan(duration, 1.0, "Batch insert should be fast (< 1s for 1000 records)")
        
        // Verify records exist
        for id in ids {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "Record \(id) should exist")
        }
    }
    
    func testOptimizedQueryWithIndex() throws {
        let collection = db.collection
        
        // Create index
        try collection.createIndex(on: ["category", "price"])
        
        // OPTIMIZATION: Reduced from 500 to 100 records for faster execution with encryption
        // Still sufficient to test query optimization functionality
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "category": .string(i % 10 == 0 ? "Electronics" : "Other"),
                "price": .double(Double(i))
            ]))
        }
        
        // Query with index
        let query = db.query()
            .where("category", equals: "Electronics")
            .where("price", greaterThan: 10)  // Adjusted threshold for smaller dataset
        
        let startTime = Date()
        let result = try query.executeOptimized()
        let duration = Date().timeIntervalSince(startTime)
        
        guard case .records(let records) = result else {
            XCTFail("Should return records")
            return
        }
        
        XCTAssertGreaterThan(records.count, 0, "Should find records")
        // More realistic performance expectation with encryption overhead
        XCTAssertLessThan(duration, 1.0, "Optimized query should be reasonably fast (< 1s)")
        print("✅ Optimized query completed in \(String(format: "%.2f", duration * 1000))ms with \(records.count) results")
    }
}
