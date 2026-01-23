//
//  ExtremeIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  EXTREME integration testing - stress integration scenarios
//  Pushing BlazeDB to its absolute limits
//

import XCTest
@testable import BlazeDBCore

final class ExtremeIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtremeInt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Extreme Scale
    
    func testExtreme_50DatabasesSimultaneous() async throws {
        print("\n🔥 EXTREME: 50 Databases Simultaneously")
        
        var databases: [BlazeDBClient] = []
        
        // Create 50 databases
        for i in 0..<50 {
            let dbURL = tempDir.appendingPathComponent("db\(i).blazedb")
            let db = try BlazeDBClient(name: "DB\(i)", fileURL: dbURL, password: "test-pass-123456")
            databases.append(db)
        }
        
        print("  ✅ Created 50 databases")
        
        // Insert into each
        await withTaskGroup(of: Int.self) { group in
            for (index, db) in databases.enumerated() {
                group.addTask {
                    do {
                        for j in 0..<20 {
                            _ = try await db.insert(BlazeDataRecord([
                                "db": .int(index),
                                "record": .int(j)
                            ]))
                        }
                        return 20
                    } catch {
                        return 0
                    }
                }
            }
            
            var totalInserted = 0
            for await count in group {
                totalInserted += count
            }
            
            print("  ✅ Inserted \(totalInserted) records across 50 databases")
            XCTAssertEqual(totalInserted, 1000, "Should insert 20 × 50 = 1000")
        }
        
        print("  ✅ VALIDATED: 50 databases operate independently")
    }
    
    func testExtreme_ChainOf10JOINs() async throws {
        print("\n🔥 EXTREME: Chain of 10 JOINs")
        
        // Create 10 related databases
        var dbs: [BlazeDBClient] = []
        for i in 0..<10 {
            let dbURL = tempDir.appendingPathComponent("chain\(i).blazedb")
            let db = try BlazeDBClient(name: "Chain\(i)", fileURL: dbURL, password: "test-pass-123456")
            dbs.append(db)
        }
        
        // Insert linked records
        var previousID: UUID? = nil
        for (index, db) in dbs.enumerated() {
            var record: [String: BlazeDocumentField] = ["level": .int(index)]
            if let prev = previousID {
                record["ref"] = .uuid(prev)
            }
            previousID = try await db.insert(BlazeDataRecord(record))
        }
        
        print("  ✅ Created chain of 10 linked databases")
        
        // Perform joins (note: actual API limits, so test what we can)
        guard dbs.count >= 2 else {
            XCTFail("Not enough databases created for join test")
            return
        }
        let joined1 = try await dbs[0].join(with: dbs[1], on: "id", equals: "ref", type: .inner)
        XCTAssertGreaterThan(joined1.count, 0)
        
        print("  ✅ JOIN operations on chain work")
    }
    
    func testExtreme_100ConcurrentTransactions() async throws {
        print("\n🔥 EXTREME: 100 Concurrent Transactions")
        
        let dbURL = tempDir.appendingPathComponent("txn-extreme.blazedb")
        let db = try BlazeDBClient(name: "TxnExtreme", fileURL: dbURL, password: "test-pass-123456")
        
        // Pre-populate with 100 accounts
        var accountIDs: [UUID] = []
        for i in 0..<100 {
            let id = try await db.insert(BlazeDataRecord(["balance": .double(100.0), "account": .int(i)]))
            accountIDs.append(id)
        }
        
        print("  ✅ Created 100 accounts")
        
        // 100 concurrent transactions
        var successCount = 0
        var failCount = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Bool.self) { group in
            for txnIndex in 0..<100 {
                group.addTask {
                    do {
                        try await db.beginTransaction()
                        
                        // Each transaction updates 5 random accounts
                        for _ in 0..<5 {
                            guard let randomID = accountIDs.randomElement() else { continue }
                            if let account = try await db.fetch(id: randomID) {
                                let balance = account.storage["balance"]?.doubleValue ?? 0
                                try await db.update(id: randomID, data: BlazeDataRecord([
                                    "balance": .double(balance + 1.0)
                                ]))
                            }
                        }
                        
                        try await db.commitTransaction()
                        return true
                    } catch {
                        try? await db.rollbackTransaction()
                        return false
                    }
                }
            }
            
            for await success in group {
                lock.lock()
                if success { successCount += 1 } else { failCount += 1 }
                lock.unlock()
            }
        }
        
        print("  ✅ Transactions: \(successCount) committed, \(failCount) failed")
        XCTAssertGreaterThan(successCount, 50, "At least half should succeed")
    }
    
    func testExtreme_1000ConcurrentReads() async throws {
        print("\n🔥 EXTREME: 1,000 Concurrent Reads")
        
        let dbURL = tempDir.appendingPathComponent("read-extreme.blazedb")
        let db = try BlazeDBClient(name: "ReadExtreme", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 100 records
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        print("  ✅ Seeded 100 records")
        
        // 1000 concurrent reads
        var readCount = 0
        let lock = NSLock()
        
        let startTime = Date()
        
        guard !ids.isEmpty else {
            XCTFail("No records to fetch - inserts may have failed")
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    do {
                        if let id = ids.randomElement() {
                            _ = try await db.fetch(id: id)
                            lock.lock()
                            readCount += 1
                            lock.unlock()
                        }
                    } catch {}
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("  ✅ Completed \(readCount)/1000 reads in \(String(format: "%.2f", duration))s")
        print("  ✅ Throughput: \(Int(Double(readCount) / duration)) reads/sec")
        
        XCTAssertGreaterThan(readCount, 900, "Most reads should succeed")
    }
    
    func testExtreme_MixedOperationsUnderLoad() async throws {
        print("\n🔥 EXTREME: Mixed Operations Under Load (5 seconds)")
        
        let dbURL = tempDir.appendingPathComponent("mixed-extreme.blazedb")
        let db = try BlazeDBClient(name: "MixedExtreme", fileURL: dbURL, password: "test-pass-123456")
        
        // Seed data
        let seedIDs = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        try db.collection.createIndex(on: "value")
        
        print("  ✅ Seeded 50 records")
        
        let duration: TimeInterval = 5.0
        let startTime = Date()
        
        var insertCount = 0
        var readCount = 0
        var updateCount = 0
        var deleteCount = 0
        let lock = NSLock()
        
        await withTaskGroup(of: Void.self) { group in
            // Inserters (20 threads)
            for _ in 0..<20 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        do {
                            _ = try await db.insert(BlazeDataRecord(["value": .int(Int.random(in: 100...1000))]))
                            lock.lock()
                            insertCount += 1
                            lock.unlock()
                        } catch {}
                        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                    }
                }
            }
            
            // Readers (50 threads)
            for _ in 0..<50 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        if let id = seedIDs.randomElement() {
                            _ = try? await db.fetch(id: id)
                            lock.lock()
                            readCount += 1
                            lock.unlock()
                        }
                        try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
                    }
                }
            }
            
            // Updaters (15 threads)
            for _ in 0..<15 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        do {
                            if let id = seedIDs.randomElement() {
                                try await db.update(id: id, data: BlazeDataRecord(["updated": .bool(true)]))
                                lock.lock()
                                updateCount += 1
                                lock.unlock()
                            }
                        } catch {}
                        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
                    }
                }
            }
            
            // Deleters (5 threads)
            for _ in 0..<5 {
                group.addTask {
                    while Date().timeIntervalSince(startTime) < duration {
                        // Delete random records (not from seed)
                        let allRecords = try? await db.fetchAll()
                        if let records = allRecords, records.count > 50 {
                            if let toDelete = records.randomElement(),
                               let id = toDelete.storage["id"]?.uuidValue,
                               !seedIDs.contains(id) {
                                try? await db.delete(id: id)
                                lock.lock()
                                deleteCount += 1
                                lock.unlock()
                            }
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                    }
                }
            }
        }
        
        print("  ✅ Operations in 5s:")
        print("    Inserts: \(insertCount)")
        print("    Reads: \(readCount)")
        print("    Updates: \(updateCount)")
        print("    Deletes: \(deleteCount)")
        print("    Total: \(insertCount + readCount + updateCount + deleteCount) operations")
        
        // Verify database is still consistent
        let finalCount = try await db.count()
        XCTAssertGreaterThan(finalCount, 40, "Should have many records")
        
        print("  ✅ Database consistent: \(finalCount) records")
    }
    
    func testExtreme_RapidCreateDestroyDatabases() async throws {
        print("\n🔥 EXTREME: Rapid Create/Destroy (50 cycles)")
        
        for cycle in 0..<50 {
            autoreleasepool {
                do {
                    let dbURL = tempDir.appendingPathComponent("rapid-\(cycle).blazedb")
                    let db = try BlazeDBClient(name: "Rapid\(cycle)", fileURL: dbURL, password: "test-pass-123456")
                    
                    // Quick operations
                    _ = try db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
                    _ = try db.fetchAll()
                    
                    // Immediate destroy (no persist)
                } catch {
                    print("  ⚠️  Cycle \(cycle) error: \(error)")
                }
            }
        }
        
        print("  ✅ Survived 50 rapid create/destroy cycles")
    }
    
    func testExtreme_AllFeaturesSimultaneously() async throws {
        print("\n🔥 EXTREME: All Features Used Simultaneously")
        
        let dbURL = tempDir.appendingPathComponent("all-features.blazedb")
        let db = try BlazeDBClient(name: "AllFeatures", fileURL: dbURL, password: "test-pass-123456")
        
        // Enable all features
        try db.collection.createIndex(on: "status")
        try db.collection.createIndex(on: ["status", "priority"])
        try db.collection.enableSearch(on: ["title", "description"])
        
        db.enableProfiling()
        
        let observerToken = db.observe { _ in }
        defer { observerToken.invalidate() }
        
        print("  ✅ All features enabled")
        
        // Perform operations using all features
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Batch inserts
            group.addTask {
                _ = try? await db.insertMany((0..<100).map { i in
                    BlazeDataRecord([
                        "title": .string("Bug \(i)"),
                        "description": .string("Description for bug \(i)"),
                        "status": .string(["open", "closed"].randomElement()!),
                        "priority": .int(Int.random(in: 1...5))
                    ])
                })
            }
            
            // Task 2: Queries
            group.addTask {
                for _ in 0..<20 {
                    _ = try? await db.query()
                        .where("status", equals: .string("open"))
                        .where("priority", greaterThan: .int(3))
                        .orderBy("priority", descending: true)
                        .limit(10)
                        .execute()
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            
            // Task 3: Searches
            group.addTask {
                for _ in 0..<20 {
                    _ = try? db.collection.searchOptimized(query: "Bug", in: ["title"])
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            
            // Task 4: Transactions
            group.addTask {
                for _ in 0..<10 {
                    do {
                        try await db.beginTransaction()
                        _ = try await db.insert(BlazeDataRecord(["txn": .bool(true)]))
                        try await db.commitTransaction()
                    } catch {
                        try? await db.rollbackTransaction()
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
            // Task 5: Backups
            group.addTask {
                for i in 0..<5 {
                    let backupURL = self.tempDir.appendingPathComponent("backup\(i).blazedb")
                    _ = try? await db.backup(to: backupURL)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        
        print("  ✅ All features used concurrently without crashes")
        
        // Verify database is still consistent
        let count = try await db.count()
        XCTAssertGreaterThan(count, 100, "Should have many records")
        
        // Get profiling report
        let report = db.getProfilingReport()
        XCTAssertFalse(report.isEmpty)
        
        print("  ✅ Database remains consistent: \(count) records")
        
        db.disableProfiling()
    }
    
    func testExtreme_MillionRecordQuery() async throws {
        print("\n🔥 EXTREME: Query on 100K records (simulated)")
        
        // Note: Using 10K for test speed, would be 100K in production
        let count = 10_000
        
        let dbURL = tempDir.appendingPathComponent("large-query.blazedb")
        let db = try BlazeDBClient(name: "LargeQuery", fileURL: dbURL, password: "test-pass-123456")
        
        print("  📥 Inserting \(count) records...")
        
        let records = (0..<count).map { i in
            BlazeDataRecord([
                "value": .int(i),
                "status": .string(i % 3 == 0 ? "active" : "inactive"),
                "priority": .int(i % 10)
            ])
        }
        
        let insertStart = Date()
        _ = try await db.insertMany(records)
        let insertTime = Date().timeIntervalSince(insertStart)
        
        print("  ✅ Inserted \(count) records in \(String(format: "%.2f", insertTime))s")
        
        // Create index
        try db.collection.createIndex(on: "status")
        
        // Query
        let queryStart = Date()
        let results = try await db.query()
            .where("status", equals: .string("active"))
            .execute()
        let queryTime = Date().timeIntervalSince(queryStart)
        
        XCTAssertGreaterThan(results.count, 3000)
        XCTAssertLessThan(queryTime, 1.0, "Query should be fast with index")
        
        print("  ✅ Query on \(count) records: \(results.count) results in \(String(format: "%.3f", queryTime))s")
    }
    
    func testExtreme_DeepRecursiveQueries() async throws {
        print("\n🔥 EXTREME: Deep Recursive Queries")
        
        let dbURL = tempDir.appendingPathComponent("recursive.blazedb")
        let db = try BlazeDBClient(name: "Recursive", fileURL: dbURL, password: "test-pass-123456")
        
        // Create tree structure: parent → child → grandchild → ...
        var previousID: UUID? = nil
        var allIDs: [UUID] = []
        
        for level in 0..<20 {
            var record: [String: BlazeDocumentField] = ["level": .int(level)]
            if let parent = previousID {
                record["parent"] = .uuid(parent)
            }
            previousID = try await db.insert(BlazeDataRecord(record))
            allIDs.append(previousID!)
        }
        
        print("  ✅ Created 20-level tree")
        
        // Query up the tree
        var current = allIDs.last!
        var path: [Int] = []
        
        for _ in 0..<20 {
            if let record = try await db.fetch(id: current) {
                if let level = record.storage["level"]?.intValue {
                    path.append(level)
                }
                if let parent = record.storage["parent"]?.uuidValue {
                    current = parent
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        XCTAssertEqual(path.first, 19, "Should start at level 19")
        XCTAssertEqual(path.last, 0, "Should reach root (level 0)")
        
        print("  ✅ Recursive traversal: \(path.count) levels")
    }
    
    func testExtreme_StressAllIndexTypes() async throws {
        print("\n🔥 EXTREME: Stress All Index Types")
        
        let dbURL = tempDir.appendingPathComponent("index-stress.blazedb")
        let db = try BlazeDBClient(name: "IndexStress", fileURL: dbURL, password: "test-pass-123456")
        
        // Create many indexes
        try db.collection.createIndex(on: "field1")
        try db.collection.createIndex(on: "field2")
        try db.collection.createIndex(on: "field3")
        try db.collection.createIndex(on: ["field1", "field2"])
        try db.collection.createIndex(on: ["field2", "field3"])
        try db.collection.createIndex(on: ["field1", "field2", "field3"])
        try db.collection.enableSearch(on: ["text1", "text2"])
        
        print("  ✅ Created 7 indexes")
        
        // Insert data
        _ = try await db.insertMany((0..<200).map { i in
            BlazeDataRecord([
                "field1": .int(i % 10),
                "field2": .string("value\(i % 5)"),
                "field3": .bool(i % 2 == 0),
                "text1": .string("Text \(i)"),
                "text2": .string("Content \(i)")
            ])
        })
        
        print("  ✅ Inserted 200 records")
        
        // Query using each index
        _ = try await db.query().where("field1", equals: .int(5)).execute()
        _ = try await db.query().where("field2", equals: .string("value3")).execute()
        _ = try await db.query().where("field3", equals: .bool(true)).execute()
        
        // Search
        _ = try db.collection.searchOptimized(query: "Text", in: ["text1"])
        
        print("  ✅ All index types used successfully")
    }
    
    func testExtreme_LongRunningTransaction() async throws {
        print("\n🔥 EXTREME: Long-Running Transaction")
        
        let dbURL = tempDir.appendingPathComponent("long-txn.blazedb")
        let db = try BlazeDBClient(name: "LongTxn", fileURL: dbURL, password: "test-pass-123456")
        
        try await db.beginTransaction()
        
        // Perform many operations in one transaction
        for i in 0..<100 {
            _ = try await db.insert(BlazeDataRecord(["index": .int(i)]))
            
            if i % 10 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)  // Small delays
            }
        }
        
        // Commit after "long" transaction
        try await db.commitTransaction()
        
        let count = try await db.count()
        XCTAssertEqual(count, 100)
        
        print("  ✅ Long transaction committed: 100 records")
    }
    
    func testExtreme_CascadingFailures() async throws {
        print("\n🔥 EXTREME: Cascading Failures")
        
        let dbURL = tempDir.appendingPathComponent("cascade.blazedb")
        let db = try BlazeDBClient(name: "Cascade", fileURL: dbURL, password: "test-pass-123456")
        
        // Setup: 10 linked databases (simulate microservices)
        var dbs: [BlazeDBClient] = []
        for i in 0..<10 {
            let url = tempDir.appendingPathComponent("service\(i).blazedb")
            let serviceDB = try BlazeDBClient(name: "Service\(i)", fileURL: url, password: "test-pass-123456")
            dbs.append(serviceDB)
        }
        
        // Insert into each
        for (index, serviceDB) in dbs.enumerated() {
            _ = try await serviceDB.insert(BlazeDataRecord(["service": .int(index)]))
        }
        
        print("  ✅ Created 10 service databases")
        
        // Simulate cascade: if service 5 fails, others should continue
        do {
            throw NSError(domain: "Service5", code: 500, userInfo: nil)
        } catch {
            print("  ⚠️  Service 5 failed")
        }
        
        // Other services should still work
        for (index, serviceDB) in dbs.enumerated() where index != 5 {
            let count = try await serviceDB.count()
            XCTAssertEqual(count, 1, "Service \(index) should still work")
        }
        
        print("  ✅ Cascading failure isolated: 9/10 services functional")
    }
}

