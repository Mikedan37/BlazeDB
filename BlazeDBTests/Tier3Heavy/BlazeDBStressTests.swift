//  BlazeDBStressTests.swift
//  BlazeDB Stress Testing Suite
//  Tests database behavior under heavy load and scale

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

// MARK: - Swift 6 concurrency (strict isolation on Linux CI)

private final class StressThreadSafeInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class StressErrorBag: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Error] = []
    func append(_ e: Error) {
        lock.lock()
        items.append(e)
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }
    var first: Error? {
        lock.lock()
        defer { lock.unlock() }
        return items.first
    }
    var all: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

final class BlazeDBStressTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeStress-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "StressTest", fileURL: tempURL, password: "TestPassword-123!")
    }
    
    override func tearDownWithError() throws {
        // Flush any pending metadata writes before cleanup
        if let collection = db?.collection as? DynamicCollection {
            try? collection.persist()
        }
        
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Scale Tests
    
    /// Test inserting records and verifying they all persist
    /// Note: Set RUN_HEAVY_STRESS=1 to use 10k records, otherwise uses 1k
    func testInsert10kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 10_000 : 1_000
        
        print("📊 Starting insertion of \(count) records...")
        let startTime = Date()
        
        // ✅ OPTIMIZED: Use batch insert instead of individual inserts (10x faster!)
        let records = (0..<count).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "title": .string("Record \(i)"),
                "value": .double(Double(i) * 1.5),
                "active": .bool(i % 2 == 0)
            ])
        }
        let insertedIDs = try db.insertMany(records)
        
        let insertDuration = Date().timeIntervalSince(startTime)
        print("✅ Inserted \(count) records in \(String(format: "%.2f", insertDuration))s")
        print("   Rate: \(String(format: "%.0f", Double(count) / insertDuration)) records/sec")
        
        // Verify records exist efficiently
        print("🔍 Verifying \(count) records...")
        let fetchStart = Date()
        
        // Strategy 1: Use fetchAll (single query) + verify count
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, count, "Should have inserted \(count) records")
        
        // Strategy 2: Verify a random sample (100 records) for data integrity
        let sampleSize = min(100, count)
        let sampleIndices = (0..<sampleSize).map { _ in Int.random(in: 0..<count) }
        
        // ✅ OPTIMIZED: Build lookup dictionary instead of fetch-in-loop (100x faster!)
        let recordsMap = Dictionary(uniqueKeysWithValues: allRecords.compactMap { record -> (UUID, BlazeDataRecord)? in
            guard let id = record.storage["id"]?.uuidValue else { return nil }
            return (id, record)
        })
        
        for index in sampleIndices {
            let id = insertedIDs[index]
            guard let record = recordsMap[id] else {
                XCTFail("Sample record \(index) with ID \(id) not found")
                return
            }
            XCTAssertEqual(record.storage["index"]?.intValue, index, "Record data mismatch at index \(index)")
        }
        
        let fetchDuration = Date().timeIntervalSince(fetchStart)
        print("✅ Verified \(count) records + \(sampleSize) samples in \(String(format: "%.2f", fetchDuration))s")
        print("   Fetch all rate: \(String(format: "%.0f", Double(count) / fetchDuration)) records/sec")
    }
    
    /// Test fetchAll performance
    /// Note: Set RUN_HEAVY_STRESS=1 to use 5k records, otherwise uses 500
    func testFetchAllWith5kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 5_000 : 500
        
        print("📊 Inserting \(count) records for fetchAll test...")
        // ✅ OPTIMIZED: Batch insert
        let records = (0..<count).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 100))  // 100 byte strings
            ])
        }
        _ = try db.insertMany(records)
        
        print("🔍 Testing fetchAll()...")
        let startTime = Date()
        let all = try db.fetchAll()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(all.count, count, "Should fetch all \(count) records")
        print("✅ fetchAll() retrieved \(count) records in \(String(format: "%.3f", duration))s")
        print("   Rate: \(String(format: "%.0f", Double(count) / duration)) records/sec")
        
        // Performance assertion: should complete in reasonable time
        XCTAssertLessThan(duration, 5.0, "fetchAll should complete in < 5 seconds for 5k records")
    }
    
    /// Test database file growth with large dataset
    /// Note: Set RUN_HEAVY_STRESS=1 to use 20k records, otherwise uses 2k
    func testFileGrowthWith20kRecords() throws {
        let count = ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ? 20_000 : 2_000
        
        print("📊 Testing file growth with \(count) records...")
        let startSize = try getFileSize(tempURL)
        print("  Initial size: \(formatBytes(startSize))")
        
        for i in 0..<count {
            let record = BlazeDataRecord([
                "id": .int(i),
                "payload": .string(String(repeating: "A", count: 200))  // 200 bytes each
            ])
            _ = try db.insert(record)
            
            if i % 5000 == 0 && i > 0 {
                let currentSize = try getFileSize(tempURL)
                print("  After \(i) records: \(formatBytes(currentSize))")
            }
        }
        
        let finalSize = try getFileSize(tempURL)
        print("✅ Final size: \(formatBytes(finalSize))")
        print("   Growth: \(formatBytes(finalSize - startSize))")
        print("   Avg per record: \(formatBytes((finalSize - startSize) / count)) bytes")
        
        XCTAssertGreaterThan(finalSize, startSize, "File should grow with records")
    }
    
    // MARK: - Concurrency Stress Tests
    
    /// Test 100 concurrent writers
    func test100ConcurrentWriters() throws {
        let writerCount = 100
        let recordsPerWriter = 50
        
        print("📊 Starting \(writerCount) concurrent writers (\(writerCount * recordsPerWriter) total records)...")
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.concurrent", attributes: .concurrent)
        let errorBag = StressErrorBag()
        let successCount = StressThreadSafeInt()
        let db = self.db!
        
        let startTime = Date()
        
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                for i in 0..<recordsPerWriter {
                    do {
                        let record = BlazeDataRecord([
                            "writer": .int(writerID),
                            "index": .int(i),
                            "timestamp": .date(Date())
                        ])
                        _ = try db.insert(record)
                        successCount.increment()
                    } catch {
                        errorBag.append(error)
                    }
                }
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(startTime)
        let successes = successCount.get()
        
        print("✅ Completed \(writerCount) concurrent writers in \(String(format: "%.2f", duration))s")
        print("   Success: \(successes)/\(writerCount * recordsPerWriter)")
        print("   Errors: \(errorBag.count)")
        print("   Throughput: \(String(format: "%.0f", Double(successes) / duration)) writes/sec")
        
        XCTAssertEqual(errorBag.count, 0, "Should have no errors from concurrent writes")
        XCTAssertEqual(successes, writerCount * recordsPerWriter, "All writes should succeed")
    }
    
    /// Test concurrent reads and writes
    func testConcurrentReadsAndWrites() throws {
        // Verify db is initialized
        XCTAssertNotNil(db, "Database should be initialized")
        
        // Reduced counts for more reliable test execution
        let readerCount = 10
        let writerCount = 5
        let duration: TimeInterval = 2.0  // Run for 2 seconds
        
        print("📊 Testing concurrent reads (\(readerCount)) and writes (\(writerCount)) for \(duration)s...")
        
        // Pre-populate with some data
        var seedIDs: [UUID] = []
        for i in 0..<50 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            seedIDs.append(id)
        }
        
        print("✅ Pre-populated \(seedIDs.count) seed records")
        let seeds = Array(seedIDs)
        let db = self.db!
        
        // Test basic write before starting concurrent test
        print("🔍 Testing single write before concurrent test...")
        let testRecord = BlazeDataRecord(["test": .string("pre-test")])
        do {
            _ = try db.insert(testRecord)
            print("✅ Single write successful")
        } catch {
            XCTFail("Single write failed before concurrent test: \(error)")
            return
        }
        
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.mixed", attributes: .concurrent)
        // ✅ OPTIMIZED: Use DispatchTime instead of Date() for more accurate timing
        let deadline = DispatchTime.now() + duration
        let readCount = StressThreadSafeInt()
        let writeCount = StressThreadSafeInt()
        let errorBag = StressErrorBag()
        
        // Start readers
        for readerID in 0..<readerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                var localReads = 0
                while DispatchTime.now() < deadline {
                    let randomID = seeds.randomElement()!
                    _ = try? db.fetch(id: randomID)
                    readCount.increment()
                    localReads += 1
                    // Optimized: shorter delay for default tests, longer for thorough testing
                    let readDelay = ProcessInfo.processInfo.environment["TEST_SLOW_CONCURRENCY"] == "1" ? 1000 : 100
                    usleep(UInt32(readDelay))
                }
                if localReads > 0 {
                    print("  Reader \(readerID) completed \(localReads) reads")
                }
            }
        }
        
        // Start writers with delay (optimized for faster tests)
        let startupDelay = ProcessInfo.processInfo.environment["TEST_SLOW_CONCURRENCY"] == "1" ? 100000 : 10000
        usleep(UInt32(startupDelay))  // 10ms default, 100ms for thorough testing
        
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                var localWrites = 0
                while DispatchTime.now() < deadline {
                    let record = BlazeDataRecord([
                        "writer": .int(writerID),
                        "timestamp": .date(Date())
                    ])
                    do {
                        _ = try db.insert(record)
                        writeCount.increment()
                        localWrites += 1
                        // Optimized: shorter delay for default tests
                        let writeDelay = ProcessInfo.processInfo.environment["TEST_SLOW_CONCURRENCY"] == "1" ? 5000 : 500
                        usleep(UInt32(writeDelay))
                    } catch {
                        errorBag.append(error)
                        print("❌ Writer \(writerID) error: \(error)")
                        break  // Stop this writer on error
                    }
                }
                if localWrites > 0 {
                    print("  Writer \(writerID) completed \(localWrites) writes")
                }
            }
        }
        
        group.wait()
        
        let reads = readCount.get()
        let writes = writeCount.get()
        print("✅ Concurrent test completed:")
        print("   Reads: \(reads) (\(String(format: "%.0f", Double(reads) / duration)) ops/sec)")
        print("   Writes: \(writes) (\(String(format: "%.0f", Double(writes) / duration)) ops/sec)")
        print("   Errors: \(errorBag.count)")
        
        if errorBag.count > 0 {
            print("❌ Write errors encountered:")
            for (index, error) in errorBag.all.prefix(5).enumerated() {
                print("   \(index + 1). \(error)")
            }
            XCTFail("Concurrent writes failed with \(errorBag.count) errors. First error: \(errorBag.first!)")
        }
        
        XCTAssertGreaterThan(reads, 0, "Should have performed reads")
        
        // More lenient assertion for writes - at least some should succeed
        if writes == 0 {
            XCTFail("No writes completed. Errors: \(errorBag.count). First error: \(errorBag.first?.localizedDescription ?? "unknown")")
        }
    }
    
    // MARK: - Durability Stress Tests
    
    /// Test sustained write throughput
    func testSustainedWriteThroughput() throws {
        let testDuration: TimeInterval = 5.0
        let stopTime = Date().addingTimeInterval(testDuration)
        var count = 0
        
        print("📊 Testing sustained write throughput for \(testDuration)s...")
        
        while Date() < stopTime {
            let record = BlazeDataRecord([
                "index": .int(count),
                "payload": .string(String(repeating: "x", count: 100))
            ])
            _ = try db.insert(record)
            count += 1
            
            if count % 500 == 0 {
                let elapsed = testDuration - stopTime.timeIntervalSinceNow
                print("  \(count) records in \(String(format: "%.1f", elapsed))s...")
            }
        }
        
        let throughput = Double(count) / testDuration
        print("✅ Sustained throughput: \(String(format: "%.0f", throughput)) writes/sec")
        print("   Total: \(count) records in \(testDuration)s")
        
        XCTAssertGreaterThan(throughput, 100, "Should sustain at least 100 writes/sec")
    }
    
    /// Test recovery after heavy load
    func testRecoveryAfterHeavyLoad() throws {
        let recordCount = 1000
        
        print("📊 Inserting \(recordCount) records...")
        var insertedIDs: [UUID] = []
        for i in 0..<recordCount {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try db.insert(record)
            insertedIDs.append(id)
        }
        
        // Close and reopen database
        print("🔄 Closing and reopening database...")
        db = nil
        
        db = try BlazeDBClient(name: "StressTest", fileURL: tempURL, password: "TestPassword-123!")
        
        // Verify all records still exist
        print("🔍 Verifying \(recordCount) records after reload...")
        for (index, id) in insertedIDs.enumerated() {
            guard let record = try db.fetch(id: id) else {
                XCTFail("Record \(index) not found after reload")
                return
            }
            XCTAssertEqual(record.storage["index"]?.intValue, index)
        }
        
        print("✅ All \(recordCount) records recovered successfully")
    }
    
    // MARK: - Helper Methods
    
    private func getFileSize(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.intValue ?? 0
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

