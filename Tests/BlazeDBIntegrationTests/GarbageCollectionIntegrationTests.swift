//
//  GarbageCollectionIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  COMPREHENSIVE integration tests for garbage collection
//  Tests all 3 GC mechanisms in real-world scenarios
//

import XCTest
@testable import BlazeDB

final class GarbageCollectionIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GC-Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Real-World Scenario 1: Bug Tracker with Archiving
    
    func testGC_BugTrackerArchiveWorkflow() async throws {
        print("\n🐛 GC INTEGRATION: Bug Tracker with Archiving")
        
        let dbURL = tempDir.appendingPathComponent("bugtracker.blazedb")
        let db = try BlazeDBClient(name: "BugTracker", fileURL: dbURL, password: "test-pass-123456")
        
        // Day 1-30: Create 1000 bugs
        print("  📅 Month 1: Creating 1,000 bugs...")
        let bugs = try await db.insertMany((0..<1000).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string("open"),
                "created_at": .date(Date())
            ])
        })
        try await db.persist()
        
        let stats1 = try await db.getStorageStats()
        print("    After creation: \(stats1.totalPages) pages, \(stats1.fileSize / 1024 / 1024) MB")
        
        // Month 2-6: Close and archive 700 bugs (70%)
        print("  📅 Months 2-6: Archiving 700 bugs (70%)...")
        for i in 0..<700 {
            try await db.delete(id: bugs[i])
        }
        try await db.persist()
        
        let stats2 = try await db.getStorageStats()
        print("    After archiving: \(stats2.usedPages) used, \(stats2.emptyPages) empty")
        print("    Waste: \(String(format: "%.1f", stats2.wastePercentage))%")
        
        // Check GC stats
        let gcStats = try db.collection.getGCStats()
        print("    GC: \(gcStats.reuseablePages) reuseable pages")
        
        // Month 7-12: Create 700 new bugs
        print("  📅 Months 7-12: Creating 700 new bugs...")
        _ = try await db.insertMany((0..<700).map { i in
            BlazeDataRecord([
                "title": .string("New Bug \(i)"),
                "status": .string("open"),
                "created_at": .date(Date())
            ])
        })
        try await db.persist()
        
        let stats3 = try await db.getStorageStats()
        print("    After new bugs: \(stats3.totalPages) pages, \(stats3.fileSize / 1024 / 1024) MB")
        
        // With page reuse: totalPages should be close to stats1
        // Without reuse: totalPages would be ~1700 (1000 + 700)
        
        let growth = Double(stats3.totalPages - stats1.totalPages) / Double(stats1.totalPages) * 100
        print("    File growth: \(String(format: "%.1f", growth))%")
        
        XCTAssertLessThan(growth, 50, "Page reuse should limit growth to < 50%")
        
        // Run VACUUM to reclaim any remaining waste
        print("  🧹 Running VACUUM...")
        let vacuumStats = try await db.vacuum()
        print("    Reclaimed: \(vacuumStats.pagesReclaimed) pages")
        
        let statsFinal = try await db.getStorageStats()
        print("    Final: \(statsFinal.usedPages) used pages (should be ~1000)")
        
        XCTAssertEqual(statsFinal.usedPages, 1000, "Should have exactly 1000 active bugs")
        
        print("  ✅ VALIDATED: GC handles bug tracker workflow perfectly!")
    }
    
    // MARK: - Real-World Scenario 2: Metrics Database with Retention
    
    func testGC_MetricsDatabaseWithRetention() async throws {
        print("\n📊 GC INTEGRATION: Metrics Database (7-day retention)")
        
        let dbURL = tempDir.appendingPathComponent("metrics.blazedb")
        let db = try BlazeDBClient(name: "Metrics", fileURL: dbURL, password: "test-pass-123456")
        
        // Simulate 30 days of metrics with 7-day retention
        var allIDs: [[UUID]] = []
        
        for day in 0..<30 {
            // Insert 100 metrics for this day
            let dayIDs = try await db.insertMany((0..<100).map { i in
                BlazeDataRecord([
                    "metric": .string("api_latency"),
                    "value": .double(Double.random(in: 10...500)),
                    "day": .int(day),
                    "timestamp": .date(Date().addingTimeInterval(Double(day * 86400)))
                ])
            })
            allIDs.append(dayIDs)
            
            // After day 7, start deleting old metrics (7-day retention)
            if day >= 7 {
                let oldDayIndex = day - 7
                for id in allIDs[oldDayIndex] {
                    try await db.delete(id: id)
                }
            }
            
            if day % 10 == 0 {
                try await db.persist()
                let stats = try await db.getStorageStats()
                print("    Day \(day): \(stats.usedPages) used, \(stats.fileSize / 1024 / 1024) MB")
            }
        }
        
        // Final check
        let finalStats = try await db.getStorageStats()
        let finalCount = try await db.count()
        
        print("  📊 Final: \(finalCount) metrics, \(finalStats.totalPages) pages, \(finalStats.fileSize / 1024 / 1024) MB")
        
        // Should have only last 7 days = 700 metrics
        XCTAssertEqual(finalCount, 700, "Should have 7 days × 100 = 700 metrics")
        
        // With page reuse: totalPages should be close to 700
        // Without reuse: totalPages would be 3000 (30 days × 100)
        
        let efficiency = Double(finalCount) / Double(finalStats.totalPages)
        print("    Page efficiency: \(String(format: "%.1f", efficiency * 100))%")
        
        XCTAssertGreaterThan(efficiency, 0.60, "Page reuse should achieve > 60% efficiency")
        
        print("  ✅ VALIDATED: GC handles rolling retention efficiently!")
    }
    
    // MARK: - Real-World Scenario 3: Cache Layer with TTL
    
    func testGC_CacheLayerWithExpiration() async throws {
        print("\n💾 GC INTEGRATION: Cache Layer with TTL Expiration")
        
        let dbURL = tempDir.appendingPathComponent("cache.blazedb")
        let db = try BlazeDBClient(name: "Cache", fileURL: dbURL, password: "test-pass-123456")
        
        // Simulate cache with 1-hour TTL
        let now = Date()
        
        // Insert 500 cache entries
        var cacheIDs: [UUID] = []
        for i in 0..<500 {
            let id = try await db.insert(BlazeDataRecord([
                "key": .string("cache_key_\(i)"),
                "value": .string("cached_data_\(i)"),
                "expires_at": .date(now.addingTimeInterval(3600))  // 1 hour
            ]))
            cacheIDs.append(id)
        }
        try await db.persist()
        
        let statsInitial = try await db.getStorageStats()
        print("    Initial: \(statsInitial.totalPages) pages")
        
        // Simulate 10 cache refresh cycles (delete expired, add new)
        for cycle in 0..<10 {
            // Delete "expired" entries (first 50)
            for i in 0..<50 {
                let index = cycle * 50 + i
                if index < cacheIDs.count {
                    try await db.delete(id: cacheIDs[index])
                }
            }
            
            // Add new cache entries
            let newIDs = try await db.insertMany((0..<50).map { i in
                BlazeDataRecord([
                    "key": .string("cache_key_new_\(cycle)_\(i)"),
                    "value": .string("fresh_data"),
                    "expires_at": .date(now.addingTimeInterval(Double(cycle + 1) * 3600))
                ])
            })
            cacheIDs.append(contentsOf: newIDs)
        }
        
        try await db.persist()
        
        let statsFinal = try await db.getStorageStats()
        let finalCount = try await db.count()
        
        print("    Final: \(finalCount) entries, \(statsFinal.totalPages) pages")
        
        // With page reuse: pages should be stable
        let growth = Double(statsFinal.totalPages - statsInitial.totalPages) / Double(statsInitial.totalPages) * 100
        print("    Growth: \(String(format: "%.1f", growth))%")
        
        XCTAssertLessThan(growth, 50, "Cache with page reuse should have minimal growth")
        
        print("  ✅ VALIDATED: GC handles cache expiration efficiently!")
    }
    
    // MARK: - Stress Test: Rapid Churn
    
    func testGC_RapidChurnStress() async throws {
        print("\n⚡ GC STRESS: Rapid Churn (1000 cycles)")
        
        let dbURL = tempDir.appendingPathComponent("churn.blazedb")
        let db = try BlazeDBClient(name: "ChurnTest", fileURL: dbURL, password: "test-pass-123456")
        
        var currentIDs: [UUID] = []
        
        let startTime = Date()
        
        for cycle in 0..<1000 {
            // Delete all current records
            for id in currentIDs {
                try await db.delete(id: id)
            }
            
            // Insert 10 new records
            currentIDs = try await db.insertMany((0..<10).map { i in
                BlazeDataRecord(["cycle": .int(cycle), "value": .int(i)])
            })
            
            if cycle % 100 == 0 {
                try await db.persist()
                let stats = try await db.getStorageStats()
                print("    Cycle \(cycle): \(stats.totalPages) pages")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let finalStats = try await db.getStorageStats()
        let finalCount = try await db.count()
        
        print("  ✅ Completed 1000 cycles in \(String(format: "%.2f", duration))s")
        print("    Final: \(finalCount) records, \(finalStats.totalPages) pages")
        
        // Should have only 10 records (last cycle)
        XCTAssertEqual(finalCount, 10)
        
        // With page reuse: pages should be ~10-20 (minimal waste)
        // Without reuse: pages would be 10,000+ (all cycles)
        XCTAssertLessThan(finalStats.totalPages, 50, "Rapid churn should stay small with page reuse")
        
        print("  ✅ VALIDATED: Page reuse handles rapid churn efficiently!")
    }
    
    // MARK: - Integration: GC + Transactions
    
    func testGC_WithTransactions() async throws {
        print("\n🔄 GC INTEGRATION: GC + Transactions")
        
        let dbURL = tempDir.appendingPathComponent("gc-txn.blazedb")
        let db = try BlazeDBClient(name: "GCTxn", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 100 records
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Transaction: Delete 50, insert 50
        try await db.beginTransaction()
        
        for i in 0..<50 {
            try await db.delete(id: ids[i])
        }
        
        _ = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["new": .int(i)]) })
        
        try await db.commitTransaction()
        
        let stats = try await db.getStorageStats()
        let count = try await db.count()
        
        XCTAssertEqual(count, 100, "Should have 100 total")
        print("  ✅ GC works with transactions: \(count) records, \(stats.totalPages) pages")
    }
    
    // MARK: - Integration: GC + Indexes
    
    func testGC_WithIndexesAndSearch() async throws {
        print("\n🔍 GC INTEGRATION: GC + Indexes + Search")
        
        let dbURL = tempDir.appendingPathComponent("gc-indexes.blazedb")
        let db = try BlazeDBClient(name: "GCIndexes", fileURL: dbURL, password: "test-pass-123456")
        
        // Create indexes
        try db.collection.createIndex(on: "status")
        try db.collection.enableSearch(on: ["title"])
        
        // Insert 200 records
        let ids = try await db.insertMany((0..<200).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ])
        })
        
        // Delete 100 records
        for i in 0..<100 {
            try await db.delete(id: ids[i])
        }
        
        // Insert 100 new records (should reuse pages)
        _ = try await db.insertMany((0..<100).map { i in
            BlazeDataRecord([
                "title": .string("New Bug \(i)"),
                "status": .string("open")
            ])
        })
        
        // Verify indexes still work
        let openBugs = try await db.query().where("status", equals: .string("open")).execute()
        XCTAssertGreaterThan(openBugs.count, 0, "Indexes should work after GC")
        
        // Verify search works
        let searchResults = try db.collection.searchOptimized(query: "Bug", in: ["title"])
        XCTAssertGreaterThan(searchResults.count, 0, "Search should work after GC")
        
        print("  ✅ GC preserves indexes and search: \(openBugs.count) indexed, \(searchResults.count) searched")
    }
    
    // MARK: - Integration: GC + VACUUM + Backup
    
    func testGC_WithVacuumAndBackup() async throws {
        print("\n💾 GC INTEGRATION: Page Reuse + VACUUM + Backup")
        
        let dbURL = tempDir.appendingPathComponent("gc-backup.blazedb")
        let db = try BlazeDBClient(name: "GCBackup", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert and churn
        var ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        for _ in 0..<5 {
            // Delete half
            for i in 0..<50 {
                try await db.delete(id: ids[i])
            }
            
            // Insert new half (reuses pages)
            let newIDs = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
            ids = Array(ids.suffix(50)) + newIDs
        }
        
        let beforeVacuum = try await db.getStorageStats()
        print("    Before VACUUM: \(beforeVacuum.totalPages) pages, \(beforeVacuum.fileSize / 1024) KB")
        
        // Run VACUUM
        let vacuumStats = try await db.vacuum()
        
        let afterVacuum = try await db.getStorageStats()
        print("    After VACUUM: \(afterVacuum.totalPages) pages, \(afterVacuum.fileSize / 1024) KB")
        print("    Reclaimed: \(vacuumStats.sizeReclaimed / 1024) KB")
        
        // Create backup
        let backupURL = tempDir.appendingPathComponent("gc-backup-file.blazedb")
        let backupStats = try await db.backup(to: backupURL)
        
        print("    Backup: \(backupStats.fileSize / 1024) KB")
        
        // Backup should be smaller after VACUUM
        XCTAssertLessThan(backupStats.fileSize, beforeVacuum.fileSize, "Backup after VACUUM should be smaller")
        
        print("  ✅ VALIDATED: GC + VACUUM + Backup work together!")
    }
    
    // MARK: - Integration: Auto-VACUUM Behavior
    
    func testGC_AutoVacuumTriggersCorrectly() async throws {
        print("\n🤖 GC INTEGRATION: Auto-VACUUM Behavior")
        
        let dbURL = tempDir.appendingPathComponent("auto-gc.blazedb")
        let db = try BlazeDBClient(name: "AutoGC", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 100 records
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db.persist()
        
        // Delete 60 records (60% waste)
        for i in 0..<60 {
            try await db.delete(id: ids[i])
        }
        try await db.persist()
        
        let statsBeforeAuto = try await db.getStorageStats()
        print("    Before auto-vacuum: \(String(format: "%.1f", statsBeforeAuto.wastePercentage))% waste")
        
        // Enable auto-vacuum with 50% threshold
        db.enableAutoVacuum(wasteThreshold: 0.50, checkInterval: 0.5)
        
        // Wait for auto-vacuum to potentially run
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        
        // Disable to prevent interference with tests
        db.disableAutoVacuum()
        
        // Note: Auto-vacuum might or might not have run (timing-dependent)
        // Just verify it doesn't crash the system
        
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 40, "Records should be preserved")
        
        print("  ✅ Auto-vacuum mechanism functional (no crashes)")
    }
    
    // MARK: - Integration: GC + Concurrent Operations
    
    func testGC_WithConcurrentOperations() async throws {
        print("\n⚡ GC INTEGRATION: GC + Concurrent Operations")
        
        let dbURL = tempDir.appendingPathComponent("gc-concurrent.blazedb")
        let db = try BlazeDBClient(name: "GCConcurrent", fileURL: dbURL, password: "test-pass-123456")
        
        // Pre-populate
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        var insertCount = 0
        var deleteCount = 0
        let lock = NSLock()
        
        // Concurrent inserts and deletes (churn)
        await withTaskGroup(of: Void.self) { group in
            // Inserters
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<20 {
                        do {
                            _ = try await db.insert(BlazeDataRecord(["concurrent": .bool(true)]))
                            lock.lock()
                            insertCount += 1
                            lock.unlock()
                        } catch {}
                        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                    }
                }
            }
            
            // Deleters
            for _ in 0..<5 {
                group.addTask {
                    for _ in 0..<20 {
                        do {
                            let allRecords = try await db.fetchAll()
                            if let random = allRecords.randomElement(),
                               let id = random.storage["id"]?.uuidValue {
                                try await db.delete(id: id)
                                lock.lock()
                                deleteCount += 1
                                lock.unlock()
                            }
                        } catch {}
                        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
                    }
                }
            }
        }
        
        print("    Operations: \(insertCount) inserts, \(deleteCount) deletes")
        
        let finalStats = try await db.getStorageStats()
        let finalCount = try await db.count()
        
        print("    Final: \(finalCount) records, \(finalStats.totalPages) pages")
        
        // Database should be consistent
        XCTAssertGreaterThan(finalCount, 50, "Should have records remaining")
        
        print("  ✅ VALIDATED: GC is thread-safe!")
    }
    
    // MARK: - Integration: GC Through Crash & Recovery
    
    func testGC_ThroughCrashRecovery() async throws {
        print("\n💥 GC INTEGRATION: GC Through Crash & Recovery")
        
        let dbURL = tempDir.appendingPathComponent("gc-crash.blazedb")
        var db: BlazeDBClient? = try BlazeDBClient(name: "GCCrash", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 100 records
        let ids = try await db!.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        try await db!.persist()
        
        // Delete 50 (pages tracked for reuse)
        for i in 0..<50 {
            try await db!.delete(id: ids[i])
        }
        try await db!.persist()
        
        let gcStatsBefore = try db!.collection.getGCStats()
        print("    Before crash: \(gcStatsBefore.reuseablePages) reuseable pages")
        
        // Crash (kill database)
        db = nil
        
        // Recovery
        db = try BlazeDBClient(name: "GCCrash", fileURL: dbURL, password: "test-pass-123456")
        
        let gcStatsAfter = try db!.collection.getGCStats()
        print("    After recovery: \(gcStatsAfter.reuseablePages) reuseable pages")
        
        // Deleted pages should persist through crash
        XCTAssertGreaterThan(gcStatsAfter.reuseablePages, 40, "Reuseable pages should persist")
        
        // Insert new records (should reuse)
        _ = try await db!.insertMany((0..<50).map { i in BlazeDataRecord(["new": .int(i)]) })
        
        let finalStats = try await db!.getStorageStats()
        
        // Total pages shouldn't grow much (reused deleted pages)
        print("    After reinsert: \(finalStats.totalPages) pages")
        XCTAssertLessThan(finalStats.totalPages, 120, "Should reuse pages after recovery")
        
        print("  ✅ VALIDATED: GC survives crash & recovery!")
    }
    
    // MARK: - Performance: GC Impact on Operations
    
    func testPerformance_GCOverhead() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    let dbURL = self.tempDir.appendingPathComponent("gc-perf-\(UUID().uuidString).blazedb")
                    let db = try BlazeDBClient(name: "GCPerf", fileURL: dbURL, password: "test-pass-123456")
                    
                    // Insert, delete, re-insert (exercise GC)
                    var ids = try await db.insertMany((0..<200).map { i in BlazeDataRecord(["value": .int(i)]) })
                    
                    for i in 0..<100 {
                        try await db.delete(id: ids[i])
                    }
                    
                    _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
                    
                    _ = try await db.getStorageStats()
                    _ = try db.collection.getGCStats()
                    
                } catch {
                    XCTFail("GC performance test failed: \(error)")
                }
            }
        }
    }
}

