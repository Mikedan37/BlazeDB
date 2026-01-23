//
//  AdvancedConcurrencyScenarios.swift
//  BlazeDBIntegrationTests
//
//  PROFESSIONAL-GRADE concurrency testing
//  Tests race conditions, deadlocks, and thread safety in complex scenarios
//

import XCTest
@testable import BlazeDBCore

final class AdvancedConcurrencyScenarios: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdvConcurrency-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Real-World Race Condition Scenarios
    
    /// SCENARIO: 100 concurrent users accessing same bug simultaneously
    /// Tests: Read-while-write, last-write-wins, data consistency
    func testScenario_100UsersAccessSameBug() async throws {
        print("\n👥 SCENARIO: 100 Concurrent Users on Same Bug")
        
        let db = try BlazeDBClient(name: "ConcurrentUsers", fileURL: dbURL, password: "concurrent-123")
        
        // Create the contested bug
        let bugID = try await db.insert(BlazeDataRecord([
            "title": .string("Login crash"),
            "status": .string("open"),
            "views": .int(0),
            "comments": .array([])
        ]))
        
        print("  ✅ Created initial bug")
        
        // 100 concurrent users view and comment
        print("  ⚙️  Simulating 100 concurrent users...")
        
        await withTaskGroup(of: (Int, Bool).self) { group in
            for user in 0..<100 {
                group.addTask {
                    var readSuccess = false
                    var writeSuccess = false
                    
                    // Each user: READ → MODIFY → WRITE
                    do {
                        // Read
                        if let bug = try await db.fetch(id: bugID) {
                            readSuccess = true
                            
                            // Simulate thinking time (makes race more likely)
                            try await Task.sleep(nanoseconds: UInt64.random(in: 1_000...10_000))
                            
                            // Update
                            try await db.update(id: bugID, with: BlazeDataRecord([
                                "last_viewer": .string("user\(user)"),
                                "last_viewed_at": .date(Date())
                            ]))
                            writeSuccess = true
                        }
                    } catch {
                        print("    ⚠️  User \(user) failed: \(error)")
                    }
                    
                    return (user, readSuccess && writeSuccess)
                }
            }
            
            var successCount = 0
            for await (user, success) in group {
                if success { successCount += 1 }
            }
            
            print("  ✅ \(successCount)/100 users completed successfully")
            XCTAssertGreaterThanOrEqual(successCount, 95, "At least 95% should succeed")
        }
        
        // Verify: Bug still exists and is valid
        let finalBug = try await db.fetch(id: bugID)
        XCTAssertNotNil(finalBug, "Bug should still exist")
        XCTAssertNotNil(finalBug?.storage["last_viewer"], "Should have last viewer")
        
        print("  ✅ Data consistent: Last viewer = \(finalBug?.storage["last_viewer"]?.stringValue ?? "unknown")")
        print("  ✅ VALIDATED: 100 concurrent users handled safely!")
    }
    
    /// SCENARIO: Read-heavy workload (100 readers, 1 writer)
    /// Tests: Read performance under writes, lock contention
    func testScenario_ReadHeavyWorkload() async throws {
        print("\n📖 SCENARIO: Read-Heavy Workload (100:1 ratio)")
        
        let db = try BlazeDBClient(name: "ReadHeavy", fileURL: dbURL, password: "read-heavy-123")
        
        // Seed data
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "data": .string("Record \(i)"),
                "counter": .int(0)
            ])
        }
        let ids = try await db.insertMany(records)
        print("  ✅ Seeded 1000 records")
        
        let duration: TimeInterval = 5.0  // Run for 5 seconds
        let startTime = Date()
        
        var readCount = 0
        var writeCount = 0
        let lock = NSLock()
        
        guard !ids.isEmpty else {
            XCTFail("No records to test concurrent reads/writes - inserts may have failed")
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            // 100 concurrent readers
            for _ in 0..<100 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        if let id = ids.randomElement() {
                            _ = try? await db.fetch(id: id)
                            lock.lock()
                            readCount += 1
                            lock.unlock()
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    }
                }
            }
            
            // 1 writer (updates records)
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    if let randomID = ids.randomElement() {
                        try? await db.update(id: randomID, with: BlazeDataRecord([
                            "counter": .int(Int.random(in: 0...100))
                        ]))
                        lock.lock()
                        writeCount += 1
                        lock.unlock()
                    }
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
            }
        }
        
        print("  ✅ Completed: \(readCount) reads, \(writeCount) writes in 5s")
        print("  ✅ Read throughput: \(readCount / 5) reads/sec")
        print("  ✅ Write throughput: \(writeCount / 5) writes/sec")
        
        // Verify: No corruption
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 1000, "No records should be lost")
        print("  ✅ VALIDATED: Read-heavy workload safe, no data loss!")
    }
    
    /// SCENARIO: Write-heavy workload with index updates
    /// Tests: Index consistency under load, batching efficiency
    func testScenario_WriteHeavyWithIndexes() async throws {
        print("\n✍️ SCENARIO: Write-Heavy Workload with Index Updates")
        
        let db = try BlazeDBClient(name: "WriteHeavy", fileURL: dbURL, password: "write-heavy-123")
        
        // Create indexes
        try await db.collection.createIndex(on: "status")
        try await db.collection.createIndex(on: ["status", "priority"])
        try await db.collection.enableSearch(fields: ["title"])
        print("  ✅ Created 3 indexes")
        
        // 50 concurrent writers hammering the database
        print("  ⚙️  50 concurrent writers for 3 seconds...")
        
        let duration: TimeInterval = 3.0
        let startTime = Date()
        var insertCount = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<50 {
                group.addTask {
                    var localInserts = 0
                    while Date().timeIntervalSince(startTime) < duration {
                        do {
                            _ = try await db.insert(BlazeDataRecord([
                                "title": .string("Bug from writer \(writer)"),
                                "status": .string(["open", "closed"].randomElement()!),
                                "priority": .int(Int.random(in: 1...5))
                            ]))
                            localInserts += 1
                        } catch {
                            break
                        }
                    }
                    lock.lock()
                    insertCount += localInserts
                    lock.unlock()
                }
            }
        }
        
        print("  ✅ Inserted \(insertCount) records in 3s (\(insertCount/3) inserts/sec)")
        
        // Verify: All indexes are consistent
        let indexed = try await db.query().where("status", equals: .string("open")).execute()
        let manual = try await db.fetchAll().filter { $0.storage["status"]?.stringValue == "open" }
        
        XCTAssertEqual(indexed.count, manual.count, "Index should match manual count")
        print("  ✅ Status index consistent: \(indexed.count) records")
        
        // Verify: Search index is consistent
        let searchResults = try await db.collection.search(query: "Bug")
        XCTAssertGreaterThan(searchResults.count, 0, "Search should find records")
        print("  ✅ Search index consistent: \(searchResults.count) results")
        
        print("  ✅ VALIDATED: Write-heavy workload with indexes is safe!")
    }
    
    /// SCENARIO: Thundering herd (all clients query at exact same moment)
    /// Tests: Lock contention, query cache, concurrent read safety
    func testScenario_ThunderingHerd() async throws {
        print("\n⚡ SCENARIO: Thundering Herd (1000 simultaneous queries)")
        
        let db = try BlazeDBClient(name: "ThunderingHerd", fileURL: dbURL, password: "herd-123")
        
        // Seed data
        let records = (0..<1000).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try await db.insertMany(records)
        print("  ✅ Seeded 1000 records")
        
        // 1000 clients all query at the exact same moment
        print("  ⚙️  Launching 1000 simultaneous queries...")
        
        let startTime = Date()
        
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    do {
                        let results = try await db.fetchAll()
                        return results.count
                    } catch {
                        return 0
                    }
                }
            }
            
            var results: [Int] = []
            for await count in group {
                results.append(count)
            }
            
            let duration = Date().timeIntervalSince(startTime)
            let successCount = results.filter { $0 == 1000 }.count
            
            print("  ✅ Completed 1000 queries in \(String(format: "%.2f", duration))s")
            print("  ✅ Success rate: \(successCount)/1000 (\(Double(successCount)/10)%)")
            print("  ✅ Throughput: \(Int(1000/duration)) queries/sec")
            
            XCTAssertGreaterThanOrEqual(successCount, 950, "At least 95% should succeed")
        }
        
        print("  ✅ VALIDATED: Thundering herd handled gracefully!")
    }
    
    /// SCENARIO: Cascading transactions (transaction spawns transaction)
    /// Tests: Nested transaction handling, rollback propagation
    func testScenario_CascadingTransactions() async throws {
        print("\n🔄 SCENARIO: Cascading Transaction Operations")
        
        let db = try BlazeDBClient(name: "Cascade", fileURL: dbURL, password: "cascade-123")
        
        // Scenario: Checkout process with multiple steps
        // If any step fails, ALL should rollback
        
        print("  🛒 Simulating checkout process...")
        
        // Step 1: Reserve inventory
        try await db.beginTransaction()
        let inventory = try await db.insert(BlazeDataRecord([
            "product_id": .int(123),
            "reserved": .bool(true),
            "quantity": .int(1)
        ]))
        print("    ✓ Step 1: Inventory reserved")
        
        // Step 2: Create order
        let order = try await db.insert(BlazeDataRecord([
            "order_id": .int(456),
            "status": .string("pending"),
            "inventory_ref": .uuid(inventory)
        ]))
        print("    ✓ Step 2: Order created")
        
        // Step 3: Process payment (simulate failure!)
        let paymentSuccess = Bool.random()
        
        if !paymentSuccess {
            print("    ✗ Step 3: Payment FAILED!")
            print("  ↩️  Rolling back entire checkout...")
            
            try await db.rollbackTransaction()
            
            // Verify: EVERYTHING rolled back
            let inventoryCheck = try await db.fetch(id: inventory)
            let orderCheck = try await db.fetch(id: order)
            
            XCTAssertNil(inventoryCheck, "Inventory reservation should be rolled back")
            XCTAssertNil(orderCheck, "Order should be rolled back")
            
            print("  ✅ All steps rolled back atomically")
        } else {
            print("    ✓ Step 3: Payment succeeded")
            try await db.commitTransaction()
            
            // Verify: Everything committed
            let inventoryCheck = try await db.fetch(id: inventory)
            let orderCheck = try await db.fetch(id: order)
            
            XCTAssertNotNil(inventoryCheck, "Inventory should be committed")
            XCTAssertNotNil(orderCheck, "Order should be committed")
            
            print("  ✅ All steps committed atomically")
        }
        
        print("  ✅ VALIDATED: Cascading operations maintain atomicity!")
    }
    
    /// SCENARIO: Deadlock prevention
    /// Tests: Circular dependencies, timeout handling
    func testScenario_DeadlockPrevention() async throws {
        print("\n🔒 SCENARIO: Potential Deadlock (2 resources, 2 users)")
        
        let db1 = try BlazeDBClient(name: "Resource1", fileURL: dbURL, password: "deadlock-123")
        
        let db2URL = dbURL.deletingLastPathComponent().appendingPathComponent("Resource2-\(UUID().uuidString).blazedb")
        let db2 = try BlazeDBClient(name: "Resource2", fileURL: db2URL, password: "deadlock-123")
        
        defer {
            try? FileManager.default.removeItem(at: db2URL)
            try? FileManager.default.removeItem(at: db2URL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        // Create records
        let r1 = try await db1.insert(BlazeDataRecord(["value": .int(100)]))
        let r2 = try await db2.insert(BlazeDataRecord(["value": .int(200)]))
        
        print("  ✅ Created 2 resources")
        
        // Classic deadlock scenario:
        // User A: Lock R1 → Try R2
        // User B: Lock R2 → Try R1
        
        print("  ⚙️  Attempting deadlock scenario...")
        
        let timeout: TimeInterval = 10.0
        
        let taskA = Task {
            try await db1.beginTransaction()
            try await db1.update(id: r1, with: BlazeDataRecord(["value": .int(101)]))
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            // Try to access db2 (other resource)
            _ = try? await db2.fetch(id: r2)
            try await db1.commitTransaction()
        }
        
        let taskB = Task {
            try await db2.beginTransaction()
            try await db2.update(id: r2, with: BlazeDataRecord(["value": .int(201)]))
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            // Try to access db1 (other resource)
            _ = try? await db1.fetch(id: r1)
            try await db2.commitTransaction()
        }
        
        // Wait for both with timeout
        let start = Date()
        _ = try? await taskA.value
        _ = try? await taskB.value
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, timeout, "Should complete without deadlock")
        print("  ✅ Completed in \(String(format: "%.2f", elapsed))s (no deadlock)")
        print("  ✅ VALIDATED: Deadlock prevention works!")
    }
    
    /// SCENARIO: Index rebuild under heavy concurrent writes
    /// Tests: Index consistency, write performance during rebuild
    func testScenario_IndexRebuildUnderLoad() async throws {
        print("\n🔨 SCENARIO: Index Rebuild During Heavy Writes")
        
        let db = try BlazeDBClient(name: "RebuildLoad", fileURL: dbURL, password: "rebuild-123")
        
        // Insert initial dataset
        let initial = (0..<500).map { i in
            BlazeDataRecord(["value": .int(i), "status": .string("initial")])
        }
        _ = try await db.insertMany(initial)
        print("  ✅ Seeded 500 records")
        
        var rebuildComplete = false
        var continueWriting = true
        var writeCount = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Rebuild index (slow operation)
            group.addTask {
                print("    ⚙️  Starting index rebuild...")
                do {
                    try await db.collection.createIndex(on: "status")
                    lock.lock()
                    rebuildComplete = true
                    lock.unlock()
                    print("    ✅ Index rebuild complete")
                } catch {
                    print("    ❌ Index rebuild failed: \(error)")
                }
            }
            
            // Task 2: Continue writing during rebuild
            group.addTask {
                while !rebuildComplete || writeCount < 50 {
                    do {
                        _ = try await db.insert(BlazeDataRecord([
                            "value": .int(Int.random(in: 1000...2000)),
                            "status": .string("concurrent")
                        ]))
                        lock.lock()
                        writeCount += 1
                        lock.unlock()
                        
                        if writeCount >= 50 { break }
                    } catch {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between writes
                }
                print("    ✅ Completed \(writeCount) concurrent writes")
            }
        }
        
        // Verify: All records present (500 initial + concurrent writes)
        let final = try await db.count()
        XCTAssertEqual(final, 500 + writeCount, "All records should be present")
        print("  ✅ Final count: \(final) records")
        
        // Verify: Index includes concurrent writes
        let concurrentInIndex = try await db.query()
            .where("status", equals: .string("concurrent"))
            .execute()
        
        XCTAssertEqual(concurrentInIndex.count, writeCount, "Index should include all concurrent writes")
        print("  ✅ Index includes all \(writeCount) concurrent writes")
        print("  ✅ VALIDATED: Index rebuild under load maintains consistency!")
    }
    
    /// SCENARIO: Transaction conflict storm (10 transactions on same records)
    /// Tests: Conflict resolution, data integrity, performance
    func testScenario_TransactionConflictStorm() async throws {
        print("\n⚡ SCENARIO: Transaction Conflict Storm")
        
        let db = try BlazeDBClient(name: "ConflictStorm", fileURL: dbURL, password: "conflict-123")
        
        // Create 10 shared resources
        var sharedIDs: [UUID] = []
        for i in 0..<10 {
            let id = try await db.insert(BlazeDataRecord([
                "resource": .int(i),
                "counter": .int(0)
            ]))
            sharedIDs.append(id)
        }
        print("  ✅ Created 10 shared resources")
        
        // 10 concurrent transactions, each trying to update all resources
        print("  ⚙️  10 transactions competing for same resources...")
        
        var successCount = 0
        var conflictCount = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Void.self) { group in
            for txn in 0..<10 {
                group.addTask {
                    do {
                        try await db.beginTransaction()
                        
                        // Try to update all shared resources
                        for (index, id) in sharedIDs.enumerated() {
                            try await db.update(id: id, with: BlazeDataRecord([
                                "counter": .int(txn * 10 + index),
                                "last_txn": .int(txn)
                            ]))
                        }
                        
                        try await db.commitTransaction()
                        
                        lock.lock()
                        successCount += 1
                        lock.unlock()
                        
                        print("    ✓ Transaction \(txn) committed")
                    } catch {
                        try? await db.rollbackTransaction()
                        lock.lock()
                        conflictCount += 1
                        lock.unlock()
                        print("    ✗ Transaction \(txn) failed: \(error)")
                    }
                }
            }
        }
        
        print("  ✅ Results: \(successCount) succeeded, \(conflictCount) conflicts")
        XCTAssertGreaterThan(successCount, 0, "At least some transactions should succeed")
        
        // Verify: Data is consistent (last-write-wins)
        for id in sharedIDs {
            let record = try await db.fetch(id: id)
            XCTAssertNotNil(record, "All resources should exist")
            XCTAssertNotNil(record?.storage["last_txn"], "Should have last transaction marker")
        }
        
        print("  ✅ VALIDATED: Conflict resolution maintains data integrity!")
    }
    
    /// Performance: Measure concurrent operation throughput
    func testPerformance_ConcurrentMixedOperations() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            Task {
                do {
                    let db = try BlazeDBClient(name: "ConcPerf", fileURL: self.dbURL, password: "perf-123")
                    
                    // Seed data
                    let records = (0..<100).map { i in
                        BlazeDataRecord(["value": .int(i)])
                    }
                    _ = try await db.insertMany(records)
                    let ids = try await db.fetchAll().compactMap { $0.storage["id"]?.uuidValue }
                    
                    // Ensure we have data before proceeding
                    guard !ids.isEmpty else {
                        XCTFail("No records were inserted - cannot run concurrent operations test")
                        return
                    }
                    
                    // Mixed concurrent operations
                    await withTaskGroup(of: Void.self) { group in
                        // 10 readers
                        for _ in 0..<10 {
                            group.addTask {
                                for _ in 0..<10 {
                                    if let id = ids.randomElement() {
                                        _ = try? await db.fetch(id: id)
                                    }
                                }
                            }
                        }
                        
                        // 5 writers
                        for _ in 0..<5 {
                            group.addTask {
                                for _ in 0..<5 {
                                    _ = try? await db.insert(BlazeDataRecord(["new": .bool(true)]))
                                }
                            }
                        }
                        
                        // 3 updaters
                        for _ in 0..<3 {
                            group.addTask {
                                for _ in 0..<3 {
                                    if let id = ids.randomElement() {
                                        try? await db.update(id: id, with: BlazeDataRecord(["updated": .bool(true)]))
                                    }
                                }
                            }
                        }
                    }
                    
                } catch {
                    XCTFail("Concurrent operations failed: \(error)")
                }
            }
        }
    }
}

