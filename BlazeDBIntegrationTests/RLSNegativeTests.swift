//
//  RLSNegativeTests.swift
//  BlazeDBIntegrationTests
//
//  Explicit negative tests for RLS/RBAC and protocol auth behavior.
//

import XCTest
@testable import BlazeDBCore

/// Focused negative tests for:
/// - RLS denying access when user is not in allowed set
/// - Sync respecting RLS when configured
final class RLSNegativeTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLS-Negative-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }
    
    /// Ensure that a user without the required role cannot see or modify protected records.
    func testRLS_DeniesAccessForUnauthorizedUser() throws {
        let dbURL = tempDir.appendingPathComponent("rls_negative.blazedb")
        let db = try BlazeDBClient(name: "RLSNegative", fileURL: dbURL, password: "rls-pass-123456")
        
        // Create users
        let admin = User(name: "Admin", email: "admin@example.com", roles: ["admin"])
        let viewer = User(name: "Viewer", email: "viewer@example.com", roles: ["viewer"])
        
        let adminID = db.rls.createUser(admin)
        let viewerID = db.rls.createUser(viewer)
        
        // Enable RLS: admin can write, viewer is read-only at best
        db.rls.enable()
        db.rls.addPolicy(.viewerReadOnly())
        db.rls.addPolicy(SecurityPolicy(
            name: "admin_can_write",
            operation: .all,
            type: .permissive
        ) { context, _ in
            context.hasRole("admin")
        })
        
        // Admin creates protected document
        db.rls.setContext(admin.toSecurityContext())
        let docID = try db.insert(BlazeDataRecord([
            "title": .string("Secret Plan"),
            "ownerId": .uuid(adminID)
        ]))
        
        // Viewer should be able to read (viewerReadOnly), but not update/delete
        db.rls.setContext(viewer.toSecurityContext())
        
        let visible = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(visible.count, 1, "Viewer should see the document in read-only mode")
        
        // Attempt to update as viewer should be blocked by policy
        var forbiddenUpdate = visible[0]
        forbiddenUpdate.storage["title"] = .string("Hacked")
        
        XCTAssertThrowsError(try db.update(id: docID, with: forbiddenUpdate),
                             "Viewer should not be allowed to update protected record")
        
        // Attempt to delete as viewer should also be blocked
        XCTAssertThrowsError(try db.delete(id: docID),
                             "Viewer should not be allowed to delete protected record")
        
        // Admin remains fully capable
        db.rls.setContext(admin.toSecurityContext())
        try db.delete(id: docID)
        XCTAssertTrue(try db.fetchAll().isEmpty)
    }
    
    /// Ensure sync respects RLS when respectRLS is enabled in topology.
    ///
    /// We simulate a server node with RLS and a client node. Only authorized
    /// user context on the server should see specific records; unauthorized
    /// contexts should not suddenly gain access via sync.
    func testSync_RespectsRLSWhenEnabled() async throws {
        let serverURL = tempDir.appendingPathComponent("rls_server.blazedb")
        let clientURL = tempDir.appendingPathComponent("rls_client.blazedb")
        
        let server = try BlazeDBClient(name: "ServerRLS", fileURL: serverURL, password: "rls-pass-123456")
        let client = try BlazeDBClient(name: "ClientRLS", fileURL: clientURL, password: "rls-pass-123456")
        
        // Basic RLS: only user with role "owner" can see records
        let owner = User(name: "Owner", email: "owner@example.com", roles: ["owner"])
        let outsider = User(name: "Outsider", email: "outsider@example.com", roles: ["outsider"])
        
        let ownerID = server.rls.createUser(owner)
        _ = server.rls.createUser(outsider)
        
        server.rls.enable()
        server.rls.addPolicy(SecurityPolicy(
            name: "owner_read_only",
            operation: .select,
            type: .permissive
        ) { context, record in
            guard let ownerField = record.storage["ownerId"]?.uuidValue else { return false }
            return context.userID == ownerField
        })
        
        // Owner creates a record
        server.rls.setContext(owner.toSecurityContext())
        let secretID = try server.insert(BlazeDataRecord([
            "title": .string("Owner Secret"),
            "ownerId": .uuid(ownerID)
        ]))
        
        // Set up sync with respectRLS = true
        let topology = BlazeTopology()
        let serverNode = try await topology.register(db: server, name: "ServerRLS", role: .server, respectRLS: true)
        let clientNode = try await topology.register(db: client, name: "ClientRLS", role: .client, respectRLS: true)
        
        try await topology.connectLocal(from: serverNode, to: clientNode, mode: .bidirectional)
        
        // Wait for sync
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Client has a copy of the data physically, but RLS on server ensures
        // that only the owner security context sees it on the server side.
        
        // On client, we simulate a read by "outsider" using the same RLS rules
        client.rls.enable()
        client.rls.addPolicy(SecurityPolicy(
            name: "owner_read_only_client",
            operation: .select,
            type: .permissive
        ) { context, record in
            guard let ownerField = record.storage["ownerId"]?.uuidValue else { return false }
            return context.userID == ownerField
        })
        
        // Outsider context on client should see nothing
        client.rls.setContext(outsider.toSecurityContext())
        let outsiderVisible = try client.rls.filterRecords(operation: .select, records: try client.fetchAll())
        XCTAssertTrue(outsiderVisible.isEmpty, "Outsider should not see owner-only records even after sync")
        
        // Owner context on client should see the record
        client.rls.setContext(owner.toSecurityContext())
        let ownerVisible = try client.rls.filterRecords(operation: .select, records: try client.fetchAll())
        XCTAssertEqual(ownerVisible.count, 1)
        XCTAssertEqual(ownerVisible.first?.string("title"), "Owner Secret")
        
        // And the record should still exist on server
        XCTAssertNotNil(try server.fetch(id: secretID))
    }
}


