//
//  DistributedGCStressTests.swift
//  BlazeDBIntegrationTests
//
//  Extreme stress tests for distributed GC features
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class DistributedGCStressTests: XCTestCase {
    
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
    
    // MARK: - Extreme Volume Tests
    
    func testExtreme_OperationLogGC_OneMillionOperations() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create 1 million operations
        let recordId = UUID()
        print("Creating 1 million operations...")
        
        for i in 0..<1_000_000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            
            // Progress indicator
            if i > 0 && i % 100_000 == 0 {
                print("Created \(i) operations...")
            }
        }
        
        print("Running GC on 1 million operations...")
        let startTime = Date()
        
        try await opLog.cleanupOldOperations(keepLast: 1000)
        
        let duration = Date().timeIntervalSince(startTime)
        let stats = await opLog.getStats()
        
        print("GC completed in \(String(format: "%.2f", duration))s")
        print("Final operations: \(stats.totalOperations)")
        
        XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
        XCTAssertLessThan(duration, 60.0, "GC should complete in under 60 seconds")
    }
    
    func testExtreme_SyncStateGC_OneHundredThousandRecords() async throws {
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "DB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "DB2", role: .client)
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Create 100,000 records
        print("Creating 100,000 records...")
        var ids: [UUID] = []
        
        for i in 0..<100_000 {
            let id = try db1.insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
            
            if i > 0 && i % 10_000 == 0 {
                print("Created \(i) records...")
            }
        }
        
        print("Waiting for sync...")
        try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
        
        // Delete half
        print("Deleting 50,000 records...")
        for i in 0..<50_000 {
            try db1.delete(id: ids[i])
            
            if i > 0 && i % 10_000 == 0 {
                print("Deleted \(i) records...")
            }
        }
        
        print("Waiting for sync...")
        try await Task.sleep(nanoseconds: 5_000_000_000)
        
        // Verify remaining records
        print("Verifying remaining records...")
        var verified = 0
        for i in 50_000..<100_000 {
            let exists = try db2.fetch(id: ids[i])
            if exists != nil {
                verified += 1
            }
        }
        
        print("Verified \(verified) records")
        XCTAssertGreaterThanOrEqual(verified, 49_000, "Should have at least 49,000 records")
        
        await topology.disconnectAll()
    }
    
    func testExtreme_RelayMemoryGC_OneMillionOperations() async throws {
        let relay = InMemoryRelay(fromNodeId: UUID(), toNodeId: UUID(), mode: .bidirectional)
        try await relay.connect()
        
        // Create 1 million operations
        print("Creating 1 million operations in relay...")
        let recordId = UUID()
        
        for i in 0..<1_000_000 {
            let op = BlazeOperation(
                timestamp: LamportTimestamp(counter: UInt64(i), nodeId: UUID()),
                nodeId: UUID(),
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
            try await relay.pushOperations([op])
            
            if i > 0 && i % 100_000 == 0 {
                print("Created \(i) operations...")
            }
        }
        
        print("Running GC on 1 million operations...")
        let startTime = Date()
        
        try await relay.limitQueueSize(maxSize: 1000)
        
        let duration = Date().timeIntervalSince(startTime)
        let stats = await relay.getQueueStats()
        
        print("GC completed in \(String(format: "%.2f", duration))s")
        print("Final queue size: \(stats.queueSize)")
        
        XCTAssertLessThanOrEqual(stats.queueSize, 1000, "Queue should be limited to 1000")
        XCTAssertLessThan(duration, 30.0, "GC should complete in under 30 seconds")
        
        await relay.disconnect()
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryPressure_OperationLogGC_UnderMemoryPressure() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create large operation log
        let recordId = UUID()
        for i in 0..<500_000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i), "data": .data(Data(repeating: 0, count: 100))])
        }
        
        // Measure memory before GC
        let statsBefore = await opLog.getStats()
        print("Operations before GC: \(statsBefore.totalOperations)")
        
        // Run GC under memory pressure
        measure(metrics: [XCTMemoryMetric()]) {
            do {
                try await opLog.cleanupOldOperations(keepLast: 1000)
            } catch {
                XCTFail("GC failed: \(error)")
            }
        }
        
        // Measure memory after GC
        let statsAfter = await opLog.getStats()
        print("Operations after GC: \(statsAfter.totalOperations)")
        
        let reduction = Double(statsBefore.totalOperations - statsAfter.totalOperations) / Double(statsBefore.totalOperations) * 100
        print("Memory reduction: \(String(format: "%.1f", reduction))%")
        
        XCTAssertGreaterThan(reduction, 99.0, "Should reduce operations by at least 99%")
    }
    
    // MARK: - Concurrent Stress Tests
    
    func testConcurrentStress_OperationLogGC_ManyThreads() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create operations
        let recordId = UUID()
        for i in 0..<100_000 {
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i)]
            )
        }
        
        // Run GC from 50 concurrent threads
        let group = DispatchGroup()
        var errors: [Error] = []
        let lock = NSLock()
        
        for _ in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                Task {
                    do {
                        try await opLog.cleanupOldOperations(keepLast: 1000)
                    } catch {
                        lock.lock()
                        errors.append(error)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        
        group.wait()
        
        XCTAssertTrue(errors.isEmpty, "No errors during concurrent GC: \(errors.count) errors")
        
        // Verify final state
        let stats = await opLog.getStats()
        XCTAssertLessThanOrEqual(stats.totalOperations, 1000, "Should keep only last 1000 operations")
    }
    
    // MARK: - Disk Space Tests
    
    func testDiskSpace_OperationLogGC_DiskSpaceReduction() async throws {
        let opLogURL = tempDir.appendingPathComponent("op_log.json")
        let opLog = OperationLog(nodeId: UUID(), storageURL: opLogURL)
        
        // Create large operation log with data
        let recordId = UUID()
        for i in 0..<100_000 {
            let largeData = Data(repeating: UInt8(i % 256), count: 1000)
            _ = await opLog.recordOperation(
                type: .update,
                collectionName: "test",
                recordId: recordId,
                changes: ["value": .int(i), "data": .data(largeData)]
            )
        }
        
        // Save to disk
        try await opLog.save()
        
        // Get file size before GC
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: opLogURL.path)
        let sizeBefore = attributesBefore[.size] as! Int64
        print("File size before GC: \(ByteCountFormatter.string(fromByteCount: sizeBefore, countStyle: .file))")
        
        // Run GC
        try await opLog.cleanupOldOperations(keepLast: 1000)
        try await opLog.save()
        
        // Get file size after GC
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: opLogURL.path)
        let sizeAfter = attributesAfter[.size] as! Int64
        print("File size after GC: \(ByteCountFormatter.string(fromByteCount: sizeAfter, countStyle: .file))")
        
        let reduction = Double(sizeBefore - sizeAfter) / Double(sizeBefore) * 100
        print("Disk space reduction: \(String(format: "%.1f", reduction))%")
        
        XCTAssertGreaterThan(reduction, 90.0, "Should reduce disk space by at least 90%")
        XCTAssertLessThan(sizeAfter, sizeBefore, "File size should decrease after GC")
    }
}

