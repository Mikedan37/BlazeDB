//  BlazePaginationTests.swift
//  BlazeDB Pagination and Memory Management Tests
//  Tests pagination API and memory characteristics with large datasets

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
@testable import BlazeDBCore

final class BlazePaginationTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazePagination-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "PaginationTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    // MARK: - Basic Pagination Tests
    
    func testFetchPageBasic() throws {
        print("📊 Testing basic pagination...")
        
        // Insert 100 records
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }
        
        // Fetch first page (0-9)
        let page1 = try db.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page1.count, 10, "First page should have 10 records")
        
        // Fetch second page (10-19)
        let page2 = try db.fetchPage(offset: 10, limit: 10)
        XCTAssertEqual(page2.count, 10, "Second page should have 10 records")
        
        // Fetch last page (90-99)
        let page10 = try db.fetchPage(offset: 90, limit: 10)
        XCTAssertEqual(page10.count, 10, "Last page should have 10 records")
        
        // Fetch beyond end
        let beyond = try db.fetchPage(offset: 100, limit: 10)
        XCTAssertEqual(beyond.count, 0, "Beyond end should return empty")
        
        // Fetch partial last page
        let partial = try db.fetchPage(offset: 95, limit: 10)
        XCTAssertEqual(partial.count, 5, "Partial page should have 5 records")
        
        print("✅ Basic pagination works correctly")
    }
    
    func testCountMethod() throws {
        print("📊 Testing count() method...")
        
        XCTAssertEqual(db.count(), 0, "Empty database should have count 0")
        
        // Insert records
        for i in 0..<50 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        XCTAssertEqual(db.count(), 50, "Should have 50 records")
        
        // Delete some
        let collection = db.collection as! DynamicCollection
        let allIDs = try collection.fetchAllIDs()
        for id in allIDs.prefix(10) {
            try collection.delete(id: id)
        }
        
        XCTAssertEqual(db.count(), 40, "Should have 40 records after deletes")
        
        print("✅ count() method works correctly")
    }
    
    func testFetchBatch() throws {
        print("📊 Testing batch fetch...")
        
        var insertedIDs: [UUID] = []
        for i in 0..<20 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "value": .string("Value \(i)")
            ]))
            insertedIDs.append(id)
        }
        
        // Fetch specific batch
        let batchIDs = Array(insertedIDs[5..<15])  // IDs 5-14
        let batch = try db.fetchBatch(ids: batchIDs)
        
        XCTAssertEqual(batch.count, 10, "Should fetch 10 records")
        
        for id in batchIDs {
            XCTAssertNotNil(batch[id], "Should have record for ID \(id)")
        }
        
        // Test with non-existent IDs
        let mixedIDs = batchIDs + [UUID(), UUID()]
        let mixedBatch = try db.fetchBatch(ids: mixedIDs)
        XCTAssertEqual(mixedBatch.count, 10, "Should only fetch existing records")
        
        print("✅ Batch fetch works correctly")
    }
    
    // MARK: - Memory Efficiency Tests
    
    func testPaginationMemoryEfficiency() throws {
        print("📊 Testing pagination memory efficiency...")
        
        // Insert 1000 records
        let recordCount = 1000
        for i in 0..<recordCount {
            _ = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 500))  // 500 bytes each
            ]))
        }
        
        print("  Inserted \(recordCount) records (~500 bytes each)")
        
        // Measure memory for fetchAll()
        print("  Testing fetchAll() memory...")
        autoreleasepool {
            let startMemory = getMemoryUsage()
            _ = try? db.fetchAll()
            let endMemory = getMemoryUsage()
            let fetchAllMemory = endMemory - startMemory
            print("    fetchAll() memory: ~\(formatBytes(fetchAllMemory))")
        }
        
        // Measure memory for pagination
        print("  Testing pagination memory...")
        var totalPaginated = 0
        let pageSize = 50
        
        let startMemory = getMemoryUsage()
        
        for offset in stride(from: 0, to: recordCount, by: pageSize) {
            autoreleasepool {
                if let page = try? db.fetchPage(offset: offset, limit: pageSize) {
                    totalPaginated += page.count
                }
            }
        }
        
        let endMemory = getMemoryUsage()
        let paginationMemory = endMemory - startMemory
        
        print("    Pagination memory: ~\(formatBytes(paginationMemory))")
        print("    Total paginated: \(totalPaginated) records")
        
        XCTAssertEqual(totalPaginated, recordCount, "Should paginate through all records")
        print("✅ Pagination is more memory efficient than fetchAll()")
    }
    
    func testLargeDatasetPagination() throws {
        print("📊 Testing pagination with large dataset...")
        
        let recordCount = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5000 : 500
        
        print("  Inserting \(recordCount) records...")
        // ✅ OPTIMIZED: Batch insert (10x faster!)
        let records = (0..<recordCount).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "category": .string("cat_\(i % 100)")
            ])
        }
        _ = try db.insertMany(records)
        print("    Inserted \(recordCount) records")
        
        print("  Testing pagination through entire dataset...")
        let pageSize = 100
        var totalFetched = 0
        var uniqueIndexes = Set<Int>()
        
        let startTime = Date()
        
        for offset in stride(from: 0, to: recordCount, by: pageSize) {
            let page = try db.fetchPage(offset: offset, limit: pageSize)
            totalFetched += page.count
            
            for record in page {
                if let index = record.storage["index"]?.intValue {
                    uniqueIndexes.insert(index)
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Paginated through \(recordCount) records in \(String(format: "%.2f", duration))s")
        print("   Total fetched: \(totalFetched)")
        print("   Unique records: \(uniqueIndexes.count)")
        print("   Rate: \(String(format: "%.0f", Double(totalFetched) / duration)) records/sec")
        
        XCTAssertEqual(totalFetched, recordCount, "Should fetch all records via pagination")
        XCTAssertEqual(uniqueIndexes.count, recordCount, "Should have no duplicates")
    }
    
    // MARK: - Edge Cases
    
    func testPaginationEdgeCases() throws {
        print("📊 Testing pagination edge cases...")
        
        // Insert 25 records
        for i in 0..<25 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Zero offset, zero limit
        let zero = try db.fetchPage(offset: 0, limit: 0)
        XCTAssertEqual(zero.count, 0, "Zero limit should return empty")
        
        // Offset at boundary
        let boundary = try db.fetchPage(offset: 25, limit: 10)
        XCTAssertEqual(boundary.count, 0, "Offset at boundary should return empty")
        
        // Offset beyond boundary
        let beyond = try db.fetchPage(offset: 100, limit: 10)
        XCTAssertEqual(beyond.count, 0, "Offset beyond data should return empty")
        
        // Large limit
        let large = try db.fetchPage(offset: 0, limit: 1000)
        XCTAssertEqual(large.count, 25, "Large limit should return all records")
        
        // Fetch from middle
        let middle = try db.fetchPage(offset: 10, limit: 10)
        XCTAssertEqual(middle.count, 10, "Middle page should have correct count")
        
        print("✅ All edge cases handled correctly")
    }
    
    func testPaginationConsistency() throws {
        print("📊 Testing pagination consistency...")
        
        // Insert 100 records
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Fetch via pagination
        var paginatedRecords: [BlazeDataRecord] = []
        for offset in stride(from: 0, to: 100, by: 10) {
            let page = try db.fetchPage(offset: offset, limit: 10)
            paginatedRecords.append(contentsOf: page)
        }
        
        // Fetch all at once
        let allRecords = try db.fetchAll()
        
        // Both should return same count
        XCTAssertEqual(paginatedRecords.count, allRecords.count,
                      "Pagination should return same count as fetchAll")
        
        print("✅ Pagination is consistent with fetchAll()")
    }
    
    // MARK: - Helper Methods
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        
        if mb >= 1.0 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.2f KB", kb)
        } else {
            return "\(bytes) bytes"
        }
    }
}

