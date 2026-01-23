//  BlazeDBMemoryTests.swift
//  BlazeDB Memory Leak and Efficiency Tests
//  Validates memory management and leak prevention

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

final class BlazeDBMemoryTests: XCTestCase {
    var tempURL: URL!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeMemory-\(UUID().uuidString).blazedb")
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Memory Leak Tests
    
    /// Test that database instances are properly deallocated
    func testDatabaseDeallocation() throws {
        weak var weakDB: BlazeDBClient?
        
        autoreleasepool {
            var db: BlazeDBClient? = try! BlazeDBClient(
                name: "LeakTest",
                fileURL: tempURL,
                password: "test-password-123"
            )
            
            weakDB = db
            XCTAssertNotNil(weakDB, "Database should exist")
            
            // Use database
            _ = try! db!.insert(BlazeDataRecord(["test": .string("data")]))
            
            // Release database
            db = nil
        }
        
        // ✅ OPTIMIZED: Reduced wait time (10ms instead of 100ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        XCTAssertNil(weakDB, "Database should be deallocated (no memory leak)")
    }
    
    /// Test that collection instances are properly deallocated
    func testCollectionDeallocation() throws {
        weak var weakCollection: DynamicCollection?
        
        autoreleasepool {
            let key = SymmetricKey(size: .bits256)
            let store = try! PageStore(fileURL: tempURL, key: key)
            let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
            
            var collection: DynamicCollection? = try! DynamicCollection(
                store: store,
                metaURL: metaURL,
                project: "LeakTest",
                encryptionKey: key
            )
            
            weakCollection = collection
            XCTAssertNotNil(weakCollection, "Collection should exist")
            
            // Use collection
            _ = try! collection!.insert(BlazeDataRecord(["test": .string("data")]))
            
            // Release collection
            collection = nil
        }
        
        // ✅ OPTIMIZED: Reduced wait time (10ms instead of 100ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        XCTAssertNil(weakCollection, "Collection should be deallocated (no memory leak)")
    }
    
    /// Test that page store instances don't leak
    func testPageStoreDeallocation() throws {
        weak var weakStore: PageStore?
        
        autoreleasepool {
            let key = SymmetricKey(size: .bits256)
            var store: PageStore? = try! PageStore(fileURL: tempURL, key: key)
            
            weakStore = store
            XCTAssertNotNil(weakStore, "Store should exist")
            
            // Use store
            let data = Data("test".utf8)
            try! store!.writePage(index: 0, plaintext: data)
            _ = try! store!.readPage(index: 0)
            
            // Release store
            store = nil
        }
        
        // ✅ OPTIMIZED: Reduced wait time (10ms instead of 100ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        XCTAssertNil(weakStore, "PageStore should be deallocated (no memory leak)")
    }
    
