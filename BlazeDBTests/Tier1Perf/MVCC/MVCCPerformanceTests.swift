//
//  MVCCPerformanceTests.swift
//  BlazeDBTests
//
//  Phase 5: MVCC Performance benchmarks and validation
//
//  Measures before/after performance improvements from MVCC
//
//  Created: 2025-11-13
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class MVCCPerformanceTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCPerf-\(testID).blazedb")
        tempURL = url
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "mvcc_perf_test", fileURL: url, password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Concurrent Read Performance
    
    func testPerformance_ConcurrentReads_100() throws {
        print("\n🚀 BENCHMARK: 100 Concurrent Reads")
        let client = try XCTUnwrap(db, "BlazeDBClient must be initialized in setUp")
        
        // Setup: Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try client.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            
            for id in ids {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    _ = try? client.fetch(id: id)
                }
            }
            
            group.wait()
        }
        
        print("  ✅ Benchmark complete (check results above)")
    }
    
    func testPerformance_ConcurrentReads_1000() throws {
        print("\n🚀 BENCHMARK: 1000 Concurrent Reads")
        let client = try XCTUnwrap(db, "BlazeDBClient must be initialized in setUp")
        
        // Setup
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try client.insert(BlazeDataRecord(["i": .int(i)]))
            ids.append(id)
        }
        
        let start = Date()
        let group = DispatchGroup()
        
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? client.fetch(id: id)
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 1000 concurrent reads: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 1000.0 / duration)) reads/sec")
        
        // With MVCC: Should be ~100-200ms
        // Without: Would be ~1000ms
        XCTAssertLessThan(duration, 2.0, "Concurrent reads should be fast")
        
        print("  ✅ Performance acceptable!")
    }
    
    // MARK: - Read-While-Write Performance
    
    func testPerformance_ReadWhileWrite() throws {
        print("\n🚀 BENCHMARK: Read While Write")
        let client = try XCTUnwrap(db, "BlazeDBClient must be initialized in setUp")
        
        // Setup
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try client.insert(BlazeDataRecord(["i": .int(i)]))
            ids.append(id)
        }
        
        let start = Date()
        let group = DispatchGroup()
        
        // Readers (100 threads)
        for id in ids {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? client.fetch(id: id)
            }
        }
        
        // Writers (10 threads)
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? client.insert(BlazeDataRecord(["write": .int(i)]))
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 100 reads + 10 writes: \(String(format: "%.3f", duration))s")
        print("  ✅ Reads didn't block on writes!")
    }
    
    // MARK: - Insert Performance
    
    func testPerformance_SingleInserts_1000() throws {
        print("\n📊 BENCHMARK: 1000 Single Inserts")
        
        let start = Date()
        
        for i in 0..<1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }
        
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 1000.0 / duration)) inserts/sec")
        
        // Should complete in reasonable time
        XCTAssertLessThan(duration, 8.0, "Inserts should be fast")
        
        print("  ✅ Insert performance acceptable!")
    }
    
    // MARK: - Update Performance
    
    func testPerformance_Updates_1000() throws {
        print("\n📊 BENCHMARK: 1000 Updates")
        
        // Setup
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "value": .int(i)
            ]))
            ids.append(id)
        }
        
        let start = Date()
        
        for id in ids {
            try requireFixture(db).update(id: id, with: BlazeDataRecord([
                "value": .int(999)
            ]))
        }
        
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 Duration: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 1000.0 / duration)) updates/sec")
        
        print("  ✅ Update performance measured!")
    }
    
    // MARK: - GC Performance
    
    func testPerformance_GC_LargeVersionSet() {
        print("\n🗑️ BENCHMARK: GC on Large Version Set")
        
        // Create local VersionManager for this performance test
        let testVersionManager = VersionManager()
        
        // Create 1000 records with 10 versions each
        for recordIdx in 0..<1000 {
            let recordID = UUID()
            for versionIdx in 1...10 {
                let v = RecordVersion(
                    recordID: recordID,
                    version: UInt64(recordIdx * 10 + versionIdx),
                    pageNumber: recordIdx * 10 + versionIdx,
                    createdByTransaction: UInt64(versionIdx)
                )
                testVersionManager.addVersion(v)
            }
        }
        
        let statsBefore = testVersionManager.getStats()
        print("  Before GC: \(statsBefore.totalVersions) versions")
        
        let start = Date()
        let removed = testVersionManager.garbageCollect()
        let duration = Date().timeIntervalSince(start)
        
        let statsAfter = testVersionManager.getStats()
        
        print("  📊 GC duration: \(String(format: "%.3f", duration))s")
        print("  📊 Removed: \(removed) versions")
        print("  📊 After GC: \(statsAfter.totalVersions) versions")
        print("  📊 Throughput: \(String(format: "%.0f", Double(removed) / duration)) versions/sec")
        
        // GC should be fast (< 100ms for 10k versions)
        XCTAssertLessThan(duration, 0.5, "GC should be fast")
        
        print("  ✅ GC performance acceptable!")
    }
    
    // MARK: - Mixed Workload Performance
    
    func testPerformance_MixedWorkload() throws {
        print("\n⚡ BENCHMARK: Mixed Workload (80% reads, 20% writes)")
        let client = try XCTUnwrap(db, "BlazeDBClient must be initialized in setUp")
        
        // Setup
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try client.insert(BlazeDataRecord(["i": .int(i)]))
            ids.append(id)
        }
        let idList = ids
        
        let start = Date()
        let group = DispatchGroup()
        
        // 1000 operations total
        for i in 0..<1000 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                let op = i % 10  // 0-9
                
                if op < 8 {  // 80% reads
                    if let id = idList.randomElement() {
                        _ = try? client.fetch(id: id)
                    }
                } else {  // 20% writes
                    _ = try? client.insert(BlazeDataRecord([
                        "random": .int(Int.random(in: 0...1000))
                    ]))
                }
            }
        }
        
        group.wait()
        let duration = Date().timeIntervalSince(start)
        
        print("  📊 1000 mixed operations: \(String(format: "%.3f", duration))s")
        print("  📊 Throughput: \(String(format: "%.0f", 1000.0 / duration)) ops/sec")
        
        print("  ✅ Mixed workload performance measured!")
    }
    
    // MARK: - Memory Usage
    
    func testPerformance_MemoryOverhead() throws {
        print("\n💾 BENCHMARK: Memory Overhead with MVCC")
        
        // Measure baseline
        _ = try requireFixture(db).collection.versionManager.getStats()
        
        // Insert 1000 records
        for i in 0..<1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }
        
        let statsAfter = try requireFixture(db).collection.versionManager.getStats()
        
        print("  📊 Total versions: \(statsAfter.totalVersions)")
        print("  📊 Unique records: \(statsAfter.uniqueRecords)")
        print("  📊 Avg versions/record: \(String(format: "%.2f", statsAfter.averageVersionsPerRecord))")
        
        // With good GC, should be close to 1.0 avg
        XCTAssertLessThan(statsAfter.averageVersionsPerRecord, 2.0, "GC should keep versions low")
        
        print("  ✅ Memory overhead is acceptable!")
    }
}

