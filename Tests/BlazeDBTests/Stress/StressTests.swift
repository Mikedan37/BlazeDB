//
//  StressTests.swift
//  BlazeDBTests
//
//  Stress tests for large datasets (100k+ records)
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class StressTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip stress tests when not running in CI/CD
        guard CICDDetection.shouldRunStressTests else {
            throw XCTSkip("Stress tests only run in CI/CD environment. Set CI=true or GITHUB_ACTIONS=true to run locally.")
        }
        
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_stress_\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "TestStress", fileURL: tempURL, password: "StressTest123!")
    }
    
    override func tearDown() {
        try? db?.collection.destroy()
        try? FileManager.default.removeItem(at: tempURL)
        db = nil
        super.tearDown()
    }
    
    func testLargeDatasetInsert() throws {
        // Insert 100k records
        let startTime = Date()
        let ids = try bulkInsert(count: 100_000, batchSize: 10_000, progressEvery: 10_000) { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "value": .double(Double(i) * 1.5)
            ])
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let perHundredMs = (duration * 1000.0) / Double(100_000 / 100)
        print("Inserted 100k records in \(duration)s (\(perHundredMs)ms per 100 records)")
        
        XCTAssertEqual(ids.count, 100_000)
        XCTAssertLessThan(duration, 60.0)  // Should complete in under 60 seconds
    }
    
    func testLargeDatasetQuery() throws {
        // Insert 100k records
        _ = try bulkInsert(count: 100_000, batchSize: 10_000) { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "value": .double(Double(i) * 1.5)
            ])
        }
        
        // Query with index
        try db.collection.createIndex(on: "index")
        
        let startTime = Date()
        let results = try db.query()
            .where("index", greaterThan: .int(50_000))
            .where("index", lessThan: .int(60_000))
            .limit(100)
            .execute()
        
        let duration = Date().timeIntervalSince(startTime)
        let records = try results.records
        print("Query on 100k records took \(duration * 1000)ms, found \(records.count) results")
        
        XCTAssertEqual(records.count, 100)
        XCTAssertLessThan(duration, 1.0)  // Should be fast with index
    }
    
    func testLargeDatasetWithLazyDecoding() throws {
        // Enable lazy decoding
        try db.enableLazyDecoding()
        
        // Insert 10k records with large fields
        let largeData = Data(repeating: 0xFF, count: 10_000)
        
        let startTime = Date()
        _ = try bulkInsert(count: 10_000, batchSize: 1_000) { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "name": .string("Record \(i)"),
                "largeData": .data(largeData)
            ])
        }
        let insertTime = Date().timeIntervalSince(startTime)
        print("Inserted 10k records with large fields in \(insertTime)s")
        
        // Query with projection (should use lazy decoding)
        let queryStart = Date()
        let results = try db.query()
            .project("id", "name", "index")
            .where("index", greaterThan: .int(5_000))
            .limit(100)
            .execute()
        let queryTime = Date().timeIntervalSince(queryStart)
        
        print("Query with lazy decoding took \(queryTime * 1000)ms")
        let records = try results.records
        XCTAssertEqual(records.count, 100)
        XCTAssertLessThan(queryTime, 0.5)  // Should be fast with lazy decoding
    }
    
    func testConcurrentWrites() throws {
        // Test concurrent writes
        let expectation = XCTestExpectation(description: "Concurrent writes")
        expectation.expectedFulfillmentCount = 10
        
        let group = DispatchGroup()
        
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                var buffer: [BlazeDataRecord] = []
                buffer.reserveCapacity(200)
                
                func flush() throws {
                    guard !buffer.isEmpty else { return }
                    _ = try self.db.insertMany(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                
                do {
                    for j in 0..<1000 {
                        buffer.append(BlazeDataRecord([
                            "id": .uuid(UUID()),
                            "thread": .int(i),
                            "index": .int(j)
                        ]))
                        
                        if buffer.count == 200 {
                            try flush()
                        }
                    }
                    
                    try flush()
                } catch {
                    XCTFail("Concurrent write failed: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30.0)
        
        // Verify all records inserted
        let results = try db.query().execute()
        let records = try results.records
        XCTAssertEqual(records.count, 10_000)
    }
    
    func testMemoryUsage() throws {
        // Insert 50k records
        let ids = try bulkInsert(count: 50_000, batchSize: 5_000) { i in
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 100))
            ])
        }
        
        // Query all (should not cause memory issues)
        let results = try db.query()
            .limit(10_000)
            .execute()
        
        let records = try results.records
        XCTAssertEqual(records.count, 10_000)
        
        // Memory should be reasonable (test passes if no crash)
    }
}

// MARK: - Helpers

private extension StressTests {
    
    @discardableResult
    func bulkInsert(count: Int, batchSize: Int = 5_000, progressEvery: Int? = nil, builder: (Int) -> BlazeDataRecord) throws -> [UUID] {
        precondition(count >= 0, "Count must be non-negative")
        precondition(batchSize > 0, "Batch size must be positive")
        
        guard count > 0 else { return [] }
        
        guard let db else {
            XCTFail("Database not initialized")
            return []
        }
        
        var ids: [UUID] = []
        ids.reserveCapacity(count)
        var buffer: [BlazeDataRecord] = []
        buffer.reserveCapacity(min(batchSize, count))
        var inserted = 0
        
        func flush() throws {
            guard !buffer.isEmpty else { return }
            let batchIds = try db.insertMany(buffer)
            ids.append(contentsOf: batchIds)
            inserted += batchIds.count
            buffer.removeAll(keepingCapacity: true)
            
            if let progressEvery {
                if inserted % progressEvery == 0 || inserted == count {
                    print("Inserted \(inserted) records...")
                }
            }
        }
        
        for i in 0..<count {
            buffer.append(builder(i))
            if buffer.count == batchSize {
                try flush()
            }
        }
        
        try flush()
        return ids
    }
}

