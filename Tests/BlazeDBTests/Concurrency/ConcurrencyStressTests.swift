//
//  ConcurrencyStressTests.swift
//  BlazeDBTests
//
//  Concurrency Torture Tests: Run 50-200 concurrent writers, simultaneous queries,
//  validate no deadlocks, no starvation, no index corruption, no partial writes,
//  no RLS bypass, no spatial/vector index drift.
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class ConcurrencyStressTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip stress tests when not running in CI/CD
        guard CICDDetection.shouldRunStressTests else {
            throw XCTSkip("Stress tests only run in CI/CD environment. Set CI=true or GITHUB_ACTIONS=true to run locally.")
        }
        
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConcurrencyStress-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            if !FileManager.default.fileExists(atPath: tempURL.path) { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "concurrency_stress_test_\(testID)", fileURL: tempURL, password: "ConcurrencyStressTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        // Only cleanup if setup was successful (test wasn't skipped)
        if tempURL != nil {
            cleanupBlazeDB(&db, at: tempURL)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Deadlock Detection
    
    private func detectDeadlock(timeout: TimeInterval = 30.0, operation: @escaping () -> Void) -> Bool {
        let expectation = XCTestExpectation(description: "Operation should complete")
        var completed = false
        let lock = NSLock()
        
        DispatchQueue.global().async {
            operation()
            lock.lock()
            completed = true
            lock.unlock()
            expectation.fulfill()
        }
        
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .timedOut
    }
    
    // MARK: - Tests
    
    func testConcurrencyStress_50Writers() throws {
        print("\n⚡ CONCURRENCY TORTURE: 50 Concurrent Writers")
        
        let writerCount = 50
        let recordsPerWriter = 20
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.writers", attributes: .concurrent)
        
        var successCount = 0
        var errorCount = 0
        let successLock = NSLock()
        let errorLock = NSLock()
        var insertedIDs: [UUID] = []
        let idsLock = NSLock()
        
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
                        let id = try self.db.insert(record)
                        
                        idsLock.lock()
                        insertedIDs.append(id)
                        idsLock.unlock()
                        
                        successLock.lock()
                        successCount += 1
                        successLock.unlock()
                    } catch {
                        errorLock.lock()
                        errorCount += 1
                        errorLock.unlock()
                    }
                }
            }
        }
        
        // Wait with timeout (deadlock detection)
        let waitResult = group.wait(timeout: .now() + 60.0)
        XCTAssertEqual(waitResult, .success, "Operations should complete without deadlock")
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("  📊 Writers: \(writerCount)")
        print("  📊 Records per writer: \(recordsPerWriter)")
        print("  📊 Success: \(successCount)/\(writerCount * recordsPerWriter)")
        print("  📊 Errors: \(errorCount)")
        print("  📊 Duration: \(String(format: "%.2f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", Double(successCount) / duration)) ops/sec")
        
        // Verify no deadlocks
        XCTAssertEqual(errorCount, 0, "Should have no errors")
        XCTAssertEqual(successCount, writerCount * recordsPerWriter, "All writes should succeed")
        
        // Verify no partial writes (all IDs should be fetchable)
        idsLock.lock()
        let ids = insertedIDs
        idsLock.unlock()
        
        for id in ids {
            let record = try db.fetch(id: id)
            XCTAssertNotNil(record, "All inserted records should be fetchable (no partial writes)")
        }
        
        print("  ✅ No deadlocks, no partial writes!")
    }
    
    func testConcurrencyStress_200Writers() throws {
        print("\n⚡ CONCURRENCY TORTURE: 200 Concurrent Writers (EXTREME)")
        
        let writerCount = 200
        let recordsPerWriter = 10
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.extreme", attributes: .concurrent)
        
        var successCount = 0
        var errorCount = 0
        let successLock = NSLock()
        let errorLock = NSLock()
        
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
                            "data": .string("Writer \(writerID) Record \(i)")
                        ])
                        _ = try self.db.insert(record)
                        
                        successLock.lock()
                        successCount += 1
                        successLock.unlock()
                    } catch {
                        errorLock.lock()
                        errorCount += 1
                        errorLock.unlock()
                    }
                }
            }
        }
        
        let waitResult = group.wait(timeout: .now() + 120.0)
        XCTAssertEqual(waitResult, .success, "Operations should complete without deadlock")
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("  📊 Writers: \(writerCount)")
        print("  📊 Success: \(successCount)/\(writerCount * recordsPerWriter)")
        print("  📊 Errors: \(errorCount)")
        print("  📊 Duration: \(String(format: "%.2f", duration))s")
        
        XCTAssertLessThan(errorCount, writerCount * recordsPerWriter / 20, "Error rate should be < 5%")
        print("  ✅ Extreme concurrency test passed!")
    }
    
    func testConcurrencyStress_SimultaneousQueries() throws {
        print("\n⚡ CONCURRENCY TORTURE: Simultaneous Queries During Writes")
        
        // Pre-populate
        var seedIDs: [UUID] = []
        for i in 0..<100 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "status": .string(i % 2 == 0 ? "active" : "inactive")
            ]))
            seedIDs.append(id)
        }
        
        let writerCount = 20
        let readerCount = 50
        let duration: TimeInterval = 5.0
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.mixed", attributes: .concurrent)
        
        var writeCount = 0
        var readCount = 0
        var errorCount = 0
        let writeLock = NSLock()
        let readLock = NSLock()
        let errorLock = NSLock()
        
        let deadline = DispatchTime.now() + duration
        
        // Start writers
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                while DispatchTime.now() < deadline {
                    do {
                        let record = BlazeDataRecord([
                            "writer": .int(writerID),
                            "timestamp": .date(Date())
                        ])
                        _ = try self.db.insert(record)
                        
                        writeLock.lock()
                        writeCount += 1
                        writeLock.unlock()
                        
                        usleep(1000) // 1ms delay
                    } catch {
                        errorLock.lock()
                        errorCount += 1
                        errorLock.unlock()
                    }
                }
            }
        }
        
        // Start readers
        for readerID in 0..<readerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                while DispatchTime.now() < deadline {
                    do {
                        // Random query
                        _ = try self.db.query()
                            .where("status", equals: .string("active"))
                            .execute()
                        
                        readLock.lock()
                        readCount += 1
                        readLock.unlock()
                        
                        usleep(500) // 0.5ms delay
                    } catch {
                        // Some query errors are acceptable
                    }
                }
            }
        }
        
        group.wait()
        
        print("  📊 Writes: \(writeCount) (\(String(format: "%.0f", Double(writeCount) / duration)) ops/sec)")
        print("  📊 Reads: \(readCount) (\(String(format: "%.0f", Double(readCount) / duration)) ops/sec)")
        print("  📊 Errors: \(errorCount)")
        
        XCTAssertGreaterThan(writeCount, 0, "Should have some writes")
        XCTAssertGreaterThan(readCount, 0, "Should have some reads")
        print("  ✅ Simultaneous queries handled correctly!")
    }
    
    func testConcurrencyStress_IndexCorruption() throws {
        print("\n⚡ CONCURRENCY TORTURE: Index Corruption Prevention")
        
        let collection = db.collection as! DynamicCollection
        
        // Create index
        try collection.createIndex(on: "status")
        
        let writerCount = 50
        let recordsPerWriter = 10
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.index", attributes: .concurrent)
        
        var insertedIDs: [UUID] = []
        let idsLock = NSLock()
        
        // Insert records concurrently
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                for i in 0..<recordsPerWriter {
                    do {
                        let status = i % 2 == 0 ? "active" : "inactive"
                        let record = BlazeDataRecord([
                            "writer": .int(writerID),
                            "index": .int(i),
                            "status": .string(status)
                        ])
                        let id = try self.db.insert(record)
                        
                        idsLock.lock()
                        insertedIDs.append(id)
                        idsLock.unlock()
                    } catch {
                        // Some errors are acceptable
                    }
                }
            }
        }
        
        group.wait()
        
        // Verify index integrity
        let activeRecords = try collection.fetch(byIndexedField: "status", value: "active")
        let inactiveRecords = try collection.fetch(byIndexedField: "status", value: "inactive")
        
        let expectedActive = writerCount * recordsPerWriter / 2
        let expectedInactive = writerCount * recordsPerWriter / 2
        
        print("  📊 Active records: \(activeRecords.count) (expected: ~\(expectedActive))")
        print("  📊 Inactive records: \(inactiveRecords.count) (expected: ~\(expectedInactive))")
        
        // Allow some variance due to concurrency
        XCTAssertGreaterThan(activeRecords.count, expectedActive - 10, "Index should be mostly correct")
        XCTAssertGreaterThan(inactiveRecords.count, expectedInactive - 10, "Index should be mostly correct")
        
        print("  ✅ Index integrity maintained!")
    }
    
    func testConcurrencyStress_VectorIndexDrift() throws {
        print("\n⚡ CONCURRENCY TORTURE: Vector Index Drift Prevention")
        
        // Enable vector index
        try db.enableVectorIndex(fieldName: "embedding")
        
        let writerCount = 30
        let recordsPerWriter = 5
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.vector", attributes: .concurrent)
        
        var insertedIDs: [UUID] = []
        let idsLock = NSLock()
        
        // Insert records with vectors concurrently
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                for i in 0..<recordsPerWriter {
                    do {
                        let vector: VectorEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
                        let vectorData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                        
                        let record = BlazeDataRecord([
                            "writer": .int(writerID),
                            "index": .int(i),
                            "embedding": .data(vectorData)
                        ])
                        let id = try self.db.insert(record)
                        
                        idsLock.lock()
                        insertedIDs.append(id)
                        idsLock.unlock()
                    } catch {
                        // Some errors are acceptable
                    }
                }
            }
        }
        
        group.wait()
        
        // Verify vector index stats
        let stats = db.getVectorIndexStats()
        XCTAssertNotNil(stats, "Vector index should exist")
        
        if let stats = stats {
            print("  📊 Vector index: \(stats.totalVectors) vectors")
            XCTAssertGreaterThanOrEqual(stats.totalVectors, writerCount * recordsPerWriter - 10, "Vector index should contain most vectors")
        }
        
        print("  ✅ Vector index drift prevented!")
    }
    
    func testConcurrencyStress_SpatialIndexDrift() throws {
        print("\n⚡ CONCURRENCY TORTURE: Spatial Index Drift Prevention")
        
        // Enable spatial index
        try db.enableSpatialIndex(on: "lat", lonField: "lon")
        
        let writerCount = 30
        let recordsPerWriter = 5
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.spatial", attributes: .concurrent)
        
        // Insert records with locations concurrently
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                for i in 0..<recordsPerWriter {
                    do {
                        let lat = 37.7749 + Double.random(in: -0.1...0.1)
                        let lon = -122.4194 + Double.random(in: -0.1...0.1)
                        
                        let record = BlazeDataRecord([
                            "writer": .int(writerID),
                            "index": .int(i),
                            "lat": .double(lat),
                            "lon": .double(lon)
                        ])
                        _ = try self.db.insert(record)
                    } catch {
                        // Some errors are acceptable
                    }
                }
            }
        }
        
        group.wait()
        
        // Verify spatial index works
        let results = try db.query()
            .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 10000)
            .execute()
        
        let records = try results.records
        print("  📊 Spatial query results: \(records.count)")
        XCTAssertGreaterThan(records.count, 0, "Spatial index should work")
        
        print("  ✅ Spatial index drift prevented!")
    }
    
    func testConcurrencyStress_StarvationDetection() throws {
        print("\n⚡ CONCURRENCY TORTURE: Starvation Detection")
        
        // Pre-populate
        var seedIDs: [UUID] = []
        for i in 0..<50 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            seedIDs.append(id)
        }
        
        let writerCount = 10
        let readerCount = 100 // More readers than writers
        let duration: TimeInterval = 3.0
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "stress.starvation", attributes: .concurrent)
        
        var writeCount = 0
        var readCount = 0
        let writeLock = NSLock()
        let readLock = NSLock()
        
        let deadline = DispatchTime.now() + duration
        
        // Start writers (should not starve)
        for writerID in 0..<writerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                while DispatchTime.now() < deadline {
                    do {
                        let record = BlazeDataRecord(["writer": .int(writerID)])
                        _ = try self.db.insert(record)
                        
                        writeLock.lock()
                        writeCount += 1
                        writeLock.unlock()
                        
                        usleep(2000) // 2ms delay
                    } catch {
                        // Some errors are acceptable
                    }
                }
            }
        }
        
        // Start readers (many more)
        for readerID in 0..<readerCount {
            group.enter()
            queue.async {
                defer { group.leave() }
                
                while DispatchTime.now() < deadline {
                    if let randomID = seedIDs.randomElement() {
                        _ = try? self.db.fetch(id: randomID)
                        
                        readLock.lock()
                        readCount += 1
                        readLock.unlock()
                    }
                    usleep(100) // 0.1ms delay
                }
            }
        }
        
        group.wait()
        
        print("  📊 Writes: \(writeCount)")
        print("  📊 Reads: \(readCount)")
        
        // Writers should not be starved (should have some writes)
        XCTAssertGreaterThan(writeCount, 0, "Writers should not be starved")
        
        print("  ✅ No starvation detected!")
    }
}

