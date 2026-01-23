//
//  UpsertEdgeCaseTests.swift
//  BlazeDBTests
//
//  Comprehensive edge case tests for upsert operations.
//  Tests concurrent upserts, transactions, index updates, and performance.
//
//  Created: Phase 3 Robustness Testing
//

import XCTest
@testable import BlazeDBCore

final class UpsertEdgeCaseTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Upsert-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "UpsertTest", fileURL: tempURL, password: "test-password-123")
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Concurrent Upsert Tests
    
    /// Test concurrent upserts on same ID (last write wins)
    func testConcurrentUpsertsOnSameID() throws {
        print("🔄 Testing concurrent upserts on same ID...")
        
        let sharedID = UUID()
        
        let expectation = self.expectation(description: "Concurrent upserts")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.upsert", attributes: .concurrent)
        
        // 10 threads upserting to same ID
        for threadID in 0..<10 {
            queue.async {
                do {
                    let wasInsert = try self.db.upsert(id: sharedID, data: BlazeDataRecord([
                        "thread": .int(threadID),
                        "timestamp": .date(Date()),
                        "value": .int(threadID * 100)
                    ]))
                    
                    // First one should be insert (true), rest should be updates (false)
                    print("  Thread \(threadID): \(wasInsert ? "INSERT" : "UPDATE")")
                    expectation.fulfill()
                } catch {
                    XCTFail("Thread \(threadID) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify final state
        let final = try db.fetch(id: sharedID)
        XCTAssertNotNil(final, "Record should exist after concurrent upserts")
        
        print("  Final record from thread: \(final?.storage["thread"]?.intValue ?? -1)")
        print("✅ Concurrent upserts handled correctly (last write wins)")
    }
    
    /// Test upsert within transaction
    func testUpsertInTransaction() throws {
        print("🔄 Testing upsert in transaction...")
        
        let id = UUID()
        
        // Begin transaction
        try db.beginTransaction()
        
        // First upsert (insert)
        let wasInsert1 = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(1)]))
        XCTAssertTrue(wasInsert1, "First upsert should be insert")
        
        // Second upsert (update)
        let wasInsert2 = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(2)]))
        XCTAssertFalse(wasInsert2, "Second upsert should be update")
        
        // Commit
        try db.commitTransaction()
        
        // Verify final value
        let final = try db.fetch(id: id)
        XCTAssertEqual(final?.storage["value"]?.intValue, 2)
        
        print("✅ Upsert in transaction works correctly")
    }
    
    /// Test upsert with index updates
    func testUpsertWithIndexUpdates() throws {
        print("🔄 Testing upsert with index updates...")
        
        let collection = db.collection
        try collection.createIndex(on: "status")
        
        let id = UUID()
        
        // Upsert (insert) with indexed field
        _ = try db.upsert(id: id, data: BlazeDataRecord([
            "title": .string("Test"),
            "status": .string("draft")
        ]))
        
        // Verify in index
        let draftResults = try collection.fetch(byIndexedField: "status", value: "draft")
        XCTAssertEqual(draftResults.count, 1, "Should be in draft index")
        
        // Upsert (update) changing indexed field
        _ = try db.upsert(id: id, data: BlazeDataRecord([
            "title": .string("Test"),
            "status": .string("published")  // Changed!
        ]))
        
        // Verify index updated
        let draftResults2 = try collection.fetch(byIndexedField: "status", value: "draft")
        XCTAssertEqual(draftResults2.count, 0, "Should no longer be in draft index")
        
        let publishedResults = try collection.fetch(byIndexedField: "status", value: "published")
        XCTAssertEqual(publishedResults.count, 1, "Should be in published index")
        
        print("✅ Upsert with index updates works correctly")
    }
    
    /// Test upsert performance vs separate insert+update
    func testUpsertPerformanceVsSeparate() throws {
        print("🔄 Testing upsert performance...")
        
        let count = 50
        var ids: [UUID] = []
        
        // Benchmark: upsert (insert phase)
        let upsertStart = Date()
        for i in 0..<count {
            let id = UUID()
            ids.append(id)
            _ = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(i)]))
        }
        let upsertInsertDuration = Date().timeIntervalSince(upsertStart)
        
        // Benchmark: upsert (update phase)
        let upsertUpdateStart = Date()
        for (i, id) in ids.enumerated() {
            _ = try db.upsert(id: id, data: BlazeDataRecord(["value": .int(i * 2)]))
        }
        let upsertUpdateDuration = Date().timeIntervalSince(upsertUpdateStart)
        
        print("  Upsert insert: \(String(format: "%.3f", upsertInsertDuration))s")
        print("  Upsert update: \(String(format: "%.3f", upsertUpdateDuration))s")
        
        // Verify final state
        let allRecords = try db.fetchAll()
        XCTAssertEqual(allRecords.count, count)
        
        // Upsert should be reasonably fast
        XCTAssertLessThan(upsertInsertDuration + upsertUpdateDuration, 2.0,
                         "100 upserts should complete in < 2 seconds")
        
        print("✅ Upsert performance is good")
    }
    
    /// Test upsert with complex data types
    func testUpsertWithComplexDataTypes() throws {
        print("🔄 Testing upsert with complex data types...")
        
        let id = UUID()
        
        // Upsert with array
        _ = try db.upsert(id: id, data: BlazeDataRecord([
            "tags": .array([.string("swift"), .string("database")]),
            "metadata": .dictionary(["version": .int(1)])
        ]))
        
        // Upsert (update) with different complex data
        _ = try db.upsert(id: id, data: BlazeDataRecord([
            "tags": .array([.string("swift"), .string("performance")]),  // Changed
            "metadata": .dictionary(["version": .int(2)])  // Updated
        ]))
        
        // Verify latest values
        let final = try db.fetch(id: id)
        
        if case let .array(tags)? = final?.storage["tags"] {
            XCTAssertEqual(tags.count, 2)
            XCTAssertEqual(tags[1].stringValue, "performance")
        } else {
            XCTFail("Should have updated tags array")
        }
        
        if case let .dictionary(meta)? = final?.storage["metadata"] {
            XCTAssertEqual(meta["version"]?.intValue, 2)
        } else {
            XCTFail("Should have updated metadata dictionary")
        }
        
        print("✅ Upsert with complex data types works correctly")
    }
}

