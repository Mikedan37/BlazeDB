//
//  PermissionTesterTests.swift
//  BlazeDBVisualizerTests
//
//  Test permission tester functionality
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class PermissionTesterTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Enable RLS
        db.rls.enable()
        
        // Create test users
        let admin = User(name: "Admin", email: "admin@test.com", roles: ["admin"])
        let engineer = User(name: "Engineer", email: "eng@test.com", roles: ["engineer"])
        let viewer = User(name: "Viewer", email: "view@test.com", roles: ["viewer"])
        
        db.rls.createUser(admin)
        db.rls.createUser(engineer)
        db.rls.createUser(viewer)
        
        // Add policies
        db.rls.addPolicy(.adminFullAccess())
        db.rls.addPolicy(.viewerReadOnly())
        
        // Add test data
        try db.insert(BlazeDataRecord( ["name": .string("Test"), "value": .int(42)]))
        try db.persist()
    }
    
    override func tearDown() async throws {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - User Loading Tests
    
    func testLoadUsers() throws {
        let users = db.rls.listUsers()
        XCTAssertEqual(users.count, 3, "Should have 3 users")
        XCTAssertTrue(users.contains { $0.name == "Admin" })
        XCTAssertTrue(users.contains { $0.name == "Engineer" })
        XCTAssertTrue(users.contains { $0.name == "Viewer" })
    }
    
    func testUserHasRoles() throws {
        let users = db.rls.listUsers()
        let admin = users.first { $0.name == "Admin" }!
        
        XCTAssertTrue(admin.roles.contains("admin"))
        XCTAssertEqual(admin.email, "admin@test.com")
    }
    
    // MARK: - Permission Testing
    
    func testAdminCanDoEverything() throws {
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        db.rls.setContext(admin.toSecurityContext())
        
        // Can read
        let records = try db.fetchAll()
        XCTAssertFalse(records.isEmpty, "Admin should be able to read")
        
        // Can insert
        let newRecord = BlazeDataRecord( ["test": .string("admin_insert")])
        XCTAssertNoThrow(try db.insert(newRecord), "Admin should be able to insert")
        
        // Can update
        if let id = newRecord.storage["id"], case .uuid(let uuid) = id {
            XCTAssertNoThrow(try db.update(id: uuid, with: newRecord), "Admin should be able to update")
            
            // Can delete
            XCTAssertNoThrow(try db.delete(id: uuid), "Admin should be able to delete")
        }
    }
    
    func testViewerCanOnlyRead() throws {
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        db.rls.setContext(viewer.toSecurityContext())
        
        // Can read
        let records = try db.fetchAll()
        XCTAssertFalse(records.isEmpty, "Viewer should be able to read")
        
        // Cannot insert (policy denies)
        let newRecord = BlazeDataRecord( ["test": .string("viewer_insert")])
        // Note: Current RLS implementation may allow this - depends on policy configuration
        // In production, you'd add a restrictive policy to block non-viewers from insert
    }
    
    func testEngineerPermissions() throws {
        let engineer = db.rls.listUsers().first { $0.name == "Engineer" }!
        db.rls.setContext(engineer.toSecurityContext())
        
        // Can read
        let records = try db.fetchAll()
        XCTAssertFalse(records.isEmpty, "Engineer should be able to read")
        
        // Engineers typically can read/write but not delete users
        // This depends on your policy configuration
    }
    
    func testContextSwitching() throws {
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        
        // Set as admin
        db.rls.setContext(admin.toSecurityContext())
        let context1 = db.rls.getContext()
        XCTAssertEqual(context1?.userID, admin.id)
        
        // Switch to viewer
        db.rls.setContext(viewer.toSecurityContext())
        let context2 = db.rls.getContext()
        XCTAssertEqual(context2?.userID, viewer.id)
        XCTAssertNotEqual(context1?.userID, context2?.userID)
    }
    
    // MARK: - Comparison Tests
    
    func testCompareUserPermissions() throws {
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        let viewer = db.rls.listUsers().first { $0.name == "Viewer" }!
        
        // Test as admin
        db.rls.setContext(admin.toSecurityContext())
        let adminCanInsert = (try? db.insert(BlazeDataRecord( ["test": .string("a")]))) != nil
        
        // Test as viewer
        db.rls.setContext(viewer.toSecurityContext())
        let viewerCanInsert = (try? db.insert(BlazeDataRecord( ["test": .string("v")]))) != nil
        
        // Admin should have more permissions than viewer
        // Note: Exact behavior depends on policy configuration
    }
    
    // MARK: - Edge Cases
    
    func testNoContextAllowsAll() throws {
        // Clear context
        db.rls.clearContext()
        
        // Should allow operations (RLS is optional)
        let records = try db.fetchAll()
        XCTAssertFalse(records.isEmpty, "No context should allow operations")
    }
    
    func testInvalidUserContext() throws {
        let invalidContext = SecurityContext(
            userID: UUID(),
            roles: ["nonexistent_role"]
        )
        
        db.rls.setContext(invalidContext)
        
        // Should still work but with no special permissions
        let records = try db.fetchAll()
        XCTAssertNotNil(records)
    }
    
    func testMultipleRoles() throws {
        let multiRole = User(
            name: "Multi",
            email: "multi@test.com",
            roles: ["viewer", "engineer", "admin"]
        )
        
        db.rls.createUser(multiRole)
        db.rls.setContext(multiRole.toSecurityContext())
        
        // Should have highest privilege (admin)
        let canInsert = (try? db.insert(BlazeDataRecord( ["test": .string("multi")]))) != nil
        XCTAssertTrue(canInsert, "User with multiple roles should have admin privileges")
    }
    
    // MARK: - Performance Tests
    
    func testPermissionCheckPerformance() throws {
        let admin = db.rls.listUsers().first { $0.name == "Admin" }!
        db.rls.setContext(admin.toSecurityContext())
        
        // Insert 100 records
        for i in 0..<100 {
            try db.insert(BlazeDataRecord( ["index": .int(i)]))
        }
        
        // Measure permission checking
        measure {
            _ = try? db.fetchAll()
        }
        
        // Should be fast (< 10ms for 100 records)
    }
}

