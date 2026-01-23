//
//  ExtendedBatchOperationsTests.swift
//  BlazeDBTests
//
//  Tests for extended batch operations (upsertMany, fetchMany, existsMany, etc.)
//

import XCTest
@testable import BlazeDBCore

final class ExtendedBatchOperationsTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "BatchTest", fileURL: dbURL, password: "test-pass-123456")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - UpsertMany Tests
    
    func testUpsertMany_WithExplicitIDs() async throws {
        print("📦 Testing upsertMany() with explicit IDs")
        
        // Insert initial records
        let id1 = try await db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(1)]))
        let id2 = try await db.insert(BlazeDataRecord(["id": .uuid(UUID()), "value": .int(2)]))
        let id3 = UUID()  // New ID (doesn't exist yet)
        
        // Upsert: update id1 & id2, insert id3
        let records: [(UUID, BlazeDataRecord)] = [
            (id1, BlazeDataRecord(["value": .int(100)])),  // Update
            (id2, BlazeDataRecord(["value": .int(200)])),  // Update
            (id3, BlazeDataRecord(["value": .int(300)]))   // Insert
        ]
        
        let count = try await db.upsertMany(records)
        XCTAssertEqual(count, 3)
        
        // Verify updates
        let record1 = try await db.fetch(id: id1)
        XCTAssertEqual(record1?.storage["value"]?.intValue, 100, "id1 should be updated")
        
        let record2 = try await db.fetch(id: id2)
        XCTAssertEqual(record2?.storage["value"]?.intValue, 200, "id2 should be updated")
        
        // Verify insert
        let record3 = try await db.fetch(id: id3)
        XCTAssertNotNil(record3, "id3 should be inserted")
        XCTAssertEqual(record3?.storage["value"]?.intValue, 300)
        
        print("  ✅ Upserted 3 records (2 updates, 1 insert)")
    }
    
    func testUpsertMany_WithAutoID() async throws {
        print("📦 Testing upsertMany() with auto-ID generation")
        
        // Insert record with ID
        let existingID = UUID()
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(existingID), "value": .int(1)]))
        
        // Upsert mix
        let records = [
            BlazeDataRecord(["id": .uuid(existingID), "value": .int(100)]),  // Update existing
            BlazeDataRecord(["value": .int(2)]),                             // Insert new (auto-ID)
            BlazeDataRecord(["value": .int(3)])                              // Insert new (auto-ID)
        ]
        
        let results = try await db.upsertMany(records)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertFalse(results[0].wasInsert, "First should be update")
        XCTAssertTrue(results[1].wasInsert, "Second should be insert")
        XCTAssertTrue(results[2].wasInsert, "Third should be insert")
        
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 3, "Should have 3 total records")
        
        print("  ✅ Upserted 3 records (1 update, 2 inserts)")
    }
    
    // MARK: - FetchMany Tests
    
    func testFetchMany_ReturnsRequestedRecords() async throws {
        print("📦 Testing fetchMany()")
        
        // Insert 50 records
        let ids = try await db.insertMany((0..<50).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Fetch subset of 10
        let subset = Array(ids.prefix(10))
        let records = try await db.fetchMany(ids: subset)
        
        XCTAssertEqual(records.count, 10, "Should fetch all 10 requested records")
        
        for id in subset {
            XCTAssertNotNil(records[id], "Should fetch \(id)")
        }
        
        print("  ✅ Fetched 10/50 records efficiently")
    }
    
    func testFetchMany_HandlesNonExistentIDs() async throws {
        print("📦 Testing fetchMany() with non-existent IDs")
        
        // Insert 5 records
        let ids = try await db.insertMany((0..<5).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Mix existing and non-existing
        let nonExistent1 = UUID()
        let nonExistent2 = UUID()
        let toFetch = [ids[0], nonExistent1, ids[1], nonExistent2, ids[2]]
        
        let records = try await db.fetchMany(ids: toFetch)
        
        XCTAssertEqual(records.count, 3, "Should fetch only existing records")
        XCTAssertNotNil(records[ids[0]])
        XCTAssertNotNil(records[ids[1]])
        XCTAssertNotNil(records[ids[2]])
        XCTAssertNil(records[nonExistent1])
        XCTAssertNil(records[nonExistent2])
        
        print("  ✅ Fetched 3/5 existing records, ignored 2 non-existent")
    }
    
    func testFetchManyOrdered_PreservesOrder() async throws {
        print("📦 Testing fetchManyOrdered() preserves order")
        
        let ids = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Fetch in specific order
        let orderedIDs = [ids[5], ids[2], ids[8], ids[0]]
        let records = try await db.fetchManyOrdered(ids: orderedIDs)
        
        XCTAssertEqual(records.count, 4)
        
        // Verify order matches
        XCTAssertEqual(records[0]?.storage["value"]?.intValue, 5)
        XCTAssertEqual(records[1]?.storage["value"]?.intValue, 2)
        XCTAssertEqual(records[2]?.storage["value"]?.intValue, 8)
        XCTAssertEqual(records[3]?.storage["value"]?.intValue, 0)
        
        print("  ✅ Order preserved: [5,2,8,0]")
    }
    
    // MARK: - ExistsMany Tests
    
    func testExistsMany() async throws {
        print("📦 Testing existsMany()")
        
        // Insert 10 records
        let ids = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Check mix of existing and non-existing
        let nonExisting1 = UUID()
        let nonExisting2 = UUID()
        let toCheck = [ids[0], nonExisting1, ids[5], nonExisting2, ids[9]]
        
        let existence = try await db.existsMany(ids: toCheck)
        
        XCTAssertEqual(existence.count, 5)
        XCTAssertEqual(existence[ids[0]], true)
        XCTAssertEqual(existence[ids[5]], true)
        XCTAssertEqual(existence[ids[9]], true)
        XCTAssertEqual(existence[nonExisting1], false)
        XCTAssertEqual(existence[nonExisting2], false)
        
        print("  ✅ Checked 5 IDs: 3 exist, 2 don't")
    }
    
    func testExistsManyOrdered() async throws {
        print("📦 Testing existsManyOrdered()")
        
        let ids = try await db.insertMany((0..<5).map { i in BlazeDataRecord(["value": .int(i)]) })
        let nonExisting = UUID()
        
        let toCheck = [ids[0], nonExisting, ids[2]]
        let results = try await db.existsManyOrdered(ids: toCheck)
        
        XCTAssertEqual(results, [true, false, true])
        
        print("  ✅ Ordered existence: [true, false, true]")
    }
    
    // MARK: - DeleteMany by IDs Tests
    
    func testDeleteManyByIDs() async throws {
        print("📦 Testing deleteMany(ids:)")
        
        // Insert 20 records
        let ids = try await db.insertMany((0..<20).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Delete first 10 by ID
        let deleted = try await db.deleteMany(ids: Array(ids.prefix(10)))
        
        XCTAssertEqual(deleted, 10)
        
        // Verify
        let remaining = try await db.count()
        XCTAssertEqual(remaining, 10)
        
        print("  ✅ Deleted 10/20 records by ID")
    }
    
    func testDeleteManyByIDs_HandlesNonExistent() async throws {
        print("📦 Testing deleteMany(ids:) with non-existent IDs")
        
        let ids = try await db.insertMany((0..<5).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Try to delete existing + non-existing
        let nonExisting = UUID()
        let toDelete = [ids[0], nonExisting, ids[1]]
        
        let deleted = try await db.deleteMany(ids: toDelete)
        
        XCTAssertEqual(deleted, 2, "Should delete only existing records")
        
        let remaining = try await db.count()
        XCTAssertEqual(remaining, 3)
        
        print("  ✅ Deleted 2/3 existing, ignored non-existent")
    }
    
    // MARK: - UpdateMany by IDs Tests
    
    func testUpdateManyByIDs() async throws {
        print("📦 Testing updateMany(ids:set:)")
        
        // Insert records
        let ids = try await db.insertMany((0..<20).map { i in
            BlazeDataRecord(["value": .int(i), "status": .string("open")])
        })
        
        // Update first 10
        let updated = try await db.updateMany(
            ids: Array(ids.prefix(10)),
            set: ["status": .string("closed"), "closed_by": .string("test")]
        )
        
        XCTAssertEqual(updated, 10)
        
        // Verify
        let closed = try await db.query().where("status", equals: .string("closed")).execute()
        let closedRecords = try closed.records
        XCTAssertEqual(closedRecords.count, 10)
        
        for record in closedRecords {
            XCTAssertEqual(record.storage["closed_by"]?.stringValue, "test")
        }
        
        print("  ✅ Updated 10 records by ID")
    }
    
    // MARK: - Performance Tests
    
    // Performance tests can be added here as needed
}
