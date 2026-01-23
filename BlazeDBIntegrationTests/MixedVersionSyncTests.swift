//
//  MixedVersionSyncTests.swift
//  BlazeDBIntegrationTests
//
//  Tests schema/version compatibility across synced databases.
//

import XCTest
@testable import BlazeDBCore

/// These tests simulate "mixed-version" behavior by using databases with
/// different effective schemas and metadata, then syncing them to ensure:
/// - Older/leaner schema nodes don't crash on richer records
/// - Newer nodes can read older records gracefully
/// - Sync achieves convergence without data loss
final class MixedVersionSyncTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MixedVersion-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }
    
    /// Simulate a "v1" (minimal schema) node syncing with a "v3" (richer schema) node.
    ///
    /// V1: only { title, status }
    /// V3: { title, status, priority, owner, tags[] }
    ///
    /// We assert:
    /// - Sync does not crash
    /// - Both sides can read at least the common fields
    func testMixedSchema_SyncBetweenMinimalAndRichNodes() async throws {
        let v1URL = tempDir.appendingPathComponent("v1_node.blazedb")
        let v3URL = tempDir.appendingPathComponent("v3_node.blazedb")
        
        // "Old" node (v1) uses simple records
        let v1 = try BlazeDBClient(name: "NodeV1", fileURL: v1URL, password: "mixed-pass-123")
        // "New" node (v3) uses richer schema
        let v3 = try BlazeDBClient(name: "NodeV3", fileURL: v3URL, password: "mixed-pass-123")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: v1, name: "NodeV1", role: .server)
        let id3 = try await topology.register(db: v3, name: "NodeV3", role: .client)
        
        try await topology.connectLocal(from: id1, to: id3, mode: .bidirectional)
        
        // Insert V1-style records on v1
        let v1Id = try v1.insert(BlazeDataRecord([
            "title": .string("Legacy Bug"),
            "status": .string("open")
        ]))
        
        // Insert V3-style records on v3
        let v3Id = try v3.insert(BlazeDataRecord([
            "title": .string("Modern Bug"),
            "status": .string("open"),
            "priority": .int(5),
            "owner": .string("new-dev@team.com"),
            "tags": .array([.string("v3"), .string("sync")])
        ]))
        
        // Allow sync to process
        try await Task.sleep(nanoseconds: 700_000_000) // 700ms
        
        // V3 should see legacy record with at least common fields
        if let legacyOnV3 = try v3.fetch(id: v1Id) {
            XCTAssertEqual(legacyOnV3.string("title"), "Legacy Bug")
            XCTAssertEqual(legacyOnV3.string("status"), "open")
        } else {
            XCTFail("V3 node should see legacy record from V1 node")
        }
        
        // V1 should see modern record; extra fields may or may not be present,
        // but common fields must be readable and not crash.
        if let modernOnV1 = try v1.fetch(id: v3Id) {
            XCTAssertEqual(modernOnV1.string("title"), "Modern Bug")
            XCTAssertEqual(modernOnV1.string("status"), "open")
            // We don't assert on priority/owner/tags here to simulate
            // an "older" codebase that ignores unknown fields.
        } else {
            XCTFail("V1 node should see modern record from V3 node (at least common fields)")
        }
    }
}


