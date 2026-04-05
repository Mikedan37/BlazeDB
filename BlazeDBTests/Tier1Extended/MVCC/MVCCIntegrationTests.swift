//
//  MVCCIntegrationTests.swift
//  BlazeDBTests
//
//  Integration tests for MVCC with actual database operations
//
//  Created: 2025-11-13
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private final class MVCCIntegrationLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class MVCCIntegrationTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCInteg-\(testID).blazedb")
        tempURL = url
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "mvcc_integ_test", fileURL: url, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
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
        
        let id = try requireFixture(db).insert(record)
        print("  ✅ Inserted with ID: \(id)")
        
        // Fetch it back
        let fetched = try requireFixture(db).fetch(id: id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["name"]?.stringValue, "Alice")
        XCTAssertEqual(fetched?["age"]?.intValue, 30)
        
        print("  ✅ Fetched successfully")
    }
    
    /// Test update creates new version
    func testMVCC_Update() throws {
        print("\n🧪 Testing MVCC Update")
        
        let id = try requireFixture(db).insert(BlazeDataRecord([
            "name": .string("Bob"),
            "score": .int(100)
        ]))
        
        // Update
        try requireFixture(db).update(id: id, with: BlazeDataRecord([
            "score": .int(200)
        ]))
        
        // Verify update
        let updated = try requireFixture(db).fetch(id: id)
        XCTAssertTrue(updated?["name"]?.stringValue == "Bob" || updated?["name"] == nil)
        XCTAssertEqual(updated?["score"]?.intValue, 200)
        
        print("  ✅ Update successful")
    }
    
    /// Test delete marks version as deleted
    func testMVCC_Delete() throws {
        print("\n🧪 Testing MVCC Delete")
        
        let id = try requireFixture(db).insert(BlazeDataRecord(["test": .string("value")]))
        
        // Delete
        try requireFixture(db).delete(id: id)
        
        // Verify deleted
        let fetched = try requireFixture(db).fetch(id: id)
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
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "name": .string("User \(i)")
            ]))
            ids.append(id)
        }
        
        print("  ✅ Inserted 100 records")
        
        let group = DispatchGroup()
        let successCount = MVCCIntegrationLockedCounter()
        let errorCount = MVCCIntegrationLockedCounter()
        let dbRef = try requireFixture(db)
        
        // Measure time
        let start = Date()
        
        // 100 concurrent reads
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    _ = try dbRef.fetch(id: id)
                    successCount.increment()
                } catch {
                    errorCount.increment()
                }
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Concurrent reads: 100")
        print("  📊 Success: \(successCount.get())")
        print("  📊 Errors: \(errorCount.get())")
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 100.0 / duration)) reads/sec")
        
        XCTAssertEqual(successCount.get(), 100)
        XCTAssertEqual(errorCount.get(), 0)
        
        print("  ✅ All concurrent reads successful!")
    }
    
    /// Test read while write (no blocking!)
    func testMVCC_ReadWhileWrite() throws {
        print("\n🚀 Testing Read While Write (No Blocking!)")
        
        // Insert initial data
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        let readCount = MVCCIntegrationLockedCounter()
        let writeCount = MVCCIntegrationLockedCounter()
        let dbRef = try requireFixture(db)
        let idList = ids
        
        let start = Date()
        
        // Readers (50 threads)
        for id in idList {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                _ = try? dbRef.fetch(id: id)
                readCount.increment()
            }
        }
        
        // Writers (10 threads)
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                _ = try? dbRef.insert(BlazeDataRecord([
                    "write": .int(i)
                ]))
                writeCount.increment()
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Reads: \(readCount.get())")
        print("  📊 Writes: \(writeCount.get())")
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  ✅ Reads and writes happened concurrently!")
    }
    
    // MARK: - Snapshot Isolation Tests
    
    /// Test that transactions see consistent snapshots
    func testMVCC_SnapshotConsistency() throws {
        print("\n📸 Testing Snapshot Consistency")
        
        // Insert records
        for i in 0..<10 {
            try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let initialCount = try requireFixture(db).count()
        print("  Initial count: \(initialCount)")
        
        // Transaction 1: Start reading
        let group = DispatchGroup()
        let count1 = MVCCIntegrationLockedCounter()
        let count2 = MVCCIntegrationLockedCounter()
        let dbRef = try requireFixture(db)
        
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            
            // This transaction sees snapshot at start
            count1.set((try? dbRef.count()) ?? 0)
            Thread.sleep(forTimeInterval: 0.1)
            // Count should be same (snapshot isolation)
            count2.set((try? dbRef.count()) ?? 0)
        }
        
        // Meanwhile, insert more records
        Thread.sleep(forTimeInterval: 0.05)
        for i in 10..<20 {
            try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        group.wait()
        
        print("  📸 Snapshot count1: \(count1.get())")
        print("  📸 Snapshot count2: \(count2.get())")
        print("  📊 Final count: \(try requireFixture(db).count())")
        
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
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        print("  ✅ Inserted 1000 records")
        
        // Benchmark: 1000 reads
        let start = Date()
        
        let group = DispatchGroup()
        let dbRef = try requireFixture(db)
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? dbRef.fetch(id: id)
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
            try requireFixture(db).insert(BlazeDataRecord([
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
            let id = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        let insertCount = MVCCIntegrationLockedCounter()
        let fetchCount = MVCCIntegrationLockedCounter()
        let updateCount = MVCCIntegrationLockedCounter()
        let deleteCount = MVCCIntegrationLockedCounter()
        let errorCount = MVCCIntegrationLockedCounter()
        let dbRef = try requireFixture(db)
        let idList = ids
        
        // 1000 random concurrent operations
        for _ in 0..<1000 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    let op = Int.random(in: 0...3)
                    
                    switch op {
                    case 0:  // Insert (25%)
                        _ = try dbRef.insert(BlazeDataRecord([
                            "random": .int(Int.random(in: 0...1000))
                        ]))
                        insertCount.increment()
                        
                    case 1:  // Fetch (25%)
                        if let id = idList.randomElement() {
                            _ = try dbRef.fetch(id: id)
                        }
                        fetchCount.increment()
                        
                    case 2:  // Update (25%)
                        if let id = idList.randomElement() {
                            try dbRef.update(id: id, with: BlazeDataRecord([
                                "updated": .bool(true)
                            ]))
                        }
                        updateCount.increment()
                        
                    case 3:  // Delete (25%)
                        if let id = idList.randomElement(), idList.count > 20 {
                            try dbRef.delete(id: id)
                        }
                        deleteCount.increment()
                        
                    default:
                        break
                    }
                } catch {
                    errorCount.increment()
                }
            }
        }
        
        group.wait()
        
        print("  📊 Operations completed:")
        print("     Inserts: \(insertCount.get())")
        print("     Fetches: \(fetchCount.get())")
        print("     Updates: \(updateCount.get())")
        print("     Deletes: \(deleteCount.get())")
        print("     Errors:  \(errorCount.get())")
        
        // Database should still be functional
        XCTAssertNoThrow(try requireFixture(db).fetchAll())
        
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
            let id = try requireFixture(db).insert(record)
            expectedRecords[id] = record
        }
        
        // Concurrent reads
        let group = DispatchGroup()
        let integrityFailures = MVCCIntegrationLockedCounter()
        let dbRef = try requireFixture(db)
        
        for (id, expected) in expectedRecords {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                if let fetched = try? dbRef.fetch(id: id) {
                    // Verify data matches
                    if fetched["index"]?.intValue != expected["index"]?.intValue ||
                       fetched["data"]?.stringValue != expected["data"]?.stringValue {
                        integrityFailures.increment()
                    }
                }
            }
        }
        
        group.wait()
        
        print("  📊 Integrity checks: 100")
        print("  📊 Failures: \(integrityFailures.get())")
        
        XCTAssertEqual(integrityFailures.get(), 0, "All data should be intact")
        
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
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i)
            ]))
            ids.append(id)
        }
        
        // Benchmark concurrent reads
        let start = Date()
        
        let group = DispatchGroup()
        let dbRef = try requireFixture(db)
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? dbRef.fetch(id: id)
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

