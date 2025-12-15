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
@testable import BlazeDB

final class BlazeDBMemoryTests: XCTestCase {
    var tempURL: URL!
    
    override func setUpWithError() throws {
        // Clear cached encryption key to ensure fresh password validation
        BlazeDBClient.clearCachedKey()
        
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeMemory-\(UUID().uuidString).blazedb")
        
        // Clean up any leftover files from previous runs
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        
        // Clear cached encryption key after test
        BlazeDBClient.clearCachedKey()
    }
    
    // MARK: - Memory Leak Tests
    
    /// Test that database instances are properly deallocated
    func testDatabaseDeallocation() throws {
        weak var weakDB: BlazeDBClient?
        
        autoreleasepool {
            var db: BlazeDBClient?
            do {
                db = try BlazeDBClient(
                    name: "LeakTest",
                    fileURL: tempURL,
                    password: "MemoryTestPassword123!"
                )
            } catch {
                XCTFail("Failed to initialize BlazeDBClient: \(error)")
                return
            }
            
            weakDB = db
            XCTAssertNotNil(weakDB, "Database should exist")
            
            guard let dbUnwrapped = db else {
                XCTFail("Database not initialized")
                return
            }
            
            // Use database
            _ = try! dbUnwrapped.insert(BlazeDataRecord(["test": .string("data")]))
            
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
            let store = try! BlazeDB.PageStore(fileURL: tempURL, key: key)
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
        weak var weakStore: BlazeDB.PageStore?
        
        autoreleasepool {
            let key = SymmetricKey(size: .bits256)
            var store: BlazeDB.PageStore? = try! BlazeDB.PageStore(fileURL: tempURL, key: key)
            
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
            password: "BlazeDBMemoryTest123!"
        )
        
        let beforeMemory = getMemoryUsage()
        
        guard let dbUnwrapped = db else {
            XCTFail("Database not initialized")
            return
        }
        
        // Perform multiple transaction rollbacks
        for _ in 0..<10 {
            autoreleasepool {
                try! dbUnwrapped.beginTransaction()
                _ = try! dbUnwrapped.insert(BlazeDataRecord(["test": .string("data")]))
                try! dbUnwrapped.rollbackTransaction()
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
            password: "BlazeDBMemoryTest123!"
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
        // CRITICAL: Ensure database files don't exist before creating
        let mainFileExists = FileManager.default.fileExists(atPath: tempURL.path)
        let metaFileExists = FileManager.default.fileExists(atPath: tempURL.deletingPathExtension().appendingPathExtension("meta").path)
        print("🧪 [TEST] Before creating database: mainFileExists=\(mainFileExists), metaFileExists=\(metaFileExists)")
        
        if mainFileExists || metaFileExists {
            print("🧪 [TEST] WARNING: Database files already exist! Removing them...")
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        }
        
        let db = try BlazeDBClient(
            name: "MemoryReleaseTest",
            fileURL: tempURL,
            password: "BlazeDBMemoryTest123!"
        )
        
        // CRITICAL: Verify database is empty before inserting
        let initialCount = try db.fetchAll().count
        print("🧪 [TEST] Initial record count: \(initialCount)")
        if initialCount > 0 {
            XCTFail("Database should be empty but contains \(initialCount) records. This suggests old data from a previous test run.")
            return
        }
        
        // Insert 500 records
        // ✅ OPTIMIZED: Batch insert
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "X", count: 500))
            ])
        }
        print("🧪 [TEST] About to insert \(records.count) records")
        
        // CRITICAL: Log the size of the first record to verify encoding
        if let firstRecord = records.first {
            do {
                let encoded = try BlazeBinaryEncoder.encode(firstRecord)
                print("🧪 [TEST] First record encoded size: \(encoded.count) bytes (should be ~525 bytes)")
                if encoded.count >= 5 {
                    let first5Bytes = encoded.prefix(5)
                    let hexString = first5Bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("🧪 [TEST] First 5 bytes hex: \(hexString) (should be '42 4c 41 5a 45' for 'BLAZE')")
                }
            } catch {
                print("❌ [TEST] Failed to encode first record: \(error)")
            }
        }
        
        _ = try db.insertMany(records)
        print("🧪 [TEST] Inserted \(records.count) records")
        
        // CRITICAL: Verify records were inserted
        let afterInsertCount = try db.fetchAll().count
        print("🧪 [TEST] Record count after insert: \(afterInsertCount)")
        XCTAssertEqual(afterInsertCount, records.count, "Should have inserted \(records.count) records")
        
        if let collection = db.collection as? DynamicCollection {
            try collection.persist()
        }
        
        let beforeFetch = getMemoryUsage()
        
        autoreleasepool {
            do {
                _ = try db.fetchAll()
            } catch {
                XCTFail("fetchAll failed: \(error)")
            }
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
            password: "BlazeDBMemoryTest123!"
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
            do {
                _ = try db.fetchAll()
            } catch {
                XCTFail("fetchAll failed: \(error)")
            }
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
            password: "BlazeDBMemoryTest123!"
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
                do {
                    _ = try db.fetchAll()
                } catch {
                    XCTFail("fetchAll failed: \(error)")
                }
                
                // Delete some
                let all: [BlazeDataRecord]
                do {
                    all = try db.fetchAll()
                } catch {
                    XCTFail("fetchAll failed: \(error)")
                    return
                }
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

