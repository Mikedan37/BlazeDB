//
//  SyncIntegrationTests.swift
//  BlazeDBTests
//
//  Comprehensive integration tests for distributed sync system
//  Tests memory safety, performance, and edge cases
//

import XCTest
@testable import BlazeDB

final class SyncIntegrationTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_sync_integration_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Enable debug logging for tests
        BlazeLogger.level = .debug
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        BlazeLogger.reset()
        super.tearDown()
    }
    
    // MARK: - Memory Safety Tests
    
    /// Test that sync doesn't leak memory with rapid operations
    func testMemorySafety_RapidOperations() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_mem.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_mem.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Insert 1000 records rapidly
        var recordIds: [UUID] = []
        for i in 0..<1000 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ])
            let id = try await db1.insert(record)
            recordIds.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Verify all records synced
        for id in recordIds {
            let synced = try await db2.fetch(id: id)
            XCTAssertNotNil(synced, "Record \(id) should be synced")
        }
        
        // Memory should be stable (no leaks)
        // Note: In a real test, you'd use Instruments to verify
    }
    
    /// Test that sync handles concurrent operations safely
    func testMemorySafety_ConcurrentOperations() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_concurrent.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_concurrent.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Concurrent inserts from both databases
        await withTaskGroup(of: Void.self) { group in
            // DB1 inserts
            for i in 0..<100 {
                group.addTask {
                    let record = BlazeDataRecord(["source": .string("db1"), "index": .int(i)])
                    _ = try? await db1.insert(record)
                }
            }
            
            // DB2 inserts
            for i in 0..<100 {
                group.addTask {
                    let record = BlazeDataRecord(["source": .string("db2"), "index": .int(i)])
                    _ = try? await db2.insert(record)
                }
            }
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Verify no crashes (memory safety)
        let db1Count = try await db1.query().all().count
        let db2Count = try await db2.query().all().count
        
        XCTAssertGreaterThan(db1Count, 0, "DB1 should have records")
        XCTAssertGreaterThan(db2Count, 0, "DB2 should have records")
    }
    
    // MARK: - Performance Tests
    
    /// Test sync performance with large batches
    func testPerformance_LargeBatchSync() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_perf.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_perf.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Insert 5000 records
        let startTime = Date()
        var records: [BlazeDataRecord] = []
        for i in 0..<5000 {
            records.append(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
        }
        let insertIds = try await db1.insertMany(records)
        let insertTime = Date().timeIntervalSince(startTime)
        
        // Wait for sync
        let syncStartTime = Date()
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify all synced
        var syncedCount = 0
        for id in insertIds {
            if try await db2.fetch(id: id) != nil {
                syncedCount += 1
            }
        }
        let syncTime = Date().timeIntervalSince(syncStartTime)
        
        XCTAssertEqual(syncedCount, 5000, "All records should sync")
        
        // Performance assertions
        XCTAssertLessThan(insertTime, 5.0, "Insert should be fast (<5s)")
        XCTAssertLessThan(syncTime, 3.0, "Sync should be fast (<3s)")
        
        print("✅ Performance: Insert \(insertTime)s, Sync \(syncTime)s")
    }
    
    // MARK: - Edge Case Tests
    
    /// Test sync with rapid connect/disconnect cycles
    func testEdgeCase_RapidConnectDisconnect() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_edge.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_edge.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        // Connect/disconnect 10 times rapidly
        for i in 0..<10 {
            try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            // Note: Disconnect not implemented yet, but test should not crash
        }
        
        // Insert a record
        let recordId = try await db1.insert(BlazeDataRecord(["test": .string("value")]))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Should still sync
        let synced = try await db2.fetch(id: recordId)
        XCTAssertNotNil(synced, "Record should sync even after rapid connect/disconnect")
    }
    
    /// Test sync with empty operations
    func testEdgeCase_EmptyOperations() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_empty.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_empty.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // No operations - should not crash
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Should still be connected
        let db1Count = try await db1.query().all().count
        let db2Count = try await db2.query().all().count
        
        XCTAssertEqual(db1Count, 0, "DB1 should be empty")
        XCTAssertEqual(db2Count, 0, "DB2 should be empty")
    }
    
    /// Test sync with very large records
    func testEdgeCase_LargeRecords() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_large.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_large.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create large record (100KB string)
        let largeString = String(repeating: "A", count: 100_000)
        let recordId = try await db1.insert(BlazeDataRecord([
            "largeData": .string(largeString)
        ]))
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Verify synced
        let synced = try await db2.fetch(id: recordId)
        XCTAssertNotNil(synced, "Large record should sync")
        XCTAssertEqual(try synced?.string("largeData"), largeString, "Large data should match")
    }
    
    // MARK: - Actor Safety Tests
    
    /// Test that actors prevent data races
    func testActorSafety_NoDataRaces() async throws {
        let db1URL = tempDir.appendingPathComponent("db1_actor.blazedb")
        let db2URL = tempDir.appendingPathComponent("db2_actor.blazedb")
        
        let db1 = try BlazeDBClient(name: "DB1", fileURL: db1URL, password: "SyncIntegrationTest123!")
        let db2 = try BlazeDBClient(name: "DB2", fileURL: db2URL, password: "SyncIntegrationTest123!")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Concurrent access to topology (should be safe due to actor)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    // Access topology concurrently (actor protects)
                    _ = await topology.getNode(id: id1)
                    _ = await topology.getNode(id: id2)
                }
            }
        }
        
        // Should not crash (actor prevents data races)
        let node1 = await topology.getNode(id: id1)
        let node2 = await topology.getNode(id: id2)
        
        XCTAssertNotNil(node1, "Node1 should exist")
        XCTAssertNotNil(node2, "Node2 should exist")
    }
}

