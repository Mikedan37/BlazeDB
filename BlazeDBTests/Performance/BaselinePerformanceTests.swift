//
//  BaselinePerformanceTests.swift
//  BlazeDBTests
//
//  LEVEL 10: Baseline Tracking - Performance Regression Detection
//
//  This tracks performance over time and alerts on regressions.
//  Each test records its execution time and compares to historical baseline.
//
//  Created: 2025-11-12
//

import XCTest
@testable import BlazeDBCore

/// Performance baseline tracker - detects regressions automatically
///
/// ⚠️ IMPORTANT: These tests are SLOW by design (30-60 seconds each!)
/// They're performance benchmarks, not unit tests.
///
/// To skip in normal test runs:
/// ```bash
/// swift test --skip BaselinePerformanceTests
/// ```
///
/// To run only baselines:
/// ```bash
/// swift test --filter BaselinePerformanceTests
/// ```
///
/// These tests:
/// - Insert 10,000-100,000 records
/// - Measure performance over time
/// - Detect regressions automatically
/// - Store baselines in `/tmp/blazedb_baselines.json`
///
final class BaselinePerformanceTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    // Baseline storage
    static let baselineFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazedb_baselines.json")
    
    override func setUp() {
        super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Baseline-\(testID).blazedb")
        
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        
        // Also clean up transaction log to prevent WAL replay from previous tests
        let txnLogURL = tempURL.deletingLastPathComponent().appendingPathComponent("txn_log.json")
        try? FileManager.default.removeItem(at: txnLogURL)
        
        db = try! BlazeDBClient(name: "baseline_test", fileURL: tempURL, password: "test-pass-123")
    }
    
    override func tearDown() {
        cleanupBlazeDB(&db, at: tempURL)
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Baseline Infrastructure
    
    /// Performance baseline record
    struct Baseline: Codable {
        let testName: String
        let averageTime: Double  // seconds
        let lastRun: Date
        let runCount: Int
        let stdDeviation: Double
    }
    
    /// Load baselines from disk
    private func loadBaselines() -> [String: Baseline] {
        guard let data = try? Data(contentsOf: Self.baselineFile),
              let baselines = try? JSONDecoder().decode([String: Baseline].self, from: data) else {
            return [:]
        }
        return baselines
    }
    
    /// Save baselines to disk
    private func saveBaselines(_ baselines: [String: Baseline]) {
        guard let data = try? JSONEncoder().encode(baselines) else { return }
        try? data.write(to: Self.baselineFile, options: .atomic)
    }
    
    /// Record a benchmark result and check for regression
    private func recordBenchmark(name: String, time: Double, allowedRegression: Double = 0.20) {
        var baselines = loadBaselines()
        
        if let existing = baselines[name] {
            // Compare to baseline
            let baseline = existing.averageTime
            let regression = (time - baseline) / baseline
            
            print("\n📊 BENCHMARK: \(name)")
            print("   Current:  \(String(format: "%.3f", time))s")
            print("   Baseline: \(String(format: "%.3f", baseline))s")
            print("   Change:   \(String(format: "%+.1f", regression * 100))%")
            
            // Alert on significant regression
            if regression > allowedRegression {
                XCTFail("""
                    ⚠️ PERFORMANCE REGRESSION DETECTED!
                    
                    Test: \(name)
                    Current: \(String(format: "%.3f", time))s
                    Baseline: \(String(format: "%.3f", baseline))s
                    Regression: \(String(format: "+%.1f", regression * 100))%
                    Allowed: \(String(format: "%.0f", allowedRegression * 100))%
                    
                    This test is running \(String(format: "%.0f", regression * 100))% slower than baseline!
                    """)
            } else if regression < -0.10 {
                print("   ✅ PERFORMANCE IMPROVEMENT! \(String(format: "%.1f", -regression * 100))% faster")
            } else {
                print("   ✅ Within acceptable range")
            }
            
            // Update rolling average
            let newCount = existing.runCount + 1
            let newAverage = (existing.averageTime * Double(existing.runCount) + time) / Double(newCount)
            
            baselines[name] = Baseline(
                testName: name,
                averageTime: newAverage,
                lastRun: Date(),
                runCount: newCount,
                stdDeviation: 0.0  // TODO: Calculate actual std dev
            )
        } else {
            // First run - establish baseline
            print("\n📊 BASELINE ESTABLISHED: \(name)")
            print("   Time: \(String(format: "%.3f", time))s")
            print("   This will be the performance baseline for future runs")
            
            baselines[name] = Baseline(
                testName: name,
                averageTime: time,
                lastRun: Date(),
                runCount: 1,
                stdDeviation: 0.0
            )
        }
        
        saveBaselines(baselines)
    }
    
    /// Measure execution time of a block
    private func measure(name: String, allowedRegression: Double = 0.20, block: () throws -> Void) rethrows {
        let start = Date()
        try block()
        let duration = Date().timeIntervalSince(start)
        
        recordBenchmark(name: name, time: duration, allowedRegression: allowedRegression)
    }
    
    // MARK: - Baseline Benchmarks
    
    /// BASELINE: Insert 1,000 records
    func testBaseline_Insert1000Records() throws {
        try measure(name: "Insert_1000_Records", allowedRegression: 0.20) {
            for i in 0..<1000 {
                try db.insert(BlazeDataRecord([
                    "index": .int(i),
                    "name": .string("User \(i)"),
                    "value": .double(Double(i) * 1.5)
                ]))
            }
        }
    }
    
    /// BASELINE: Batch insert 10,000 records
    func testBaseline_BatchInsert10000Records() throws {
        try measure(name: "BatchInsert_10000_Records", allowedRegression: 0.15) {
            let records = (0..<10_000).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "name": .string("User \(i)"),
                    "value": .double(Double(i) * 1.5)
                ])
            }
            _ = try db.insertMany(records)
        }
    }
    
    /// BASELINE: Fetch all 10,000 records
    func testBaseline_FetchAll10000Records() throws {
        // Setup: Insert 10k records
        let records = (0..<10_000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "name": .string("User \(i)")
            ])
        }
        _ = try db.insertMany(records)
        
        try measure(name: "FetchAll_10000_Records", allowedRegression: 0.20) {
            let all = try db.fetchAll()
            XCTAssertEqual(all.count, 10_000)
        }
    }
    
    /// BASELINE: Query with filter (10,000 records)
    func testBaseline_QueryWithFilter() throws {
        // Setup - Use batch insert for speed!
        let records = (0..<10_000).map { i in
            BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "active" : "inactive"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        try measure(name: "Query_With_Filter", allowedRegression: 0.20) {
            let results = try db.query()
                .where("status", equals: .string("active"))
                .execute()
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    /// BASELINE: Aggregation on 10,000 records
    func testBaseline_Aggregation() throws {
        // Setup - Use batch insert for speed!
        let records = (0..<10_000).map { i in
            BlazeDataRecord([
                "category": .string(i % 5 == 0 ? "A" : "B"),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        try measure(name: "Aggregation_Sum_10000", allowedRegression: 0.20) {
            let result = try db.query()
                .sum("value", as: "total")
                .executeAggregation()
            XCTAssertNotNil(result.sum("total"))
        }
    }
    
    /// BASELINE: Update 1,000 records
    func testBaseline_Update1000Records() throws {
        // Setup - Use batch insert for faster test setup
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "value": .string("Original")
            ])
        }
        let ids = try db.insertMany(records)
        
        try measure(name: "Update_1000_Records", allowedRegression: 0.20) {
            for id in ids {
                try db.update(id: id, with: BlazeDataRecord([
                    "value": .string("Updated")
                ]))
            }
        }
    }
    
    /// BASELINE: Delete 1,000 records
    func testBaseline_Delete1000Records() throws {
        // Setup - Use batch insert for faster test setup
        let records = (0..<1000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        let ids = try db.insertMany(records)
        
        try measure(name: "Delete_1000_Records", allowedRegression: 0.20) {
            for id in ids {
                try db.delete(id: id)
            }
        }
    }
    
    /// BASELINE: Persist 10,000 records
    func testBaseline_Persist10000Records() throws {
        // Setup
        let records = (0..<10_000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        _ = try db.insertMany(records)
        
        try measure(name: "Persist_10000_Records", allowedRegression: 0.25) {
            try db.persist()
        }
    }
    
    /// BASELINE: Concurrent inserts (100 threads × 10 records)
    func testBaseline_ConcurrentInserts() throws {
        try measure(name: "Concurrent_Inserts_1000", allowedRegression: 0.30) {
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
    
    /// BASELINE: Mixed workload (read-heavy)
    func testBaseline_MixedWorkloadReadHeavy() throws {
        // Setup - Use batch insert for faster test setup
        let records = (0..<1000).map { i in
            BlazeDataRecord(["index": .int(i)])
        }
        var ids = try db.insertMany(records)
        
        try measure(name: "Mixed_Workload_ReadHeavy", allowedRegression: 0.25) {
            for _ in 0..<1000 {
                let op = Int.random(in: 0...10)
                
                if op < 8 {  // 80% reads
                    if let id = ids.randomElement() {
                        _ = try? db.fetch(id: id)
                    }
                } else if op < 9 {  // 10% updates
                    if let id = ids.randomElement() {
                        try? db.update(id: id, with: BlazeDataRecord(["value": .int(Int.random(in: 0...100))]))
                    }
                } else {  // 10% inserts
                    let id = try db.insert(BlazeDataRecord(["index": .int(Int.random(in: 0...1000))]))
                    ids.append(id)
                }
            }
        }
    }
    
    // MARK: - Stress Test Baselines
    
    /// BASELINE: Large record insert (3KB - within page limit)
    func testBaseline_LargeRecordInsert() throws {
        // ⚠️ NOTE: Single records limited to ~4KB (page size)
        // 1MB would exceed limit, so we test 3KB instead
        try measure(name: "LargeRecord_Insert_3KB", allowedRegression: 0.30) {
            let largeData = Data(repeating: 0xFF, count: 3_000)  // 3KB (fits in page)
            _ = try db.insert(BlazeDataRecord([
                "blob": .data(largeData)
            ]))
        }
    }
    
    /// BASELINE: Many small records (100,000)
    func testBaseline_ManySmallRecords() throws {
        try measure(name: "ManySmallRecords_100000", allowedRegression: 0.20) {
            let records = (0..<100_000).map { i in
                BlazeDataRecord(["i": .int(i)])
            }
            _ = try db.insertMany(records)
        }
    }
    
    /// BASELINE: Complex query (multiple filters)
    func testBaseline_ComplexQuery() throws {
        // Setup - Use batch insert for speed!
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "status": .string(i % 3 == 0 ? "active" : "inactive"),
                "priority": .int(i % 5),
                "value": .int(i)
            ])
        }
        _ = try db.insertMany(records)
        
        try measure(name: "ComplexQuery_MultipleFilters", allowedRegression: 0.25) {
            let results = try db.query()
                .where("status", equals: .string("active"))
                .where("priority", greaterThan: .int(2))
                .where("value", lessThan: .int(4000))
                .execute()
            XCTAssertGreaterThan(results.count, 0)
        }
    }
    
    // MARK: - Report Generation
    
    /// Generate performance report (run this manually)
    func testGeneratePerformanceReport() {
        let baselines = loadBaselines()
        
        print("\n" + String(repeating: "=", count: 80))
        print("📊 BLAZEDB PERFORMANCE REPORT")
        print(String(repeating: "=", count: 80))
        print("\nDate: \(Date())")
        print("Total Benchmarks: \(baselines.count)")
        print("\n" + String(repeating: "-", count: 80))
        
        // Sort by test name
        let sorted = baselines.values.sorted { $0.testName < $1.testName }
        
        for baseline in sorted {
            print("\n\(baseline.testName):")
            print("  Average Time: \(String(format: "%.3f", baseline.averageTime))s")
            print("  Last Run:     \(baseline.lastRun)")
            print("  Run Count:    \(baseline.runCount)")
        }
        
        print("\n" + String(repeating: "=", count: 80))
        
        // Also write to file
        let reportFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_performance_report.txt")
        
        var report = """
        BLAZEDB PERFORMANCE REPORT
        Generated: \(Date())
        Total Benchmarks: \(baselines.count)
        
        """
        
        for baseline in sorted {
            report += """
            \n\(baseline.testName):
              Average: \(String(format: "%.3f", baseline.averageTime))s
              Runs: \(baseline.runCount)
            
            """
        }
        
        try? report.write(to: reportFile, atomically: true, encoding: .utf8)
        print("\n📄 Report saved to: \(reportFile.path)")
    }
}

