//
//  PerformanceProfilingTests.swift
//  BlazeDBTests
//
//  LEVEL 10: Automated Performance Profiling
//
//  Identifies performance bottlenecks automatically using XCTest metrics.
//  Tracks CPU, memory, disk I/O, and clock time for all operations.
//
//  Created: 2025-11-12
//

import XCTest
@testable import BlazeDBCore

/// Automated performance profiling - finds bottlenecks
final class PerformanceProfilingTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Profile-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try! BlazeDBClient(name: "profile_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Profiling Infrastructure
    
    /// Profile with all metrics
    private func profileWithMetrics(name: String, block: () throws -> Void) rethrows {
        let metrics: [XCTMetric] = [
            XCTClockMetric(),           // Wall clock time
            XCTCPUMetric(),             // CPU usage
            XCTMemoryMetric(),          // Memory footprint
            XCTStorageMetric()          // Disk I/O
        ]
        
        let options = XCTMeasureOptions()
        options.iterationCount = 5  // Run 5 times for average
        
        measure(metrics: metrics, options: options) {
            try? block()
        }
    }
    
    // MARK: - Insert Performance Profiling
    
    /// PROFILE: Single record insert
    func testProfile_SingleInsert() throws {
        try profileWithMetrics(name: "Single Insert") {
            _ = try db.insert(BlazeDataRecord([
                "name": .string("Test User"),
                "age": .int(30),
                "active": .bool(true)
            ]))
        }
    }
    
    /// PROFILE: Batch insert (1,000 records)
    func testProfile_BatchInsert1000() throws {
        try profileWithMetrics(name: "Batch Insert 1000") {
            let records = (0..<1000).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "name": .string("User \(i)"),
                    "value": .double(Double(i) * 1.5)
                ])
            }
            _ = try db.insertMany(records)
        }
    }
    
    /// PROFILE: Large record insert (1MB)
    func testProfile_LargeRecordInsert() throws {
        try profileWithMetrics(name: "Large Record Insert") {
            let largeData = Data(repeating: 0xFF, count: 1_000_000)
            _ = try db.insert(BlazeDataRecord([
                "blob": .data(largeData)
            ]))
        }
    }
    
    // MARK: - Fetch Performance Profiling
    
    /// PROFILE: Fetch single record
    func testProfile_SingleFetch() throws {
        // Setup
        let id = try! db.insert(BlazeDataRecord(["test": .string("value")]))
        
        try profileWithMetrics(name: "Single Fetch") {
            _ = try db.fetch(id: id)
        }
    }
    
    /// PROFILE: Fetch all (10,000 records)
    func testProfile_FetchAll10000() throws {
        // Setup
        let records = (0..<10_000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try! db.insertMany(records)
        
        try profileWithMetrics(name: "Fetch All 10000") {
            let all = try db.fetchAll()
            XCTAssertEqual(all.count, 10_000)
        }
    }
    
    // MARK: - Query Performance Profiling
    
    /// PROFILE: Simple query with filter
    func testProfile_SimpleQuery() throws {
        // Setup
        for i in 0..<5000 {
            try! db.insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "active" : "inactive"),
                "value": .int(i)
            ]))
        }
        
        try profileWithMetrics(name: "Simple Query") {
            let results = try db.query()
                .where("status", equals: .string("active"))
                .execute()
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    /// PROFILE: Complex query with multiple filters
    func testProfile_ComplexQuery() throws {
        // Setup
        for i in 0..<5000 {
            try! db.insert(BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "active" : "inactive"),
                "priority": .int(i % 5),
                "value": .int(i),
                "category": .string(i % 10 == 0 ? "A" : "B")
            ]))
        }
        
        try profileWithMetrics(name: "Complex Query") {
            let results = try db.query()
                .where("status", equals: .string("active"))
                .where("priority", greaterThan: .int(2))
                .where("value", lessThan: .int(4000))
                .execute()
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    // MARK: - Aggregation Performance Profiling
    
    /// PROFILE: Sum aggregation
    func testProfile_SumAggregation() throws {
        // Setup
        for i in 0..<10_000 {
            try! db.insert(BlazeDataRecord([
                "value": .int(i)
            ]))
        }
        
        try profileWithMetrics(name: "Sum Aggregation") {
            let result = try db.query()
                .sum("value", as: "total")
                .executeAggregation()
            XCTAssertNotNil(result.sum("total"))
        }
    }
    
    /// PROFILE: Grouped aggregation
    func testProfile_GroupedAggregation() throws {
        // Setup
        for i in 0..<10_000 {
            try! db.insert(BlazeDataRecord([
                "category": .string(i % 5 == 0 ? "A" : "B"),
                "value": .int(i)
            ]))
        }
        
        try profileWithMetrics(name: "Grouped Aggregation") {
            let result = try db.query()
                .groupBy("category")
                .sum("value", as: "total")
                .executeGroupedAggregation()
            XCTAssertGreaterThan(result.groups.count, 0)
        }
    }
    
    // MARK: - Update Performance Profiling
    
    /// PROFILE: Single update
    func testProfile_SingleUpdate() throws {
        // Setup
        let id = try! db.insert(BlazeDataRecord([
            "name": .string("Original"),
            "value": .int(100)
        ]))
        
        try profileWithMetrics(name: "Single Update") {
            try db.update(id: id, with: BlazeDataRecord([
                "name": .string("Updated")
            ]))
        }
    }
    
    /// PROFILE: Batch update (1,000 records)
    func testProfile_BatchUpdate1000() throws {
        // Setup
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try! db.insert(BlazeDataRecord([
                "index": .int(i),
                "value": .string("Original")
            ]))
            ids.append(id)
        }
        
        try profileWithMetrics(name: "Batch Update 1000") {
            for id in ids {
                try db.update(id: id, with: BlazeDataRecord([
                    "value": .string("Updated")
                ]))
            }
        }
    }
    
    // MARK: - Delete Performance Profiling
    
    /// PROFILE: Single delete
    func testProfile_SingleDelete() throws {
        // Setup
        let id = try! db.insert(BlazeDataRecord(["test": .string("value")]))
        
        try profileWithMetrics(name: "Single Delete") {
            try db.delete(id: id)
        }
    }
    
    /// PROFILE: Batch delete (1,000 records)
    func testProfile_BatchDelete1000() throws {
        // Setup
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try! db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        try profileWithMetrics(name: "Batch Delete 1000") {
            for id in ids {
                try db.delete(id: id)
            }
        }
    }
    
    // MARK: - Persistence Performance Profiling
    
    /// PROFILE: Persist 1,000 records
    func testProfile_Persist1000() throws {
        // Setup
        let records = (0..<1000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try! db.insertMany(records)
        
        try profileWithMetrics(name: "Persist 1000") {
            try db.persist()
        }
    }
    
    /// PROFILE: Persist 10,000 records
    func testProfile_Persist10000() throws {
        // Setup
        let records = (0..<10_000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try! db.insertMany(records)
        
        try profileWithMetrics(name: "Persist 10000") {
            try db.persist()
        }
    }
    
    // MARK: - Concurrent Performance Profiling
    
    /// PROFILE: Concurrent inserts (100 threads × 10 records)
    func testProfile_ConcurrentInserts() throws {
        try profileWithMetrics(name: "Concurrent Inserts") {
            let group = DispatchGroup()
            
            for i in 0..<100 {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    
                    for j in 0..<10 {
                        try? self.db.insert(BlazeDataRecord([
                            "thread": .int(i),
                            "index": .int(j)
                        ]))
                    }
                }
            }
            
            group.wait()
        }
    }
    
    /// PROFILE: Concurrent reads (1,000 operations)
    func testProfile_ConcurrentReads() throws {
        // Setup
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try! db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        try profileWithMetrics(name: "Concurrent Reads") {
            let group = DispatchGroup()
            
            for _ in 0..<1000 {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    
                    if let id = ids.randomElement() {
                        _ = try? self.db.fetch(id: id)
                    }
                }
            }
            
            group.wait()
        }
    }
    
    // MARK: - Memory Profiling
    
    /// PROFILE: Memory usage during large batch insert
    func testProfile_MemoryUsage() throws {
        try profileWithMetrics(name: "Memory Usage Large Batch") {
            let records = (0..<50_000).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "name": .string("User \(i)"),
                    "data": .string(String(repeating: "x", count: 100))
                ])
            }
            _ = try db.insertMany(records)
        }
    }
    
    // MARK: - Disk I/O Profiling
    
    /// PROFILE: Disk writes (10,000 small records)
    func testProfile_DiskWrites() throws {
        try profileWithMetrics(name: "Disk Writes 10000") {
            for i in 0..<10_000 {
                try? db.insert(BlazeDataRecord(["i": .int(i)]))
            }
        }
    }
    
    /// PROFILE: Disk reads (fetch all)
    func testProfile_DiskReads() throws {
        // Setup
        for i in 0..<10_000 {
            try! db.insert(BlazeDataRecord(["i": .int(i)]))
        }
        try! db.persist()
        
        // Reopen to force disk read
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try! BlazeDBClient(name: "profile_test", fileURL: tempURL, password: "test-pass-123")
        
        try profileWithMetrics(name: "Disk Reads 10000") {
            let all = try db.fetchAll()
            XCTAssertEqual(all.count, 10_000)
        }
    }
    
    // MARK: - CPU Profiling
    
    /// PROFILE: CPU-intensive query (complex filters)
    func testProfile_CPUIntensiveQuery() throws {
        // Setup
        for i in 0..<20_000 {
            try! db.insert(BlazeDataRecord([
                "a": .int(i),
                "b": .string("value\(i)"),
                "c": .double(Double(i) * 1.5),
                "d": .bool(i % 2 == 0)
            ]))
        }
        
        try profileWithMetrics(name: "CPU Intensive Query") {
            let results = try db.query()
                .where("a", greaterThan: .int(5000))
                .where("a", lessThan: .int(15000))
                .where("d", equals: .bool(true))
                .execute()
            XCTAssertGreaterThan(results.count, 0)
        }
    }
}

