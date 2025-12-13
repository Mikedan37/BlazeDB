//
//  SyncEndToEndTests.swift
//  BlazeDBTests
//
//  End-to-end integration tests for database synchronization
//

import XCTest
@testable import BlazeDB

final class SyncEndToEndTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_sync_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    /// Test that data inserted in one database appears in another (local sync)
    func testLocalSyncEndToEnd() async throws {
        // Create two databases
        let db1URL = tempDir.appendingPathComponent("db1.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncEndToEndTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncEndToEndTest123!")
        
        // Create topology
        let topology = BlazeTopology()
        
        // Register databases
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        // Connect them
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert data into db1
        let record = BlazeDataRecord([
            "title": .string("Test Record"),
            "value": .int(42)
        ])
        let recordId = try await db1.insert(record)
        
        // Wait for sync (give it time to process)
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        
        // Verify data appears in db2
        let synced = try await db2.fetch(id: recordId)
        XCTAssertNotNil(synced, "Record should be synced to db2")
        XCTAssertEqual(try synced?.string("title"), "Test Record")
        XCTAssertEqual(try synced?.int("value"), 42)
    }
    
    /// Test that updates sync correctly
    func testUpdateSyncEndToEnd() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_update.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_update.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncEndToEndTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncEndToEndTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert initial record
        let recordId = try await db1.insert(BlazeDataRecord([
            "title": .string("Original"),
            "value": .int(1)
        ]))
        
        // Wait for initial sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Update in db1
        var updated = try await db1.fetch(id: recordId)!
        updated.storage["title"] = .string("Updated")
        updated.storage["value"] = .int(2)
        try await db1.update(id: recordId, with: updated)
        
        // Wait for update sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify update in db2
        let synced = try await db2.fetch(id: recordId)
        XCTAssertEqual(try synced?.string("title"), "Updated")
        XCTAssertEqual(try synced?.int("value"), 2)
    }
    
    /// Test that deletes sync correctly
    func testDeleteSyncEndToEnd() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_delete.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_delete.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncEndToEndTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncEndToEndTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert record
        let recordId = try await db1.insert(BlazeDataRecord([
            "title": .string("To Delete")
        ]))
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify it exists in db2
        let fetchedBefore = try await db2.fetch(id: recordId)
        XCTAssertNotNil(fetchedBefore)
        
        // Delete in db1
        try await db1.delete(id: recordId)
        
        // Wait for delete sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify deleted in db2
        let fetchedAfter = try await db2.fetch(id: recordId)
        XCTAssertNil(fetchedAfter)
    }
    
    /// Test bidirectional sync (both databases can write)
    func testBidirectionalSyncEndToEnd() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_bidi.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_bidi.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncEndToEndTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncEndToEndTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert in db1
        let id1_record = try await db1.insert(BlazeDataRecord([
            "source": .string("db1"),
            "value": .int(1)
        ]))
        
        // Insert in db2
        let id2_record = try await db2.insert(BlazeDataRecord([
            "source": .string("db2"),
            "value": .int(2)
        ]))
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        // Verify both records in both databases
        let fetched1 = try await db2.fetch(id: id1_record)
        XCTAssertNotNil(fetched1, "db1's record should be in db2")
        let fetched2 = try await db1.fetch(id: id2_record)
        XCTAssertNotNil(fetched2, "db2's record should be in db1")
    }
}

