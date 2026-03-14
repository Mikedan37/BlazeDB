//
//  BTreeDebugTests.swift
//  BlazeDB
//
//  Debug tests for B-tree index operations
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BTreeDebugTests: XCTestCase {
    
    func testBTreeDirectOperations() throws {
        // Test B-tree directly without going through collection
        let btree = FieldBTreeIndex(name: "test")
        
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        
        // Insert with key 4
        btree.insert(key: ComparableField(.int(4)), value: id1)
        btree.insert(key: ComparableField(.int(4)), value: id2)
        btree.insert(key: ComparableField(.int(4)), value: id3)
        
        // Find key 4
        let found = btree.find(key: ComparableField(.int(4)))
        XCTAssertEqual(found.count, 3, "Should find 3 UUIDs for key 4")
        
        // Remove id1 from key 4
        btree.remove(key: ComparableField(.int(4)), value: id1)
        
        // Check count
        let afterRemove = btree.find(key: ComparableField(.int(4)))
        XCTAssertEqual(afterRemove.count, 2, "Should find 2 UUIDs after removing one")
        XCTAssertFalse(afterRemove.contains(id1), "id1 should be removed")
        XCTAssertTrue(afterRemove.contains(id2), "id2 should still exist")
        XCTAssertTrue(afterRemove.contains(id3), "id3 should still exist")
    }
    
    func testBTreeFindBetween() throws {
        let btree = FieldBTreeIndex(name: "test")
        
        // Insert records with various priorities
        var idsByPriority: [Int: [UUID]] = [:]
        for priority in 0..<5 {
            var ids: [UUID] = []
            for _ in 0..<10 {
                let id = UUID()
                ids.append(id)
                btree.insert(key: ComparableField(.int(priority)), value: id)
            }
            idsByPriority[priority] = ids
        }
        
        // Total should be 50
        XCTAssertEqual(btree.count, 50, "Should have 50 entries")
        
        // Find all with priority=4 using findBetween(4, 4)
        let found4 = btree.findBetween(min: ComparableField(.int(4)), max: ComparableField(.int(4)))
        XCTAssertEqual(found4.count, 10, "Should find 10 UUIDs with priority=4")
        
        // Find range 2-3
        let found2to3 = btree.findBetween(min: ComparableField(.int(2)), max: ComparableField(.int(3)))
        XCTAssertEqual(found2to3.count, 20, "Should find 20 UUIDs with priority 2-3")
        
        // Now remove all priority=4 entries
        for id in idsByPriority[4]! {
            btree.remove(key: ComparableField(.int(4)), value: id)
        }
        
        // Should find 0 now
        let found4After = btree.findBetween(min: ComparableField(.int(4)), max: ComparableField(.int(4)))
        XCTAssertEqual(found4After.count, 0, "Should find 0 UUIDs with priority=4 after removal")
    }
    
    func testBTreeManagerIndexAndDeindex() throws {
        let manager = BTreeIndexManager()
        
        // Create an index for "priority"
        _ = manager.getOrCreateIndex(for: "priority")
        
        let id1 = UUID()
        
        // Index a record
        manager.indexRecord(id: id1, fields: ["priority": .int(4), "name": .string("test")])
        
        // Find via the index
        if let index = manager.getIndex(for: "priority") {
            let found = index.find(key: ComparableField(.int(4)))
            XCTAssertEqual(found.count, 1, "Should find 1 record with priority=4")
            XCTAssertTrue(found.contains(id1), "Should contain id1")
        } else {
            XCTFail("Index should exist")
        }
        
        // Deindex the record
        manager.deindexRecord(id: id1, fields: ["priority": .int(4), "name": .string("test")])
        
        // Check it's gone
        if let index = manager.getIndex(for: "priority") {
            let found = index.find(key: ComparableField(.int(4)))
            XCTAssertEqual(found.count, 0, "Should find 0 records after deindex")
        }
    }
    
    func testCollectionUpdateUpdatesIndex() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("btree_debug_test_\(UUID().uuidString)")
        let dbPath = tempURL.appendingPathExtension("blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: dbPath)
            try? FileManager.default.removeItem(at: tempURL.appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: dbPath.appendingPathExtension("wal"))
        }
        
        let db = try BlazeDBClient(
            name: "btree_debug",
            fileURL: dbPath,
            password: "TestPassword-123!"
        )
        defer { try? db.close() }
        
        // Insert one record
        let recordId = try db.insert(BlazeDataRecord([
            "priority": .int(4),
            "name": .string("test")
        ]))
        
        // Create range index
        try db.collection.createRangeIndex(on: "priority")
        
        // Verify it's in the index
        if let index = db.collection.btreeIndexManager.getIndex(for: "priority") {
            let found4 = index.find(key: ComparableField(.int(4)))
            XCTAssertEqual(found4.count, 1, "Should find 1 record with priority=4")
            XCTAssertTrue(found4.contains(recordId), "Should contain our record")
        }
        
        // Update the record
        try db.update(id: recordId, with: BlazeDataRecord(["priority": .int(0)]))
        
        // Verify it's moved in the index
        if let index = db.collection.btreeIndexManager.getIndex(for: "priority") {
            let found4After = index.find(key: ComparableField(.int(4)))
            let found0After = index.find(key: ComparableField(.int(0)))
            
            XCTAssertEqual(found4After.count, 0, 
                "Should find 0 records with priority=4 after update (was \(found4After.count))")
            XCTAssertEqual(found0After.count, 1,
                "Should find 1 record with priority=0 after update (was \(found0After.count))")
        }
        
        // Verify data is correct
        let fetched = try db.fetch(id: recordId)
        XCTAssertEqual(fetched?.storage["priority"]?.intValue, 0, "Record should have priority=0")
    }
}
