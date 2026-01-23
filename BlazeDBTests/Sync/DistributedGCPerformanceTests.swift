//
//  DistributedGCPerformanceTests.swift
//  BlazeDBTests
//
//  Performance tests for all distributed GC features with Xcode metrics
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDBCore

final class DistributedGCPerformanceTests: XCTestCase {
    
    var tempDir: URL!
    var db1: BlazeDBClient!
    var db2: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let url1 = tempDir.appendingPathComponent("db1.blazedb")
        let url2 = tempDir.appendingPathComponent("db2.blazedb")
        
        db1 = try! BlazeDBClient(name: "DB1", fileURL: url1, password: "test1234")
        db2 = try! BlazeDBClient(name: "DB2", fileURL: url2, password: "test1234")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Operation Log GC Performance
    
    func testPerformance_OperationLogGC_KeepLastOperations() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create large operation log
        let recordId = UUID()
        for i in 0..<10000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Measure GC performance
        measure {
            do {
                try await opLog.cleanupOldOperations(keepLast: 1000)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    func testPerformance_OperationLogGC_CleanupOrphaned() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operations for many records
        var recordIds: [UUID] = []
        for i in 0..<5000 {
            let recordId = UUID()
            recordIds.append(recordId)
            _ = await opLog.recordOperation(
                type: .insert,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Only keep half
        let existingIDs = Set(recordIds.prefix(2500))
        
        // Measure GC performance
        measure {
            do {
                try await opLog.cleanupOrphanedOperations(existingRecordIDs: existingIDs)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    func testPerformance_OperationLogGC_Compact() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create many operations with duplicates
        let recordId = UUID()
        for i in 0..<5000 {
            let op = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            // Add duplicate
            await opLog.applyRemoteOperation(op)
        }
        
        // Measure compaction performance
        measure {
            do {
                try await opLog.compactOperationLog()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    func testPerformance_OperationLogGC_FullCleanup() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create large operation log
        var recordIds: [UUID] = []
        for i in 0..<10000 {
            let recordId = UUID()
            recordIds.append(recordId)
            for j in 0..<10 {
                _ = await opLog.recordOperation(
                    type: .update,
                    collectionName: "test",
                    recordId: recordId,
                    changes: ["value": .int(i * 10 + j)]
                )
            }
        }
        
        let config = OperationLogGCConfig(
            keepLastOperationsPerRecord: 5,
            retentionDays: 7,
            cleanupOrphaned: true,
            compactEnabled: true
        )
        
        let existingIDs = Set(recordIds.prefix(5000))
        
        // Measure full cleanup performance
        measure {
            do {
                try await opLog.runFullCleanup(config: config, existingRecordIDs: existingIDs)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    // MARK: - Sync State GC Performance
    
    func testPerformance_SyncStateGC_CleanupDeletedRecords() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        let engine = BlazeSyncEngine(localDB: db1, relay: relay)
        
        // Create many records
        var ids: [UUID] = []
        for i in 0..<10000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Delete half
        for i in 0..<5000 {
            try db1.delete(id: ids[i])
        }
        
        // Measure GC performance
        measure {
            do {
                try await engine.cleanupSyncStateForDeletedRecords()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    func testPerformance_SyncStateGC_Compact() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        let engine = BlazeSyncEngine(localDB: db1, relay: relay)
        
        // Create many records to populate sync state
        for i in 0..<10000 {
            _ = try db1.insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        // Measure compaction performance
        measure {
            do {
                try await engine.compactSyncState()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    // MARK: - Relay Memory GC Performance
    
    func testPerformance_RelayMemoryGC_LimitQueueSize() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // Fill queue
        let recordId = UUID()
        for i in 0..<50000 {
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
        
        // Measure GC performance
        measure {
            do {
                try await relay.limitQueueSize(maxSize: 1000)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
        
        await relay.disconnect()
    }
    
    func testPerformance_RelayMemoryGC_Compact() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // Create many operations with duplicates
        let recordId = UUID()
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: 1, nodeId: UUID()),
            nodeId: UUID(),
            type: .update,
            collectionName: "test",
            recordId: recordId,
            changes: ["value": .int(1)]
        )
        
        // Add duplicates
        for _ in 0..<10000 {
            try await relay.pushOperations([op])
        }
        
        // Measure compaction performance
        measure {
            do {
                try await relay.compactQueue()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
        
        await relay.disconnect()
    }
    
    // MARK: - Multi-Database GC Performance
    
    func testPerformance_MultiDatabaseGC_Coordinate() async throws {
        let coordinator = MultiDatabaseGCCoordinator.shared
        
        // Register many databases
        var databases: [BlazeDBClient] = []
        for i in 0..<10 {
            let url = tempDir.appendingPathComponent("db\(i).blazedb")
            let db = try BlazeDBClient(name: "DB\(i)", fileURL: url, password: "test1234")
            databases.append(db)
            try await coordinator.registerDatabase(db, name: "DB\(i)")
        }
        
        // Insert records in each
        for db in databases {
            for i in 0..<1000 {
                _ = try db.insert(BlazeDataRecord(["value": .int(i)]))
            }
        }
        
        // Measure coordination performance
        measure {
            do {
                try await coordinator.coordinateGC()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
        
        // Cleanup
        for i in 0..<10 {
            try await coordinator.unregisterDatabase(name: "DB\(i)")
        }
    }
    
    // MARK: - Memory Usage Tests
    
    func testMemory_OperationLogGC_MemoryReduction() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create large operation log
        let recordId = UUID()
        for i in 0..<50000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Get memory before GC
        let statsBefore = await opLog.getStats()
        let operationsBefore = statsBefore.totalOperations
        
        // Run GC
        try await opLog.cleanupOldOperations(keepLast: 1000)
        
        // Get memory after GC
        let statsAfter = await opLog.getStats()
        let operationsAfter = statsAfter.totalOperations
        
        // Verify reduction
        XCTAssertLessThan(operationsAfter, operationsBefore, "Operations should be reduced")
        let reduction = Double(operationsBefore - operationsAfter) / Double(operationsBefore) * 100
        print("Memory reduction: \(String(format: "%.1f", reduction))%")
        
        // Measure memory usage
        measure(metrics: [XCTMemoryMetric()]) {
            // GC operation
            do {
                try await opLog.cleanupOldOperations(keepLast: 1000)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    func testMemory_SyncStateGC_MemoryReduction() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        let engine = BlazeSyncEngine(localDB: db1, relay: relay)
        
        // Create many records
        var ids: [UUID] = []
        for i in 0..<20000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Delete half
        for i in 0..<10000 {
            try db1.delete(id: ids[i])
        }
        
        // Measure memory usage during GC
        measure(metrics: [XCTMemoryMetric()]) {
            do {
                try await engine.cleanupSyncStateForDeletedRecords()
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
    }
    
    // MARK: - Throughput Tests
    
    func testThroughput_OperationLogGC_OperationsPerSecond() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operation log
        let recordId = UUID()
        for i in 0..<100000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Measure throughput
        let startTime = Date()
        try await opLog.cleanupOldOperations(keepLast: 1000)
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        let throughput = Double(100000) / duration
        
        print("Operation Log GC Throughput: \(String(format: "%.0f", throughput)) operations/second")
        
        XCTAssertGreaterThan(throughput, 1000, "Should process at least 1000 ops/sec")
    }
    
    func testThroughput_SyncStateGC_RecordsPerSecond() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        let engine = BlazeSyncEngine(localDB: db1, relay: relay)
        
        // Create many records
        var ids: [UUID] = []
        for i in 0..<50000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        // Delete half
        for i in 0..<25000 {
            try db1.delete(id: ids[i])
        }
        
        // Measure throughput
        let startTime = Date()
        try await engine.cleanupSyncStateForDeletedRecords()
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        let throughput = Double(50000) / duration
        
        print("Sync State GC Throughput: \(String(format: "%.0f", throughput)) records/second")
        
        XCTAssertGreaterThan(throughput, 100, "Should process at least 100 records/sec")
    }
}

