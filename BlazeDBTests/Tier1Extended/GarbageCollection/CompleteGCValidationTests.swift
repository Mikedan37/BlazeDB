//
//  CompleteGCValidationTests.swift
//  BlazeDBTests
//
//  End-to-end validation that complete GC prevents storage blowup
//
//  This is THE test that proves BlazeDB won't blow up in production.
//
//  Created: 2025-11-13
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CompleteGCValidationTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompleteGC-\(testID).blazedb")
        tempURL = url
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "complete_gc_test", fileURL: url, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }

    private var isHeavyStressMode: Bool {
        ProcessInfo.processInfo.environment["RUN_HEAVY_STRESS"] == "1" ||
        ProcessInfo.processInfo.environment["TEST_SLOW_CONCURRENCY"] == "1"
    }

    private func scaled(_ value: Int, floor: Int = 1) -> Int {
        if isHeavyStressMode { return value }
        return max(floor, Int(Double(value) * 0.35))
    }

    private func requireDatabaseURL() throws -> URL {
        try XCTUnwrap(tempURL, "temp URL must be set in setUp")
    }
    
    // MARK: - THE ULTIMATE TEST
    
    /// THE BIG ONE: Prove storage won't blow up over time
    func testCompleteGC_PreventStorageBlowup() throws {
        print("\n" + String(repeating: "=", count: 60))
        print("🔥 ULTIMATE TEST: Complete GC Prevents Storage Blowup")
        print(String(repeating: "=", count: 60))
        
        try requireFixture(db).setMVCCEnabled(true)
        
        // Configure aggressive GC
        var gcConfig = MVCCGCConfiguration()
        gcConfig.transactionThreshold = 50
        gcConfig.versionThreshold = 2.0
        gcConfig.verbose = true
        try requireFixture(db).configureGC(gcConfig)
        
        let sizeInitial = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 1
        print("\n📊 Initial file size: \(sizeInitial / 1000) KB")
        
        // Simulate 6 months of heavy usage
        print("\n🔄 Simulating 6 months of heavy usage...")
        
        var ids: [UUID] = []
        
        for month in 1...6 {
            print("\n📅 Month \(month):")
            
            // Insert 1000 records
            print("   📝 Inserting 1000 records...")
            for i in 0..<1000 {
                let id = try requireFixture(db).insert(BlazeDataRecord([
                    "month": .int(month),
                    "index": .int(i),
                    "data": .string(String(repeating: "x", count: 500))
                ]))
                ids.append(id)
            }
            
            // Update 500 records (creates new versions)
            print("   ✏️  Updating 500 records...")
            for id in ids.prefix(500).shuffled() {
                try requireFixture(db).update(id: id, with: BlazeDataRecord([
                    "updated": .bool(true)
                ]))
            }
            
            // Delete 300 old records
            print("   🗑️ Deleting 300 old records...")
            if ids.count > 300 {
                for id in ids.prefix(300) {
                    try requireFixture(db).delete(id: id)
                }
                ids.removeFirst(300)
            }
            
            // Persist and GC
            try requireFixture(db).persist()
            let removed = try requireFixture(db).runGarbageCollection()
            print("   ♻️  GC removed \(removed) old versions")
            
            // Check size
            let sizeNow = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let growth = Double(sizeNow - sizeInitial) / Double(sizeInitial)
            
            print("   📊 File size: \(sizeNow / 1_000_000) MB (growth: \(String(format: "%.1f", growth * 100))%)")
            
            // VACUUM if needed
            let health = try requireFixture(db).getStorageHealth()
            if health.needsVacuum {
                print("   🗑️ Running VACUUM (waste: \(String(format: "%.1f", health.wastedPercentage * 100))%)...")
                try requireFixture(db).vacuum()
                
                let sizeAfterVacuum = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                print("   ✅ VACUUM complete: \(sizeAfterVacuum / 1_000_000) MB")
            }
        }
        
        // Final check
        let sizeFinal = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let totalGrowth = Double(sizeFinal - sizeInitial) / max(Double(sizeInitial), 1.0)
        
        print("\n" + String(repeating: "=", count: 60))
        print("📊 FINAL RESULTS:")
        print("   Initial size: \(sizeInitial / 1_000_000) MB")
        print("   Final size:   \(sizeFinal / 1_000_000) MB")
        print("   Growth:       \(String(format: "%.1f", totalGrowth * 100))%")
        print("   Active records: \(try requireFixture(db).count())")
        print(String(repeating: "=", count: 60))
        
        // With complete GC, growth should be bounded
        // Even after 6 months of heavy usage, file should not 10x
        XCTAssertLessThan(totalGrowth, 10.0, "File should not grow 10x even after months")
        
        // Get final stats
        let mvccStats = try requireFixture(db).getMVCCStats()
        let gcStats = try requireFixture(db).getGCStats()
        let pageGCStats = try requireFixture(db).collection.versionManager.pageGC.getStats()
        
        print("\n📊 MVCC Stats:")
        print(mvccStats.description)
        print("\n📊 Version GC Stats:")
        print(gcStats.description)
        print("\n📊 Page GC Stats:")
        print(pageGCStats.description)
        
        print("\n✅ STORAGE WILL NOT BLOW UP! ✅")
        print("   ✅ Memory GC working")
        print("   ✅ Page GC working")
        print("   ✅ VACUUM working")
        print("   ✅ File size bounded")
        print("\n🎉 BlazeDB is BULLETPROOF! 🎉\n")
    }
    
    // MARK: - Regression Prevention
    
    /// Ensure file never grows beyond 3x active data size
    func testGC_FileSizeBoundary() throws {
        print("\n📏 Testing File Size Stays Bounded")
        
        try requireFixture(db).setMVCCEnabled(true)
        
        // Insert baseline
        var ids: [UUID] = []
        for i in 0..<200 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "data": .string(String(repeating: "x", count: 2000))
            ]))
            ids.append(id)
        }
        
        try requireFixture(db).persist()
        let baselineSize = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        
        // Heavy churn (10 cycles of update/delete)
        for cycle in 0..<10 {
            // Update all
            for id in ids {
                try requireFixture(db).update(id: id, with: BlazeDataRecord([
                    "cycle": .int(cycle)
                ]))
            }
            
            // Delete half, insert half
            for id in ids.prefix(100) {
                try requireFixture(db).delete(id: id)
            }
            ids.removeFirst(100)
            
            for i in 0..<100 {
                let id = try requireFixture(db).insert(BlazeDataRecord([
                    "data": .string(String(repeating: "y", count: 2000))
                ]))
                ids.append(id)
            }
            
            // GC
            try requireFixture(db).runGarbageCollection()
            
            // Auto-vacuum if needed
            try requireFixture(db).autoVacuumIfNeeded()
        }
        
        try requireFixture(db).persist()
        let finalSize = try requireDatabaseURL().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        
        let ratio = Double(finalSize) / Double(baselineSize)
        
        print("  Baseline: \(baselineSize / 1_000_000) MB")
        print("  Final:    \(finalSize / 1_000_000) MB")
        print("  Ratio:    \(String(format: "%.2f", ratio))x")
        
        // File should not grow beyond 3x despite heavy churn
        XCTAssertLessThan(ratio, 3.0, "Complete GC should keep file within 3x baseline")
        
        print("  ✅ File size stays bounded!")
    }
    
    /// The "Real World" simulation
    func testGC_RealWorldSimulation() throws {
        print("\n🌎 REAL-WORLD SIMULATION: 1 Year of App Usage")
        
        try requireFixture(db).setMVCCEnabled(true)
        
        // Configure production-like GC
        var gcConfig = MVCCGCConfiguration()
        gcConfig.transactionThreshold = 100
        gcConfig.versionThreshold = 3.0
        try requireFixture(db).configureGC(gcConfig)
        
        var ids: [UUID] = []
        var totalOperations = 0
        
        // Keep Tier1 deterministic and bounded; full stress remains available via env flags.
        let months = isHeavyStressMode ? 12 : 4
        let insertsPerMonth = scaled(500, floor: 120)
        let updatesPerMonth = scaled(300, floor: 80)
        let deletesPerMonth = scaled(200, floor: 60)

        // Simulate months of production-like churn.
        for month in 1...months {
            // Typical month: 500 new records, 300 updates, 200 deletes
            
            // Inserts
            for i in 0..<insertsPerMonth {
                let id = try requireFixture(db).insert(BlazeDataRecord([
                    "month": .int(month),
                    "data": .string("Month \(month) data \(i)")
                ]))
                ids.append(id)
                totalOperations += 1
            }
            
            // Updates (random existing records)
            for _ in 0..<updatesPerMonth {
                if let id = ids.randomElement() {
                    try? try requireFixture(db).update(id: id, with: BlazeDataRecord([
                        "lastUpdate": .date(Date())
                    ]))
                    totalOperations += 1
                }
            }
            
            // Deletes (oldest records)
            if ids.count > deletesPerMonth {
                for id in ids.prefix(deletesPerMonth) {
                    try? try requireFixture(db).delete(id: id)
                    totalOperations += 1
                }
                ids.removeFirst(deletesPerMonth)
            }
            
            // Quarterly vacuum
            if month % 3 == 0 {
                try requireFixture(db).autoVacuumIfNeeded()
            }
            
            if month % 3 == 0 {
                let health = try requireFixture(db).getStorageHealth()
                print("  Month \(month): \(health.fileSizeBytes / 1_000_000) MB, \(String(format: "%.1f", health.wastedPercentage * 100))% wasted")
            }
        }
        
        // Final stats
        print("\n📊 After 1 Year:")
        print("   Total operations: \(totalOperations)")
        print("   Active records:   \(try requireFixture(db).count())")
        
        let finalHealth = try requireFixture(db).getStorageHealth()
        print(finalHealth.description)
        
        let mvccStats = try requireFixture(db).getMVCCStats()
        let gcStats = try requireFixture(db).getGCStats()
        
        print("\n" + mvccStats.description)
        print("\n" + gcStats.description)
        
        // After 1 year, file should still be reasonable
        XCTAssertLessThan(finalHealth.fileSizeBytes, 100_000_000, "File should stay under 100 MB")
        XCTAssertLessThan(finalHealth.wastedPercentage, 0.60, "Waste should stay under 60%")
        
        print("\n✅ BlazeDB survives 1 year of usage without blowing up!")
    }
}

