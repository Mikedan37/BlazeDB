//
//  UnixDomainSocketTests.swift
//  BlazeDBTests
//
//  Unit and integration tests for Unix Domain Socket relay
//

import XCTest
@testable import BlazeDBCore

final class UnixDomainSocketTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb_unix_socket_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        BlazeLogger.level = .debug
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        BlazeLogger.reset()
        super.tearDown()
    }
    
    // MARK: - Unit Tests
    
    /// Test Unix Domain Socket relay creation
    func testUnixDomainSocketRelay_Creation() async throws {
        let socketPath = tempDir.appendingPathComponent("test.sock").path
        let fromNodeId = UUID()
        let toNodeId = UUID()
        
        let relay = UnixDomainSocketRelay(
            socketPath: socketPath,
            fromNodeId: fromNodeId,
            toNodeId: toNodeId,
            mode: .bidirectional
        )
        
        // Relay should be created successfully
        XCTAssertNotNil(relay)
    }
    
    /// Test BlazeBinary encoding/decoding of operations
    func testBlazeBinaryEncoding() throws {
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: 1, nodeId: UUID()),
            nodeId: UUID(),
            type: .insert,
            collectionName: "test",
            recordId: UUID(),
            changes: ["field": .string("value")]
        )
        
        // Encode to BlazeBinary
        let encoded = try BlazeOperation.encodeToBlazeBinary(op)
        XCTAssertGreaterThan(encoded.count, 0, "Encoded data should not be empty")
        
        // Decode from BlazeBinary
        let decoded = try BlazeOperation.decodeFromBlazeBinary(encoded)
        
        // Verify round-trip
        XCTAssertEqual(decoded.id, op.id)
        XCTAssertEqual(decoded.type, op.type)
        XCTAssertEqual(decoded.collectionName, op.collectionName)
        XCTAssertEqual(decoded.recordId, op.recordId)
        XCTAssertEqual(decoded.changes["field"], op.changes["field"])
    }
    
    /// Test multiple operations encoding/decoding
    func testBlazeBinaryEncoding_MultipleOperations() throws {
        var operations: [BlazeOperation] = []
        
        for i in 0..<10 {
            let op = BlazeOperation(
                timestamp: LamportTimestamp(counter: UInt64(i), nodeId: UUID()),
                nodeId: UUID(),
                type: .insert,
                collectionName: "test",
                recordId: UUID(),
                changes: ["index": .int(i)]
            )
            operations.append(op)
        }
        
        // Encode all operations
        var encoded = Data()
        var count = UInt32(operations.count).bigEndian
        encoded.append(Data(bytes: &count, count: 4))
        
        for op in operations {
            let opData = try BlazeOperation.encodeToBlazeBinary(op)
            var opLength = UInt32(opData.count).bigEndian
            encoded.append(Data(bytes: &opLength, count: 4))
            encoded.append(opData)
        }
        
        // Decode all operations
        var offset = 0
        let decodedCount = encoded[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        XCTAssertEqual(Int(decodedCount), 10)
        
        var decodedOps: [BlazeOperation] = []
        for _ in 0..<10 {
            let opLength = Int(encoded[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offset += 4
            let opData = encoded[offset..<offset+opLength]
            offset += opLength
            let op = try BlazeOperation.decodeFromBlazeBinary(opData)
            decodedOps.append(op)
        }
        
        // Verify all operations
        XCTAssertEqual(decodedOps.count, 10)
        for (i, op) in decodedOps.enumerated() {
            XCTAssertEqual(op.int("index"), i)
        }
    }
    
    // MARK: - Integration Tests
    
    /// Test cross-app sync with Unix Domain Sockets (simulated)
    func testCrossAppSync_UnixDomainSocket() async throws {
        // Create two databases (simulating different apps)
        let db1URL = tempDir.appendingPathComponent("app1_db.blazedb")
        let db2URL = tempDir.appendingPathComponent("app2_db.blazedb")
        
        let db1 = try BlazeDBClient(name: "App1DB", fileURL: db1URL, password: "test123")
        let db2 = try BlazeDBClient(name: "App2DB", fileURL: db2URL, password: "test123")
        
        // Create topology
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "App1DB", role: .server)
        let id2 = try await topology.register(db: db2, name: "App2DB", role: .client)
        
        // Create socket path (in temp dir for testing)
        let socketPath = tempDir.appendingPathComponent("blazedb_sync.sock").path
        
        // Connect via Unix Domain Socket
        try await topology.connectCrossApp(
            from: id1,
            to: id2,
            socketPath: socketPath,
            mode: .bidirectional
        )
        
        // Wait for connection
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Insert in db1
        let recordId = try db1.insert(BlazeDataRecord([
            "message": .string("Hello from App1!"),
            "value": .int(42)
        ]))
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Verify synced to db2
        let synced = try db2.fetch(id: recordId)
        XCTAssertNotNil(synced, "Record should sync via Unix Domain Socket")
        XCTAssertEqual(synced?.string("message"), "Hello from App1!")
        XCTAssertEqual(synced?.int("value"), 42)
    }
    
    /// Test bidirectional sync via Unix Domain Socket
    func testCrossAppSync_Bidirectional() async throws {
        let db1URL = tempDir.appendingPathComponent("app1_bidi.blazedb")
        let db2URL = tempDir.appendingPathComponent("app2_bidi.blazedb")
        
        let db1 = try BlazeDBClient(name: "App1", fileURL: db1URL, password: "test123")
        let db2 = try BlazeDBClient(name: "App2", fileURL: db2URL, password: "test123")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "App1", role: .server)
        let id2 = try await topology.register(db: db2, name: "App2", role: .client)
        
        let socketPath = tempDir.appendingPathComponent("bidi_sync.sock").path
        try await topology.connectCrossApp(from: id1, to: id2, socketPath: socketPath, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Insert in both apps
        let id1_record = try db1.insert(BlazeDataRecord(["source": .string("app1"), "value": .int(1)]))
        let id2_record = try db2.insert(BlazeDataRecord(["source": .string("app2"), "value": .int(2)]))
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Verify bidirectional sync
        XCTAssertNotNil(try db2.fetch(id: id1_record), "App1's record should be in App2")
        XCTAssertNotNil(try db1.fetch(id: id2_record), "App2's record should be in App1")
    }
    
    /// Test performance of Unix Domain Socket sync
    func testCrossAppSync_Performance() async throws {
        let db1URL = tempDir.appendingPathComponent("app1_perf.blazedb")
        let db2URL = tempDir.appendingPathComponent("app2_perf.blazedb")
        
        let db1 = try BlazeDBClient(name: "App1", fileURL: db1URL, password: "test123")
        let db2 = try BlazeDBClient(name: "App2", fileURL: db2URL, password: "test123")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "App1", role: .server)
        let id2 = try await topology.register(db: db2, name: "App2", role: .client)
        
        let socketPath = tempDir.appendingPathComponent("perf_sync.sock").path
        try await topology.connectCrossApp(from: id1, to: id2, socketPath: socketPath, mode: .bidirectional)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Insert 1000 records
        let startTime = Date()
        var recordIds: [UUID] = []
        for i in 0..<1000 {
            let id = try db1.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            recordIds.append(id)
        }
        let insertTime = Date().timeIntervalSince(startTime)
        
        // Wait for sync
        let syncStartTime = Date()
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify all synced
        var syncedCount = 0
        for id in recordIds {
            if try db2.fetch(id: id) != nil {
                syncedCount += 1
            }
        }
        let syncTime = Date().timeIntervalSince(syncStartTime)
        
        XCTAssertEqual(syncedCount, 1000, "All records should sync")
        XCTAssertLessThan(insertTime, 5.0, "Insert should be fast")
        XCTAssertLessThan(syncTime, 3.0, "Sync should be fast")
        
        print("✅ Performance: Insert \(insertTime)s, Sync \(syncTime)s")
    }
    
    /// Test error handling (invalid socket path)
    func testCrossAppSync_InvalidSocketPath() async throws {
        let db1URL = tempDir.appendingPathComponent("app1_error.blazedb")
        let db2URL = tempDir.appendingPathComponent("app2_error.blazedb")
        
        let db1 = try BlazeDBClient(name: "App1", fileURL: db1URL, password: "test123")
        let db2 = try BlazeDBClient(name: "App2", fileURL: db2URL, password: "test123")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "App1", role: .server)
        let id2 = try await topology.register(db: db2, name: "App2", role: .client)
        
        // Invalid socket path (non-existent directory)
        let invalidPath = "/nonexistent/path/blazedb.sock"
        
        // Should handle error gracefully
        do {
            try await topology.connectCrossApp(from: id1, to: id2, socketPath: invalidPath, mode: .bidirectional)
            XCTFail("Should have thrown error for invalid socket path")
        } catch {
            // Expected error
            XCTAssertTrue(true, "Error handled correctly")
        }
    }
}

