//
//  AsyncAwaitEdgeCaseTests.swift
//  BlazeDBTests
//
//  Additional async/await edge case tests for 100% coverage.
//  Tests async error paths, concurrent async operations, and async edge cases.
//
//  Created: Final 1% Coverage Push
//

import XCTest
@testable import BlazeDBCore

final class AsyncAwaitEdgeCaseTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsyncEdge-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "AsyncEdgeTest", fileURL: tempURL, password: "test-password-123")
        
        // IMPORTANT: Disable MVCC until version persistence is implemented
        db.collection.mvccEnabled = false
    }
    
    override func tearDown() async throws {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
    }
    
    // MARK: - Async Error Path Tests
    
    /// Test async update on non-existent record
    func testAsyncUpdateNonExistentThrows() async throws {
        print("⚡ Testing async update on non-existent record...")
        
        let randomID = UUID()
        
        do {
            try await db.update(id: randomID, data: BlazeDataRecord(["value": .int(1)]))
            XCTFail("Should throw error for non-existent record")
        } catch {
            // Expected error
            print("  Expected error: \(error)")
        }
        
        print("✅ Async update non-existent throws correctly")
    }
    
    /// Test async delete on non-existent record (should not throw)
    func testAsyncDeleteNonExistent() async throws {
        print("⚡ Testing async delete on non-existent record...")
        
        let randomID = UUID()
        
        // Should not throw (delete is idempotent)
        try await db.delete(id: randomID)
        
        print("✅ Async delete non-existent handled gracefully")
    }
    
    /// Test async insertMany with empty array
    func testAsyncInsertManyEmpty() async throws {
        print("⚡ Testing async insertMany with empty array...")
        
        let ids = try await db.insertMany([])
        
        XCTAssertEqual(ids.count, 0, "Empty batch should return empty IDs")
        
        print("✅ Async insertMany empty works")
    }
    
    /// Test async query with no results
    func testAsyncQueryNoResults() async throws {
        print("⚡ Testing async query with no results...")
        
        let results = try await db.query()
            .where("field", equals: .string("nonexistent"))
            .execute()
            .records
        
        XCTAssertEqual(results.count, 0, "Query with no matches should return empty")
        
        print("✅ Async query with no results works")
    }
    
    /// Test async fetch on empty database
    func testAsyncFetchAllEmpty() async throws {
        print("⚡ Testing async fetchAll on empty database...")
        
        let records = try await db.fetchAll()
        
        XCTAssertEqual(records.count, 0, "Empty database should return empty array")
        
        print("✅ Async fetchAll empty works")
    }
    
    /// Test concurrent async operations
    func testConcurrentAsyncOperations() async throws {
        print("⚡ Testing concurrent async operations...")
        
        // Insert base records
        for i in 0..<10 {
            _ = try await db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        // Concurrent async operations
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Concurrent reads
            for _ in 0..<5 {
                group.addTask {
                    let _ = try await self.db.fetchAll()
                }
            }
            
            // Concurrent writes
            for i in 10..<15 {
                group.addTask {
                    _ = try await self.db.insert(BlazeDataRecord(["index": .int(i)]))
                }
            }
            
            // Wait for all
            try await group.waitForAll()
        }
        
        let final = try await db.fetchAll()
        XCTAssertEqual(final.count, 15, "Should have 15 records after concurrent ops")
        
        print("✅ Concurrent async operations work correctly")
    }
}

