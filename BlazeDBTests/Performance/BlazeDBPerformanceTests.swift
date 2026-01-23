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
    
    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazePerf-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "PerfTest", fileURL: tempURL, password: "test-password-123")
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
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for i in 0..<100 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "title": .string("Record \(i)"),
                    "timestamp": .date(Date())
                ])
                _ = try! db.insert(record)
            }
            
            // Flush for accurate measurement
            try! db.persist()
        }
    }
    
    /// Measure bulk insert performance
    /// Test ACTUAL bulk/batch insert performance (using insertMany)
    func testBulkInsertPerformance() throws {
        print("⚡ Testing BATCH insert performance (500 records)...")
        
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        
        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric(),
            XCTStorageMetric()
        ], options: options) {
            // Create 500 records
            let records = (0..<500).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 200))
                ])
            }
            
            // Insert in ONE batch operation (50-100x faster!)
            _ = try! db.insertMany(records)
            try! db.persist()
        }
        
        print("✅ Batch insert performance measured")
    }
    
    /// Test individual insert performance (baseline for comparison)
    func testIndividualInsertPerformance() throws {
        print("⚡ Testing INDIVIDUAL insert performance (100 records)...")
        
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        
        measure(metrics: [XCTClockMetric()], options: options) {
            // Insert one-by-one (slower, but sometimes necessary)
            for i in 0..<100 {  // Reduced to 100 for faster tests
                _ = try! db.insert(BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 200))
                ]))
            }
        }
        
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
        
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for id in ids.prefix(100) {
                _ = try! db.fetch(id: id)
            }
        }
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
        
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [
            XCTClockMetric(),
            XCTMemoryMetric()
        ], options: options) {
            _ = try! db.fetchAll()
        }
    }
    
    /// Measure pagination performance
    func testPaginationPerformance() throws {
        // Setup: Insert 500 records
        for i in 0..<500 {
            let record = BlazeDataRecord(["index": .int(i)])
            _ = try db.insert(record)
        }
        
            try db.persist()
        
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            _ = try! db.fetchPage(offset: 0, limit: 100)
        }
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
        
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTStorageMetric()], options: options) {
            for (index, id) in ids.prefix(100).enumerated() {
                let updated = BlazeDataRecord(["value": .int(index + 1000)])
                try! db.update(id: id, with: updated)
            }
            
            try! db.persist()
        }
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
        
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for id in ids.prefix(100) {
                try! db.delete(id: id)
            }
            
            try! db.persist()
        }
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
        db = try BlazeDBClient(name: "PerfTest", fileURL: tempURL, password: "test-password-123")
        let rebuiltCollection = db.collection
        
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = try! rebuiltCollection.fetch(byIndexedField: "category", value: "cat_5")
        }
    }
    
    // MARK: - Transaction Performance
    
    /// Measure transaction commit performance
    func testTransactionPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for i in 0..<50 {
                // Database inserts are internally transactional
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "data": .string("Transactional \(i)")
                ])
                _ = try! db.insert(record)
            }
            
            try! db.persist()
        }
    }
    
    // MARK: - Encryption Performance
    
    /// Measure encryption overhead
    func testEncryptionPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        
        let largeData = String(repeating: "X", count: 3000)  // ~3KB payload
        
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for i in 0..<100 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "payload": .string(largeData)
                ])
                _ = try! db.insert(record)
            }
            
            try! db.persist()
        }
    }
    
    // MARK: - Memory Efficiency
    
    /// Measure memory usage during operations
    func testMemoryEfficiency() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        
        measure(metrics: [XCTMemoryMetric()], options: options) {
            // Insert 300 records (enough to measure memory, fast enough for 3 iterations)
            for i in 0..<300 {
                let record = BlazeDataRecord([
                    "index": .int(i),
                    "data": .string(String(repeating: "A", count: 100))
                ])
                _ = try! db.insert(record)
            }
            
            try! db.persist()
            
            // Fetch all
            _ = try! db.fetchAll()
        }
    }
    
    // MARK: - Storage I/O
    
    /// Measure disk I/O performance
    func testStorageIOPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        
        measure(metrics: [XCTStorageMetric()], options: options) {
            // Use batch insert for faster, more realistic test
            let records = (0..<200).map { i in
                BlazeDataRecord([
                    "index": .int(i),
                    "payload": .string(String(repeating: "X", count: 500))
                ])
            }
            _ = try! db.insertMany(records)
            try! db.persist()
        }
    }
}

