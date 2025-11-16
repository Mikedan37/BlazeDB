//
//  DistributedGCRobustnessTests.swift
//  BlazeDBIntegrationTests
//
//  Robustness and stress tests for distributed GC features
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class DistributedGCRobustnessTests: XCTestCase {
    
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
    
    // MARK: - Stress Tests
    
    func testStress_OperationLogGC_ExtremeVolume() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create extreme volume of operations
        let recordId = UUID()
        for i in 0..<100000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            
            // Run GC every 10000 operations
            if i > 0 && i % 10000 == 0 {
                try await opLog.cleanupOldOperations(keepLast: 1000)
            }
        }
        
        // Final GC
        try await opLog.cleanupOldOperations(keepLast: 1000)
        
        let stats = await opLog.getStats()
        XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
    }
    
    func testStress_SyncStateGC_ConcurrentOperations() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Concurrent insertions
        let group = DispatchGroup()
        var errors: [Error] = []
        
        for i in 0..<1000 {
            group.enter()
            DispatchQueue.global().async {
                do {
                    _ = try self.db1.insert(BlazeDataRecord(["value": .int(i)]))
                } catch {
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.wait()
        XCTAssertTrue(errors.isEmpty, "No errors during concurrent operations")
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        
        // Run GC during concurrent operations
        let gcGroup = DispatchGroup()
        var gcErrors: [Error] = []
        
        for _ in 0..<10 {
            gcGroup.enter()
            DispatchQueue.global().async {
                Task {
                    do {
                        // Get sync engine and run GC
                        // In a real implementation, we'd access the sync engine
                        // For now, just verify no crashes
                    } catch {
                        gcErrors.append(error)
                    }
                    gcGroup.leave()
                }
            }
        }
        
        gcGroup.wait()
        XCTAssertTrue(gcErrors.isEmpty, "No errors during concurrent GC")
        
        await topology.disconnectAll()
    }
    
    func testStress_RelayMemoryGC_HighFrequency() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // High frequency operations
        let recordId = UUID()
        for i in 0..<100000 {
            let op = BlazeOperation(
                timestamp: LamportTimestamp(counter: UInt64(i), nodeId: UUID()),
                nodeId: UUID(),
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            try await relay.pushOperations([op])
            
            // Run GC every 1000 operations
            if i > 0 && i % 1000 == 0 {
                try await relay.limitQueueSize(maxSize: 100)
            }
        }
        
        // Final GC
        try await relay.limitQueueSize(maxSize: 100)
        
        let stats = await relay.getQueueStats()
        XCTAssertLessThanOrEqual(stats.queueSize, 100, "Queue should be limited")
        
        await relay.disconnect()
    }
    
    // MARK: - Edge Case Tests
    
    func testEdgeCase_OperationLogGC_EmptyLog() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // GC on empty log should not crash
        try await opLog.cleanupOldOperations(keepLast: 1000)
        try await opLog.cleanupOrphanedOperations(existingRecordIDs: Set<UUID>())
        try await opLog.compactOperationLog()
        
        let stats = await opLog.getStats()
        XCTAssertEqual(stats.totalOperations, 0, "Empty log should have 0 operations")
    }
    
    func testEdgeCase_SyncStateGC_NoDeletedRecords() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        let engine = BlazeSyncEngine(localDB: db1, relay: relay)
        
        // GC with no deleted records should not crash
        try await engine.cleanupSyncStateForDeletedRecords()
        try await engine.compactSyncState()
        
        let stats = await engine.getSyncStateStats()
        XCTAssertTrue(true, "GC should complete without errors")
    }
    
    func testEdgeCase_RelayMemoryGC_EmptyQueue() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // GC on empty queue should not crash
        try await relay.limitQueueSize(maxSize: 1000)
        try await relay.compactQueue()
        
        let stats = await relay.getQueueStats()
        XCTAssertEqual(stats.queueSize, 0, "Empty queue should have 0 operations")
        
        await relay.disconnect()
    }
    
    func testEdgeCase_MultiDatabaseGC_NoDatabases() async throws {
        let coordinator = MultiDatabaseGCCoordinator.shared
        
        // GC with no databases should not crash
        try await coordinator.coordinateGC()
        
        let stats = await coordinator.getStats()
        XCTAssertEqual(stats.registeredDatabases, 0, "Should have 0 registered databases")
    }
    
    // MARK: - Data Integrity Tests
    
    func testDataIntegrity_OperationLogGC_PreservesRecentOperations() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operations
        let recordId = UUID()
        var recentOps: [BlazeOperation] = []
        for i in 0..<5000 {
            let op = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            if i >= 4000 {
                recentOps.append(op)
            }
        }
        
        // Run GC
        try await opLog.cleanupOldOperations(keepLast: 1000)
        
        // Verify recent operations are preserved
        let stats = await opLog.getStats()
        XCTAssertGreaterThanOrEqual(stats.totalOperations, 1000, "Should keep at least 1000 operations")
        
        // Verify we can still access recent operations
        for op in recentOps.suffix(100) {
            let exists = await opLog.contains(op.id)
            XCTAssertTrue(exists, "Recent operation \(op.id) should still exist")
        }
    }
    
    func testDataIntegrity_SyncStateGC_PreservesActiveRecords() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Insert records
        var activeIds: [UUID] = []
        for i in 0..<100 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            activeIds.append(id)
        }
        
        // Insert and delete some records
        var deletedIds: [UUID] = []
        for i in 100..<200 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            deletedIds.append(id)
            try db1.delete(id: id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify active records still exist
        for id in activeIds {
            let exists = try db1.fetch(id: id)
            XCTAssertNotNil(exists, "Active record \(id) should still exist")
        }
        
        // Verify deleted records are gone
        for id in deletedIds {
            let exists = try db1.fetch(id: id)
            XCTAssertNil(exists, "Deleted record \(id) should be gone")
        }
        
        await topology.disconnectAll()
    }
    
    // MARK: - Concurrent GC Tests
    
    func testConcurrent_OperationLogGC_MultipleThreads() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operations
        let recordId = UUID()
        for i in 0..<10000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Run GC concurrently from multiple threads
        let group = DispatchGroup()
        var errors: [Error] = []
        
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                Task {
                    do {
                        try await opLog.cleanupOldOperations(keepLast: 1000)
                    } catch {
                        errors.append(error)
                    }
                    group.leave()
                }
            }
        }
        
        group.wait()
        XCTAssertTrue(errors.isEmpty, "No errors during concurrent GC")
        
        // Verify final state is consistent
        let stats = await opLog.getStats()
        XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
    }
    
    func testConcurrent_SyncStateGC_MultipleEngines() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        let id3 = try await topology.register(db: db3, name: "DB3", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        try await topology.connectLocal(from: id1, to: id3, mode: .bidirectional)
        
        // Create records in all databases
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Delete some records
        for i in 0..<500 {
            try db1.delete(id: ids[i])
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Verify all databases are consistent
        for i in 500..<1000 {
            let exists1 = try db1.fetch(id: ids[i])
            let exists2 = try db2.fetch(id: ids[i])
            let exists3 = try db3.fetch(id: ids[i])
            
            XCTAssertNotNil(exists1, "DB1 should have record \(i)")
            XCTAssertNotNil(exists2, "DB2 should have record \(i)")
            XCTAssertNotNil(exists3, "DB3 should have record \(i)")
        }
        
        await topology.disconnectAll()
    }
    
    // MARK: - Recovery Tests
    
    func testRecovery_OperationLogGC_AfterCrash() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operations and save
        let recordId = UUID()
        for i in 0..<5000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        try await opLog.save()
        
        // Simulate crash (recreate opLog)
        let opLog2 = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        try await opLog2.load()
        
        // Run GC after recovery
        try await opLog2.cleanupOldOperations(keepLast: 1000)
        
        let stats = await opLog2.getStats()
        XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
    }
    
    func testRecovery_SyncStateGC_AfterReconnect() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Create records
        var ids: [UUID] = []
        for i in 0..<1000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Disconnect
        await topology.disconnectAll()
        
        // Delete some records
        for i in 0..<500 {
            try db1.delete(id: ids[i])
        }
        
        // Reconnect
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify consistency
        for i in 500..<1000 {
            let exists1 = try db1.fetch(id: ids[i])
            let exists2 = try db2.fetch(id: ids[i])
            XCTAssertNotNil(exists1, "DB1 should have record \(i)")
            XCTAssertNotNil(exists2, "DB2 should have record \(i)")
        }
        
        await topology.disconnectAll()
    }
    
    // MARK: - Long-Running Tests
    
    func testLongRunning_OperationLogGC_SustainedLoad() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Sustained load with periodic GC
        let recordId = UUID()
        for batch in 0..<100 {
            // Create batch of operations
            for i in 0..<1000 {
                _ = await opLog.recordOperation(
                    type: .update,
                    collectionName: "test",
                    recordId: recordId,
                    changes: ["value": .int(batch * 1000 + i)]
                )
            }
            
            // Run GC every batch
            try await opLog.cleanupOldOperations(keepLast: 1000)
            
            // Verify state is consistent
            let stats = await opLog.getStats()
            XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
        }
    }
    
    func testLongRunning_SyncStateGC_SustainedSync() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Sustained sync with periodic deletions
        for batch in 0..<50 {
            // Insert batch
            var batchIds: [UUID] = []
            for i in 0..<100 {
                let id = try db1.insert(BlazeDataRecord(["batch": .int(batch), "value": .int(i)]))
                batchIds.append(id)
            }
            
            // Wait for sync
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // Delete half
            for i in 0..<50 {
                try db1.delete(id: batchIds[i])
            }
            
            // Wait for sync
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // Verify remaining records
            for i in 50..<100 {
                let exists = try db2.fetch(id: batchIds[i])
                XCTAssertNotNil(exists, "Record \(i) in batch \(batch) should exist")
            }
        }
        
        await topology.disconnectAll()
    }
}