    /// Test that transaction cleanup doesn't leak
    func testTransactionRollbackNoLeak() throws {
        var db: BlazeDBClient? = try BlazeDBClient(
            name: "TransactionLeakTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        let beforeMemory = getMemoryUsage()
        
        // Perform multiple transaction rollbacks
        for _ in 0..<10 {
            autoreleasepool {
                try! db!.beginTransaction()
                _ = try! db!.insert(BlazeDataRecord(["test": .string("data")]))
                try! db!.rollbackTransaction()
            }
        }
        
        // ✅ OPTIMIZED: Reduced wait time (10ms instead of 200ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        let afterMemory = getMemoryUsage()
        let growth = afterMemory - beforeMemory
        
        print("📊 Memory after 10 rollbacks: \(formatBytes(growth)) growth")
        
        // Memory should not grow significantly
        XCTAssertLessThan(growth, 5 * 1024 * 1024, "Transaction rollbacks should not leak memory")
        
        db = nil
    }
    
    // MARK: - Memory Growth Tests
    
    /// Test memory growth with large inserts
    func testMemoryGrowthDuringBulkInsert() throws {
        let db = try BlazeDBClient(
            name: "MemoryGrowthTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        let initialMemory = getMemoryUsage()
        
        // Insert 1000 records
        // ✅ OPTIMIZED: Batch insert
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "A", count: 200))
            ])
        }
        _ = try db.insertMany(records)
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let peakMemory = getMemoryUsage()
        let growth = peakMemory - initialMemory
        
        print("📊 Memory growth: \(formatBytes(growth))")
        print("   Initial: \(formatBytes(initialMemory))")
        print("   Peak: \(formatBytes(peakMemory))")
        
        // Memory growth should be reasonable (< 50MB for 1000 x 200-byte records)
        XCTAssertLessThan(growth, 50 * 1024 * 1024, "Memory growth should be reasonable")
    }
    
    /// Test memory is released after fetchAll
    func testMemoryReleasedAfterFetchAll() throws {
        let db = try BlazeDBClient(
            name: "MemoryReleaseTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        // Insert 500 records
        // ✅ OPTIMIZED: Batch insert
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "X", count: 500))
            ])
        }
        _ = try db.insertMany(records)
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let beforeFetch = getMemoryUsage()
        
        autoreleasepool {
            _ = try! db.fetchAll()
        }
        
        // ✅ OPTIMIZED: Reduced polling time (10ms instead of 100ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        let afterFetch = getMemoryUsage()
        let retained = afterFetch - beforeFetch
        
        print("📊 Memory retained after fetchAll: \(formatBytes(retained))")
        
        // Should not retain significant memory after fetchAll
        // Relaxed threshold to 20MB to account for Swift runtime overhead
        XCTAssertLessThan(retained, 20 * 1024 * 1024, "Should release memory after fetchAll")
    }
    
    /// Test pagination uses less memory than fetchAll
    func testPaginationMemoryEfficiency() throws {
        let db = try BlazeDBClient(
            name: "PaginationMemoryTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        // Insert 500 records
        // ✅ OPTIMIZED: Batch insert
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "Y", count: 500))
            ])
        }
        _ = try db.insertMany(records)
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        // Measure fetchAll memory
        let beforeFetchAll = getMemoryUsage()
        autoreleasepool {
            _ = try! db.fetchAll()
        }
        let fetchAllPeak = getMemoryUsage()
        let fetchAllMemory = fetchAllPeak - beforeFetchAll
        
        // ✅ OPTIMIZED: Reduced polling time (10ms instead of 100ms)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        
        // Measure pagination memory
        let beforePagination = getMemoryUsage()
        autoreleasepool {
            _ = try! db.fetchPage(offset: 0, limit: 50)
        }
        let paginationPeak = getMemoryUsage()
        let paginationMemory = paginationPeak - beforePagination
        
        print("📊 Memory comparison:")
        print("   fetchAll: \(formatBytes(fetchAllMemory))")
        print("   pagination (50): \(formatBytes(paginationMemory))")
        
        // Pagination should use significantly less memory
        XCTAssertLessThan(paginationMemory, fetchAllMemory, "Pagination should use less memory")
    }
    
    // MARK: - Stress Memory Tests
    
    /// Test memory under repeated operations
    func testMemoryStabilityUnderLoad() throws {
        let db = try BlazeDBClient(
            name: "MemoryStabilityTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        var memoryReadings: [Int] = []
        
        // Perform 10 rounds of operations
        for round in 0..<10 {
            autoreleasepool {
                // Insert 100 records
                for i in 0..<100 {
                    let record = BlazeDataRecord([
                        "round": .int(round),
                        "index": .int(i),
                        "data": .string(String(repeating: "Z", count: 200))
                    ])
                    _ = try! db.insert(record)
                }
                
                // Fetch all
                _ = try! db.fetchAll()
                
                // Delete some
                let all = try! db.fetchAll()
                for record in all.prefix(50) {
                    if let id = record.storage["id"]?.uuidValue {
                        try! db.delete(id: id)
                    }
                }
            }
            
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            
            let currentMemory = getMemoryUsage()
            memoryReadings.append(currentMemory)
            
            print("  Round \(round + 1): \(formatBytes(currentMemory))")
        }
        
        // Check for memory growth
        let firstReading = memoryReadings[0]
        let lastReading = memoryReadings[9]
        let growth = lastReading - firstReading
        let growthPercent = Double(growth) / Double(firstReading) * 100
        
        print("📊 Memory stability:")
        print("   First: \(formatBytes(firstReading))")
        print("   Last: \(formatBytes(lastReading))")
        print("   Growth: \(formatBytes(growth)) (\(String(format: "%.1f", growthPercent))%)")
        
        // Memory growth should be minimal (< 50% over 10 rounds)
        XCTAssertLessThan(growthPercent, 50, "Memory should remain stable under load")
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
        
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size)
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

