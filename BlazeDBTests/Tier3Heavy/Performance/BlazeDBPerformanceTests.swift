//  BlazeDBPerformanceTests.swift
//  BlazeDB Performance Benchmarks
//  Uses XCTMetric for Xcode integration and baseline tracking

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

final class BlazeDBPerformanceTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!

    #if !os(Linux)
    /// XCTest `measure` on GitHub runners: one iteration, omit memory metric when it amplifies peak RSS / OOM risk.
    private enum CIMeasure {
        static var isGitHubActions: Bool {
            ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        }
        static func options(iterations: Int) -> XCTMeasureOptions {
            let o = XCTMeasureOptions()
            o.iterationCount = isGitHubActions ? 1 : iterations
            return o
        }
    }
    #endif
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazePerf-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "PerfTest", fileURL: tempURL, password: "TestPassword-123!")
    }
    
    override func tearDownWithError() throws {
        if let collection = db?.collection {
            try? collection.persist()
        }
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
    }
    
    // MARK: - Insert Performance
    
    /// Measure single insert performance
    func testInsertPerformance() throws {
        let runWorkload: () -> Void = {
            for i in 0..<100 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "title": .string("Record \(i)"),
                    "timestamp": .date(Date())
                ])
                _ = try! self.db.insert(record)
            }
            
            // Flush for accurate measurement
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        let mem: [XCTMetric] = CIMeasure.isGitHubActions ? [] : [XCTMemoryMetric()]
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()] + mem,
            options: CIMeasure.options(iterations: 5),
            block: runWorkload
        )
        #endif
    }
    
    /// Measure bulk insert performance
    /// Test ACTUAL bulk/batch insert performance (using insertMany)
    func testBulkInsertPerformance() throws {
        print("⚡ Testing BATCH insert performance (500 records)...")
        
        let runWorkload: () -> Void = {
            // Create 500 records
            let records = (0..<500).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 200))
                ])
            }
            
            // Insert in ONE batch operation (50-100x faster!)
            _ = try! self.db.insertMany(records)
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        let mem: [XCTMetric] = CIMeasure.isGitHubActions ? [] : [XCTMemoryMetric()]
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()] + mem + [XCTStorageMetric()],
            options: CIMeasure.options(iterations: 3),
            block: runWorkload
        )
        #endif
        
        print("✅ Batch insert performance measured")
    }
    
    /// Test individual insert performance (baseline for comparison)
    func testIndividualInsertPerformance() throws {
        print("⚡ Testing INDIVIDUAL insert performance (100 records)...")
        
        let runWorkload: () -> Void = {
            // Insert one-by-one (slower, but sometimes necessary)
            for i in 0..<100 {  // Reduced to 100 for faster tests
                _ = try! self.db.insert(BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 200))
                ]))
            }
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(metrics: [XCTClockMetric()], options: CIMeasure.options(iterations: 3), block: runWorkload)
        #endif
        
        print("✅ Individual insert performance measured")
    }
    
    // MARK: - Read Performance
    
    /// Measure single fetch performance
    func testFetchByIDPerformance() throws {
        // Setup: Insert 300 records
        var ids: [UUID] = []
        for i in 0..<300 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        try db.persist()
        
        let runWorkload: () -> Void = {
            for id in ids.prefix(100) {
                _ = try! self.db.fetch(id: id)
            }
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: CIMeasure.options(iterations: 10),
            block: runWorkload
        )
        #endif
    }
    
    /// Measure fetchAll performance
    func testFetchAllPerformance() throws {
        // Setup: Insert 500 records using batch insert
        let records = (0..<500).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
        }
        _ = try db.insertMany(records)
        try db.persist()
        print("  Setup: Inserted 500 records via batch")
        
        let runWorkload: () -> Void = {
            _ = try! self.db.fetchAll()
        }
        #if os(Linux)
        runWorkload()
        #else
        let metrics: [XCTMetric] = CIMeasure.isGitHubActions
            ? [XCTClockMetric()]
            : [XCTClockMetric(), XCTMemoryMetric()]
        measure(metrics: metrics, options: CIMeasure.options(iterations: 5), block: runWorkload)
        #endif
    }
    
    /// Measure pagination performance
    func testPaginationPerformance() throws {
        // Setup: Insert 500 records
        for i in 0..<500 {
            let record = BlazeDataRecord(["index": .int(i)])
            _ = try db.insert(record)
        }
        
        try db.persist()
        
        let runWorkload: () -> Void = {
            _ = try! self.db.fetchPage(offset: 0, limit: 100)
        }
        #if os(Linux)
        runWorkload()
        #else
        let metrics: [XCTMetric] = CIMeasure.isGitHubActions
            ? [XCTClockMetric()]
            : [XCTClockMetric(), XCTMemoryMetric()]
        measure(metrics: metrics, options: CIMeasure.options(iterations: 10), block: runWorkload)
        #endif
    }
    
    // MARK: - Update Performance
    
    /// Measure update performance
    func testUpdatePerformance() throws {
        // Setup: Insert 500 records
        var ids: [UUID] = []
        for i in 0..<500 {
            let record = BlazeDataRecord(["value": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        try db.persist()
        
        let runWorkload: () -> Void = {
            for (index, id) in ids.prefix(100).enumerated() {
                let updated = BlazeDataRecord(["value": .int(index + 1000)])
                try! self.db.update(id: id, with: updated)
            }
            
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(), XCTStorageMetric()],
            options: CIMeasure.options(iterations: 5),
            block: runWorkload
        )
        #endif
    }
    
    // MARK: - Delete Performance
    
    /// Measure delete performance
    func testDeletePerformance() throws {
        // Setup: Insert 500 records
        var ids: [UUID] = []
        for i in 0..<500 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try db.insert(record)
            ids.append(id)
        }
        
        try db.persist()
        
        let runWorkload: () -> Void = {
            for id in ids.prefix(100) {
                try! self.db.delete(id: id)
            }
            
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: CIMeasure.options(iterations: 5),
            block: runWorkload
        )
        #endif
    }
    
    // MARK: - Index Performance
    
    /// Measure index query performance
    func testIndexQueryPerformance() throws {
        let collection = db.collection
        
        // Setup: Create index and insert records
        try collection.createIndex(on: "category")
        
        for i in 0..<300 {
            let record = BlazeDataRecord([
                "category": .string("cat_\(i % 10)"),
                "data": .int(i)
            ])
            _ = try db.insert(record)
        }
        
        try collection.persist()
        
        // Reopen to trigger index rebuild
        db = nil
        db = try BlazeDBClient(name: "PerfTest", fileURL: tempURL, password: "TestPassword-123!")
        let rebuiltCollection = db.collection
        
        let runWorkload: () -> Void = {
            _ = try! rebuiltCollection.fetch(byIndexedField: "category", value: "cat_5")
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(metrics: [XCTClockMetric()], options: CIMeasure.options(iterations: 10), block: runWorkload)
        #endif
    }
    
    // MARK: - Transaction Performance
    
    /// Measure transaction commit performance
    func testTransactionPerformance() throws {
        let runWorkload: () -> Void = {
            for i in 0..<50 {
                // Database inserts are internally transactional
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "data": .string("Transactional \(i)")
                ])
                _ = try! self.db.insert(record)
            }
            
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: CIMeasure.options(iterations: 5),
            block: runWorkload
        )
        #endif
    }
    
    // MARK: - Encryption Performance
    
    /// Measure encryption overhead
    func testEncryptionPerformance() throws {
        let largeData = String(repeating: "X", count: 3000)  // ~3KB payload
        
        let runWorkload: () -> Void = {
            for i in 0..<100 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "payload": .string(largeData)
                ])
                _ = try! self.db.insert(record)
            }
            
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric()],
            options: CIMeasure.options(iterations: 5),
            block: runWorkload
        )
        #endif
    }
    
    // MARK: - Memory Efficiency
    
    /// Measure memory usage during operations
    func testMemoryEfficiency() throws {
        let runWorkload: () -> Void = {
            // Insert 300 records (enough to measure memory, fast enough for 3 iterations)
            for i in 0..<300 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 100))
                ])
                _ = try! self.db.insert(record)
            }
            
            try! self.db.persist()
            
            // Fetch all
            _ = try! self.db.fetchAll()
        }
        #if os(Linux)
        runWorkload()
        #else
        // On CI, memory-only measurement is replaced with wall clock so we still exercise the path without XCTMemoryMetric spikes.
        let metrics: [XCTMetric] = CIMeasure.isGitHubActions ? [XCTClockMetric()] : [XCTMemoryMetric()]
        measure(metrics: metrics, options: CIMeasure.options(iterations: 3), block: runWorkload)
        #endif
    }
    
    // MARK: - Storage I/O
    
    /// Measure disk I/O performance
    func testStorageIOPerformance() throws {
        let runWorkload: () -> Void = {
            // Use batch insert for faster, more realistic test
            let records = (0..<200).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "payload": .string(String(repeating: "X", count: 500))
                ])
            }
            _ = try! self.db.insertMany(records)
            try! self.db.persist()
        }
        #if os(Linux)
        runWorkload()
        #else
        measure(metrics: [XCTStorageMetric()], options: CIMeasure.options(iterations: 3), block: runWorkload)
        #endif
    }
}
