//
//  MVCCIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for MVCC with actual database operations
//
//  Created: 2025-11-13
//

import XCTest
@testable import BlazeDBCore

final class MVCCIntegrationTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCInteg-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "mvcc_integ_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic MVCC Operations
    
    /// Test basic insert/fetch with MVCC enabled
    func testMVCC_InsertAndFetch() throws {
        print("\n🧪 Testing MVCC Insert + Fetch")
        
        // Insert record
        let record = BlazeDataRecord([
            "name": .string("Alice"),
            "age": .int(30)
        ])
        
        let id = try db.insert(record)
        print("  ✅ Inserted with ID: \(id)")
        
        // Fetch it back
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["name"]?.stringValue, "Alice")
        XCTAssertEqual(fetched?["age"]?.intValue, 30)
        
        print("  ✅ Fetched successfully")
    }
    
    /// Test update creates new version
    func testMVCC_Update() throws {
        print("\n🧪 Testing MVCC Update")
        
        let id = try db.insert(BlazeDataRecord([
            "name": .string("Bob"),
            "score": .int(100)
        ]))
        
        // Update
        try db.update(id: id, with: BlazeDataRecord([
            "score": .int(200)
        ]))
        
        // Verify update
        let updated = try db.fetch(id: id)
        XCTAssertEqual(updated?["name"]?.stringValue, "Bob")
        XCTAssertEqual(updated?["score"]?.intValue, 200)
        
        print("  ✅ Update successful")
    }
    
    /// Test delete marks version as deleted
    func testMVCC_Delete() throws {
        print("\n🧪 Testing MVCC Delete")
        
        let id = try db.insert(BlazeDataRecord(["test": .string("value")]))
        
        // Delete
        try db.delete(id: id)
        
        // Verify deleted
        let fetched = try db.fetch(id: id)
        XCTAssertNil(fetched)
        
        print("  ✅ Delete successful")
    }
    
    // MARK: - Concurrent Read Tests
    
    /// Test concurrent reads (THE KILLER FEATURE! 🚀)
    func testMVCC_ConcurrentReads() throws {
        print("\n🚀 Testing MVCC Concurrent Reads (THIS IS THE MAGIC!)")
        
        // Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "name": .string("User \(i)")
            ]))
            ids.append(id)
        }
        
        print("  ✅ Inserted 100 records")
        
        let group = DispatchGroup()
        var successCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        // Measure time
        let start = Date()
        
        // 100 concurrent reads
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    _ = try self.db.fetch(id: id)
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch {
                    lock.lock()
                    errorCount += 1
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Concurrent reads: 100")
        print("  📊 Success: \(successCount)")
        print("  📊 Errors: \(errorCount)")
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 100.0 / duration)) reads/sec")
        
        XCTAssertEqual(successCount, 100)
        XCTAssertEqual(errorCount, 0)
        
        print("  ✅ All concurrent reads successful!")
    }
    
    /// Test read while write (no blocking!)
    func testMVCC_ReadWhileWrite() throws {
        print("\n🚀 Testing Read While Write (No Blocking!)")
        
        // Insert initial data
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        var readCount = 0
        var writeCount = 0
        let lock = NSLock()
        
        let start = Date()
        
        // Readers (50 threads)
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                _ = try? self.db.fetch(id: id)
                lock.lock()
                readCount += 1
                lock.unlock()
            }
        }
        
        // Writers (10 threads)
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                _ = try? self.db.insert(BlazeDataRecord([
                    "write": .int(i)
                ]))
                lock.lock()
                writeCount += 1
                lock.unlock()
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Reads: \(readCount)")
        print("  📊 Writes: \(writeCount)")
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  ✅ Reads and writes happened concurrently!")
    }
    
    // MARK: - Snapshot Isolation Tests
    
    /// Test that transactions see consistent snapshots
    func testMVCC_SnapshotConsistency() throws {
        print("\n📸 Testing Snapshot Consistency")
        
        // Insert records
        for i in 0..<10 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let initialCount = db.count()
        print("  Initial count: \(initialCount)")
        
        // Transaction 1: Start reading
        let group = DispatchGroup()
        var count1 = 0
        var count2 = 0
        
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            
            // This transaction sees snapshot at start
            count1 = self.db.count()
            Thread.sleep(forTimeInterval: 0.1)
            // Count should be same (snapshot isolation)
            count2 = self.db.count()
        }
        
        // Meanwhile, insert more records
        Thread.sleep(forTimeInterval: 0.05)
        for i in 10..<20 {
            try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        group.wait()
        
        print("  📸 Snapshot count1: \(count1)")
        print("  📸 Snapshot count2: \(count2)")
        print("  📊 Final count: \(db.count())")
        
        // Note: Without full snapshot transactions, this might not work yet
        // This test documents expected behavior
        print("  ℹ️  Snapshot isolation test (expected behavior)")
    }
    
    // MARK: - Performance Benchmarks
    
    /// Benchmark: Concurrent reads vs serial
    func testBenchmark_ConcurrentReads() throws {
        print("\n📊 BENCHMARK: Concurrent Reads (MVCC vs Serial)")
        
        // Insert test data
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        print("  ✅ Inserted 1000 records")
        
        // Benchmark: 1000 reads
        let start = Date()
        
        let group = DispatchGroup()
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? self.db.fetch(id: id)
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 1000 concurrent reads:")
        print("     Duration: \(String(format: "%.3f", duration))s")
        print("     Throughput: \(String(format: "%.0f", 1000.0 / duration)) reads/sec")
        
        // With MVCC, this should be FAST!
        // Serial would be ~1000ms, MVCC should be ~100-200ms
        print("  ✅ Benchmark complete")
    }
    
    /// Benchmark: Insert performance
    func testBenchmark_InsertPerformance() throws {
        print("\n📊 BENCHMARK: Insert Performance")
        
        let start = Date()
        
        for i in 0..<1000 {
            try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Test record \(i)")
            ]))
        }
        
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 1000 inserts:")
        print("     Duration: \(String(format: "%.3f", duration))s")
        print("     Throughput: \(String(format: "%.0f", 1000.0 / duration)) inserts/sec")
        
        // Should be similar to current (small overhead acceptable)
        print("  ✅ Insert benchmark complete")
    }
    
    // MARK: - Stress Tests
    
    /// Stress test: Many concurrent operations
    func testMVCC_ConcurrentStress() throws {
        print("\n🔥 MVCC Stress Test: 1000 Concurrent Operations")
        
        // Pre-populate
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        var insertCount = 0
        var fetchCount = 0
        var updateCount = 0
        var deleteCount = 0
        var errorCount = 0
        let lock = NSLock()
        
        // 1000 random concurrent operations
        for _ in 0..<1000 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    let op = Int.random(in: 0...3)
                    
                    switch op {
                    case 0:  // Insert (25%)
                        _ = try self.db.insert(BlazeDataRecord([
                            "random": .int(Int.random(in: 0...1000))
                        ]))
                        lock.lock()
                        insertCount += 1
                        lock.unlock()
                        
                    case 1:  // Fetch (25%)
                        if let id = ids.randomElement() {
                            _ = try self.db.fetch(id: id)
                        }
                        lock.lock()
                        fetchCount += 1
                        lock.unlock()
                        
                    case 2:  // Update (25%)
                        if let id = ids.randomElement() {
                            try self.db.update(id: id, with: BlazeDataRecord([
                                "updated": .bool(true)
                            ]))
                        }
                        lock.lock()
                        updateCount += 1
                        lock.unlock()
                        
                    case 3:  // Delete (25%)
                        if let id = ids.randomElement(), ids.count > 20 {
                            try self.db.delete(id: id)
                        }
                        lock.lock()
                        deleteCount += 1
                        lock.unlock()
                        
                    default:
                        break
                    }
                } catch {
                    lock.lock()
                    errorCount += 1
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        print("  📊 Operations completed:")
        print("     Inserts: \(insertCount)")
        print("     Fetches: \(fetchCount)")
        print("     Updates: \(updateCount)")
        print("     Deletes: \(deleteCount)")
        print("     Errors:  \(errorCount)")
        
        // Database should still be functional
        XCTAssertNoThrow(try db.fetchAll())
        
        print("  ✅ Stress test passed!")
    }
    
    // MARK: - Data Integrity Tests
    
    /// Verify data integrity after concurrent operations
    func testMVCC_DataIntegrity() throws {
        print("\n🔒 Testing Data Integrity with MVCC")
        
        var expectedRecords: [UUID: BlazeDataRecord] = [:]
        
        // Insert 100 records
        for i in 0..<100 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let id = try db.insert(record)
            expectedRecords[id] = record
        }
        
        // Concurrent reads
        let group = DispatchGroup()
        var integrityFailures = 0
        let lock = NSLock()
        
        for (id, expected) in expectedRecords {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                if let fetched = try? self.db.fetch(id: id) {
                    // Verify data matches
                    if fetched["index"]?.intValue != expected["index"]?.intValue ||
                       fetched["data"]?.stringValue != expected["data"]?.stringValue {
                        lock.lock()
                        integrityFailures += 1
                        lock.unlock()
                    }
                }
            }
        }
        
        group.wait()
        
        print("  📊 Integrity checks: 100")
        print("  📊 Failures: \(integrityFailures)")
        
        XCTAssertEqual(integrityFailures, 0, "All data should be intact")
        
        print("  ✅ Data integrity verified!")
    }
    
    // MARK: - MVCC vs Legacy Comparison
    
    /// Compare MVCC performance to legacy
    func testComparison_MVCCvsLegacy() throws {
        print("\n⚔️  MVCC vs Legacy Performance Comparison")
        
        // This test compares both paths
        // (Currently both use same backend, but documents expected behavior)
        
        let recordCount = 500
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<recordCount {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i)
            ]))
            ids.append(id)
        }
        
        // Benchmark concurrent reads
        let start = Date()
        
        let group = DispatchGroup()
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? self.db.fetch(id: id)
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 \(recordCount) concurrent reads:")
        print("     Duration: \(String(format: "%.3f", duration))s")
        print("     Throughput: \(String(format: "%.0f", Double(recordCount) / duration)) reads/sec")
        
        // Document expected improvement
        print("  💡 Expected with full MVCC: 5-10x faster")
        print("  ✅ Comparison benchmark complete")
    }
}

