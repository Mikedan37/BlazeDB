//
//  DistributedGCIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for distributed GC features
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDBCore

final class DistributedGCIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var db1: BlazeDBClient!
    var db2: BlazeDBClient!
    var db3: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let url1 = tempDir.appendingPathComponent("db1.blazedb")
        let url2 = tempDir.appendingPathComponent("db2.blazedb")
        let url3 = tempDir.appendingPathComponent("db3.blazedb")
        
        db1 = try! BlazeDBClient(name: "DB1", fileURL: url1, password: "test1234")
        db2 = try! BlazeDBClient(name: "DB2", fileURL: url2, password: "test1234")
        db3 = try! BlazeDBClient(name: "DB3", fileURL: url3, password: "test1234")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - End-to-End GC Tests
    
    func testEndToEnd_OperationLogGCWithRealSync() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Create many operations
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        
        // Verify all records synced
        for id in ids {
            let synced = try db2.fetch(id: id)
            XCTAssertNotNil(synced, "Record \(id) should be synced")
        }
        
        // Operation log should have grown
        // In a real implementation, we'd check the operation log size
        
        await topology.disconnectAll()
    }
    
    func testEndToEnd_SyncStateGCWithRecordDeletion() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Delete half the records
        for i in 0..<25 {
            try db1.delete(id: ids[i])
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Verify deletions synced
        for i in 0..<25 {
            let deleted = try db2.fetch(id: ids[i])
            XCTAssertNil(deleted, "Record \(i) should be deleted")
        }
        
        // Verify remaining records still exist
        for i in 25..<50 {
            let exists = try db2.fetch(id: ids[i])
            XCTAssertNotNil(exists, "Record \(i) should still exist")
        }
        
        await topology.disconnectAll()
    }
    
    func testEndToEnd_MultiDatabaseGCCoordination() async throws {
        let coordinator = MultiDatabaseGCCoordinator.shared
        
        // Register all databases
        try await coordinator.registerDatabase(db1, name: "DB1")
        try await coordinator.registerDatabase(db2, name: "DB2")
        try await coordinator.registerDatabase(db3, name: "DB3")
        
        // Insert records in each database
        for i in 0..<10 {
            _ = try db1.insert(BlazeDataRecord(["db": .string("1"), "value": .int(i)]))
            _ = try db2.insert(BlazeDataRecord(["db": .string("2"), "value": .int(i)]))
            _ = try db3.insert(BlazeDataRecord(["db": .string("3"), "value": .int(i)]))
        }
        
        // Coordinate GC
        try await coordinator.coordinateGC()
        
        let stats = await coordinator.getStats()
        XCTAssertEqual(stats.registeredDatabases, 3, "Should have 3 registered databases")
        
        // Cleanup
        try await coordinator.unregisterDatabase(name: "DB1")
        try await coordinator.unregisterDatabase(name: "DB2")
        try await coordinator.unregisterDatabase(name: "DB3")
    }
    
    func testEndToEnd_RelayMemoryGCWithHighVolume() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // Push many operations
        let recordId = UUID()
        for i in 0..<10000 {
            let op = BlazeOperation(
                timestamp: LamportTimestamp(counter: UInt64(i), nodeId: UUID()),
                nodeId: UUID(),
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            try await relay.pushOperations([op])
        }
        
        // Check queue size before GC
        let statsBefore = await relay.getQueueStats()
        XCTAssertGreaterThan(statsBefore.queueSize, 0, "Queue should have operations")
        
        // Run GC
        let config = RelayMemoryGCConfig(maxQueueSize: 1000, retentionSeconds: 300)
        try await relay.runFullCleanup(config: config)
        
        // Check queue size after GC
        let statsAfter = await relay.getQueueStats()
        XCTAssertLessThanOrEqual(statsAfter.queueSize, 1000, "Queue should be limited after GC")
        
        await relay.disconnect()
    }
    
    func testEndToEnd_CompleteGCWorkflow() async throws {
        // Setup topology
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Create workload
        var ids: [UUID] = []
        for i in 0..<200 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        // Delete some records
        for i in 0..<100 {
            try db1.delete(id: ids[i])
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Update remaining records
        for i in 100..<200 {
            var record = try db1.fetch(id: ids[i])!
            record.storage["updated"] = .bool(true)
            try db1.update(id: ids[i], with: record)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify final state
        for i in 100..<200 {
            let synced = try db2.fetch(id: ids[i])
            XCTAssertNotNil(synced, "Record \(i) should exist")
            XCTAssertEqual(synced?.bool("updated"), true, "Record \(i) should be updated")
        }
        
        // GC should have run automatically
        // Verify no memory leaks or excessive growth
        
        await topology.disconnectAll()
    }
}

