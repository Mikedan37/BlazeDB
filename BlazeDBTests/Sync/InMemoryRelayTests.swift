//
//  InMemoryRelayTests.swift
//  BlazeDBTests
//
//  Tests for InMemoryRelay local synchronization
//

import XCTest
@testable import BlazeDBCore

final class InMemoryRelayTests: XCTestCase {
    
    func testConnectAndDisconnect() async throws {
        let fromNode = UUID()
        let toNode = UUID()
        
        let relay = InMemoryRelay(
            fromNodeId: fromNode,
            toNodeId: toNode,
            mode: .bidirectional
        )
        
        try await relay.connect()
        await relay.disconnect()
        
        // Should not throw
        XCTAssertTrue(true)
    }
    
    func testPushAndPullOperations() async throws {
        let fromNode = UUID()
        let toNode = UUID()
        
        let relay = InMemoryRelay(
            fromNodeId: fromNode,
            toNodeId: toNode,
            mode: .bidirectional
        )
        
        try await relay.connect()
        
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: 1, nodeId: fromNode),
            nodeId: fromNode,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Test Bug")]
        )
        
        try await relay.pushOperations([op])
        
        let pulled = try await relay.pullOperations(since: LamportTimestamp(counter: 0, nodeId: fromNode))
        
        XCTAssertEqual(pulled.count, 1)
        XCTAssertEqual(pulled.first?.id, op.id)
    }
    
    func testReadOnlyMode() async throws {
        let fromNode = UUID()
        let toNode = UUID()
        
        let relay = InMemoryRelay(
            fromNodeId: fromNode,
            toNodeId: toNode,
            mode: .readOnly
        )
        
        try await relay.connect()
        
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: 1, nodeId: fromNode),
            nodeId: fromNode,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Test Bug")]
        )
        
        // Push should work (source can push)
        try await relay.pushOperations([op])
        
        // Pull should work (target can pull)
        let pulled = try await relay.pullOperations(since: LamportTimestamp(counter: 0, nodeId: fromNode))
        XCTAssertEqual(pulled.count, 1)
    }
    
    func testOperationHandler() async throws {
        let fromNode = UUID()
        let toNode = UUID()
        
        let relay = InMemoryRelay(
            fromNodeId: fromNode,
            toNodeId: toNode,
            mode: .bidirectional
        )
        
        try await relay.connect()
        
        var receivedOps: [BlazeOperation] = []
        let expectation = expectation(description: "Operation received")
        
        relay.onOperationReceived { ops in
            receivedOps = ops
            expectation.fulfill()
        }
        
        let op = BlazeOperation(
            timestamp: LamportTimestamp(counter: 1, nodeId: fromNode),
            nodeId: fromNode,
            type: .insert,
            collectionName: "bugs",
            recordId: UUID(),
            changes: ["title": .string("Test Bug")]
        )
        
        try await relay.pushOperations([op])
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedOps.count, 1)
        XCTAssertEqual(receivedOps.first?.id, op.id)
    }
    
    func testExchangeSyncState() async throws {
        let fromNode = UUID()
        let toNode = UUID()
        
        let relay = InMemoryRelay(
            fromNodeId: fromNode,
            toNodeId: toNode,
            mode: .bidirectional
        )
        
        try await relay.connect()
        
        let state = try await relay.exchangeSyncState()
        
        XCTAssertEqual(state.nodeId, fromNode)
        XCTAssertEqual(state.operationCount, 0)
    }
}

