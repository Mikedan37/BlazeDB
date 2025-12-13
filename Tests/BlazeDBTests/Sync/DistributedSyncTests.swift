//
//  DistributedSyncTests.swift
//  BlazeDBTests
//
//  Integration tests for distributed synchronization
//

import XCTest
@testable import BlazeDB

final class DistributedSyncTests: XCTestCase {
    var tempDir: URL!
    
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DistributedSyncTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Local Sync Integration
    
    func testLocalSyncBidirectional() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "DistributedSyncTest123!")
        let usersDB = try BlazeDBClient(name: "Users", fileURL: usersURL, password: "DistributedSyncTest123!")
        
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        let usersNode = try await topology.register(db: usersDB, name: "users")
        
        try await topology.connectLocal(
            from: bugsNode,
            to: usersNode,
            mode: .bidirectional
        )
        
        // Insert in bugs DB
        let bugId = try await bugsDB.insert(BlazeDataRecord([
            "title": .string("Test Bug"),
            "status": .string("open")
        ]))
        
        XCTAssertNotNil(bugId)
        
        // Verify topology connection
        let connections = await topology.getConnections(for: bugsNode)
        XCTAssertEqual(connections.count, 1)
    }
    
    func testSyncPolicy() {
        let policy = SyncPolicy(
            collections: ["bugs", "comments"],
            teams: [UUID()],
            excludeFields: ["internalNotes"],
            respectRLS: true,
            encryptionMode: .e2eOnly
        )
        
        XCTAssertEqual(policy.collections?.count, 2)
        XCTAssertEqual(policy.teams?.count, 1)
        XCTAssertEqual(policy.excludeFields.count, 1)
        XCTAssertTrue(policy.respectRLS)
        XCTAssertEqual(policy.encryptionMode, .e2eOnly)
    }
    
    func testRemoteNode() {
        let remote = RemoteNode(
            host: "example.com",
            port: 8080,
            database: "bugs",
            useTLS: true
        )
        
        XCTAssertEqual(remote.host, "example.com")
        XCTAssertEqual(remote.port, 8080)
        XCTAssertEqual(remote.database, "bugs")
        XCTAssertTrue(remote.useTLS)
    }
    
    // MARK: - Operation Log
    
    func testOperationLog() async throws {
        let nodeId = UUID()
        let logURL = tempDir.appendingPathComponent("operation_log.json")
        let opLog = OperationLog(nodeId: nodeId, storageURL: logURL)
        
        // Record operation
        let op = await opLog.recordOperation(
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Test")]
        )
        
        XCTAssertNotNil(op)
        XCTAssertEqual(op.type, .insert)
        XCTAssertEqual(op.collectionName, "bugs")
        
        // Check if contains
        let contains = await opLog.contains(op.id)
        XCTAssertTrue(contains)
        
        // Get operations
        let ops = await opLog.getOperations(since: LamportTimestamp(counter: 0, nodeId: nodeId))
        XCTAssertEqual(ops.count, 1)
        
        // Save and load
        try await opLog.save()
        
        let newLog = OperationLog(nodeId: nodeId, storageURL: logURL)
        try await newLog.load()
        
        let loadedOps = await newLog.getOperations(since: LamportTimestamp(counter: 0, nodeId: nodeId))
        XCTAssertEqual(loadedOps.count, 1)
    }
}

