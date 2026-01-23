//
//  TopologyTests.swift
//  BlazeDBTests
//
//  Tests for BlazeTopology multi-database coordination
//

import XCTest
@testable import BlazeDBCore

final class TopologyTests: XCTestCase {
    var tempDir: URL!
    
    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TopologyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Node Registration
    
    func testRegisterDatabase() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        
        let nodeId = try await topology.register(db: bugsDB, name: "bugs")
        
        let nodes = await topology.getNodes()
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "bugs")
        XCTAssertEqual(nodes.first?.nodeId, nodeId)
    }
    
    func testRegisterMultipleDatabases() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        let usersDB = try BlazeDBClient(name: "Users", fileURL: usersURL, password: "pass")
        
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        let usersNode = try await topology.register(db: usersDB, name: "users")
        
        let nodes = await topology.getNodes()
        XCTAssertEqual(nodes.count, 2)
        XCTAssertNotEqual(bugsNode, usersNode)
    }
    
    // MARK: - Local Connections
    
    func testConnectLocalDatabases() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        let usersDB = try BlazeDBClient(name: "Users", fileURL: usersURL, password: "pass")
        
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        let usersNode = try await topology.register(db: usersDB, name: "users")
        
        try await topology.connectLocal(
            from: bugsNode,
            to: usersNode,
            mode: .bidirectional
        )
        
        let connections = await topology.getConnections(for: bugsNode)
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections.first?.type, .local)
    }
    
    func testLocalConnectionReadOnly() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let dashboardURL = tempDir.appendingPathComponent("dashboard.blazedb")
        
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        let dashboardDB = try BlazeDBClient(name: "Dashboard", fileURL: dashboardURL, password: "pass")
        
        // Insert bug in bugs DB
        let bugId = try bugsDB.insert(BlazeDataRecord([
            "title": .string("Test Bug"),
            "status": .string("open")
        ]))
        
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        let dashboardNode = try await topology.register(db: dashboardDB, name: "dashboard")
        
        // Connect read-only (dashboard can read bugs)
        try await topology.connectLocal(
            from: bugsNode,
            to: dashboardNode,
            mode: .readOnly
        )
        
        // Dashboard should be able to read bugs
        // (This will be tested more thoroughly with sync engine)
        XCTAssertNotNil(bugId)
    }
    
    // MARK: - Topology Graph
    
    func testGetTopologyGraph() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let usersURL = tempDir.appendingPathComponent("users.blazedb")
        
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        let usersDB = try BlazeDBClient(name: "Users", fileURL: usersURL, password: "pass")
        
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        let usersNode = try await topology.register(db: usersDB, name: "users")
        
        try await topology.connectLocal(from: bugsNode, to: usersNode, mode: .bidirectional)
        
        let graph = await topology.getTopologyGraph()
        let visualization = graph.visualize()
        
        XCTAssertTrue(visualization.contains("bugs"))
        XCTAssertTrue(visualization.contains("users"))
        XCTAssertTrue(visualization.contains("local"))
    }
    
    // MARK: - Error Cases
    
    func testConnectLocalWithInvalidNode() async throws {
        let topology = BlazeTopology()
        
        let bugsURL = tempDir.appendingPathComponent("bugs.blazedb")
        let bugsDB = try BlazeDBClient(name: "Bugs", fileURL: bugsURL, password: "pass")
        let bugsNode = try await topology.register(db: bugsDB, name: "bugs")
        
        let invalidNode = UUID()
        
        do {
            try await topology.connectLocal(from: bugsNode, to: invalidNode, mode: .bidirectional)
            XCTFail("Should have thrown TopologyError.nodeNotFound")
        } catch TopologyError.nodeNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

