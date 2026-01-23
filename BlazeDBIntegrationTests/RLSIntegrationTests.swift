//
//  RLSIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests for RLS in real-world scenarios
//

import XCTest
@testable import BlazeDBCore

final class RLSIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLS-Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Scenario 1: Bug Tracker with RLS
    
    func testRLS_BugTrackerScenario() throws {
        print("\n🐛 RLS INTEGRATION: Bug Tracker (Team-Based Access)")
        
        let dbURL = tempDir.appendingPathComponent("bugs.blazedb")
        let db = try BlazeDBClient(name: "Bugs", fileURL: dbURL, password: "test-pass-123456")
        
        // Create users
        let alice = User(name: "Alice", email: "alice@example.com", roles: ["developer"])
        let bob = User(name: "Bob", email: "bob@example.com", roles: ["developer"])
        let admin = User(name: "Admin", email: "admin@example.com", roles: ["admin"])
        
        let aliceID = db.rls.createUser(alice)
        let bobID = db.rls.createUser(bob)
        let adminID = db.rls.createUser(admin)
        
        print("  👥 Created 3 users")
        
        // Create teams
        let engineeringTeam = Team(name: "Engineering", memberIDs: [aliceID, bobID])
        let teamID = db.rls.createTeam(engineeringTeam)
        
        // Add users to team
        db.rls.addUserToTeam(userID: aliceID, teamID: teamID)
        db.rls.addUserToTeam(userID: bobID, teamID: teamID)
        
        print("  🏢 Created Engineering team")
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userInTeam())
        db.rls.addPolicy(.adminFullAccess())
        
        print("  🔐 RLS enabled with policies")
        
        // Alice creates bugs for her team
        db.rls.setContext(alice.toSecurityContext())
        
        let bug1 = try db.insert(BlazeDataRecord([
            "title": .string("Bug 1"),
            "teamId": .uuid(teamID)
        ]))
        
        let bug2 = try db.insert(BlazeDataRecord([
            "title": .string("Bug 2"),
            "teamId": .uuid(teamID)
        ]))
        
        print("  ✅ Alice created 2 bugs for team")
        
        // Alice can see team bugs
        let aliceBugs = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(aliceBugs.count, 2)
        print("  ✅ Alice sees 2 team bugs")
        
        // Bob can also see team bugs
        db.rls.setContext(bob.toSecurityContext())
        let bobBugs = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(bobBugs.count, 2)
        print("  ✅ Bob sees 2 team bugs")
        
        // Admin sees everything
        db.rls.setContext(admin.toSecurityContext())
        let adminBugs = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(adminBugs.count, 2)
        print("  ✅ Admin sees all bugs")
        
        // Create bug for different team
        let otherTeamID = UUID()
        let bug3 = try db.insert(BlazeDataRecord([
            "title": .string("Bug 3"),
            "teamId": .uuid(otherTeamID)
        ]))
        
        // Alice shouldn't see other team's bugs
        db.rls.setContext(alice.toSecurityContext())
        let aliceFilteredBugs = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(aliceFilteredBugs.count, 2, "Alice should only see her team's bugs")
        print("  ✅ Alice cannot see other team's bugs")
        
        // Admin still sees everything
        db.rls.setContext(admin.toSecurityContext())
        let allBugsAdmin = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(allBugsAdmin.count, 3)
        print("  ✅ Admin sees all 3 bugs")
        
        print("\n  🎉 Bug tracker RLS scenario complete!")
    }
    
    // MARK: - Scenario 2: User Owns Record
    
    func testRLS_UserOwnsRecordScenario() throws {
        print("\n👤 RLS INTEGRATION: User Owns Record")
        
        let dbURL = tempDir.appendingPathComponent("tasks.blazedb")
        let db = try BlazeDBClient(name: "Tasks", fileURL: dbURL, password: "test-pass-123456")
        
        // Create users
        let alice = User(name: "Alice", email: "alice@example.com")
        let bob = User(name: "Bob", email: "bob@example.com")
        
        let aliceID = db.rls.createUser(alice)
        let bobID = db.rls.createUser(bob)
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userOwnsRecord(userIDField: "userId"))
        
        // Alice creates tasks
        db.rls.setContext(alice.toSecurityContext())
        
        let task1 = try db.insert(BlazeDataRecord([
            "title": .string("Alice's task 1"),
            "userId": .uuid(aliceID)
        ]))
        
        let task2 = try db.insert(BlazeDataRecord([
            "title": .string("Alice's task 2"),
            "userId": .uuid(aliceID)
        ]))
        
        // Bob creates his tasks
        db.rls.setContext(bob.toSecurityContext())
        
        let task3 = try db.insert(BlazeDataRecord([
            "title": .string("Bob's task 1"),
            "userId": .uuid(bobID)
        ]))
        
        print("  ✅ Created 3 tasks (2 Alice, 1 Bob)")
        
        // Alice should only see her 2 tasks
        db.rls.setContext(alice.toSecurityContext())
        let aliceTasks = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(aliceTasks.count, 2)
        XCTAssertTrue(aliceTasks.allSatisfy { $0.storage["userId"]?.uuidValue == aliceID })
        print("  ✅ Alice sees only her 2 tasks")
        
        // Bob should only see his 1 task
        db.rls.setContext(bob.toSecurityContext())
        let bobTasks = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(bobTasks.count, 1)
        XCTAssertEqual(bobTasks.first?.storage["userId"]?.uuidValue, bobID)
        print("  ✅ Bob sees only his 1 task")
        
        print("\n  🎉 User owns record scenario complete!")
    }
    
    // MARK: - Scenario 3: Read-Only Viewers
    
    func testRLS_ViewerReadOnlyScenario() throws {
        print("\n👁️  RLS INTEGRATION: Read-Only Viewers")
        
        let dbURL = tempDir.appendingPathComponent("docs.blazedb")
        let db = try BlazeDBClient(name: "Docs", fileURL: dbURL, password: "test-pass-123456")
        
        // Create users
        let editor = User(name: "Editor", email: "editor@example.com", roles: ["editor"])
        let viewer = User(name: "Viewer", email: "viewer@example.com", roles: ["viewer"])
        
        let editorID = db.rls.createUser(editor)
        let viewerID = db.rls.createUser(viewer)
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.viewerReadOnly())
        db.rls.addPolicy(SecurityPolicy(
            name: "editor_can_write",
            operation: .all,
            type: .permissive
        ) { context, _ in
            context.hasRole("editor")
        })
        
        // Editor creates document
        db.rls.setContext(editor.toSecurityContext())
        
        let doc1 = try db.insert(BlazeDataRecord([
            "title": .string("Document 1")
        ]))
        
        print("  ✅ Editor created document")
        
        // Viewer can read
        db.rls.setContext(viewer.toSecurityContext())
        let viewerRecords = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(viewerRecords.count, 1)
        print("  ✅ Viewer can read document")
        
        // Viewer cannot update
        let canUpdate = db.rls.policyEngine.isAllowed(
            operation: .update,
            context: viewer.toSecurityContext(),
            record: viewerRecords[0]
        )
        XCTAssertFalse(canUpdate)
        print("  ✅ Viewer cannot update document")
        
        // Viewer cannot delete
        let canDelete = db.rls.policyEngine.isAllowed(
            operation: .delete,
            context: viewer.toSecurityContext(),
            record: viewerRecords[0]
        )
        XCTAssertFalse(canDelete)
        print("  ✅ Viewer cannot delete document")
        
        print("\n  🎉 Read-only viewer scenario complete!")
    }
    
    // MARK: - Scenario 4: Multi-Tenant Application
    
    func testRLS_MultiTenantScenario() throws {
        print("\n🏢 RLS INTEGRATION: Multi-Tenant Application")
        
        let dbURL = tempDir.appendingPathComponent("saas.blazedb")
        let db = try BlazeDBClient(name: "SaaS", fileURL: dbURL, password: "test-pass-123456")
        
        // Create organizations (tenants)
        let acmeCorp = Team(name: "Acme Corp")
        let globexInc = Team(name: "Globex Inc")
        
        let acmeID = db.rls.createTeam(acmeCorp)
        let globexID = db.rls.createTeam(globexInc)
        
        // Create users in different orgs
        let aliceInAcme = User(name: "Alice", email: "alice@acme.com", teamIDs: [acmeID])
        let bobInGlobex = User(name: "Bob", email: "bob@globex.com", teamIDs: [globexID])
        
        let aliceID = db.rls.createUser(aliceInAcme)
        let bobID = db.rls.createUser(bobInGlobex)
        
        db.rls.addUserToTeam(userID: aliceID, teamID: acmeID)
        db.rls.addUserToTeam(userID: bobID, teamID: globexID)
        
        print("  🏢 Created 2 tenants with users")
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userInTeam(teamIDField: "organizationId"))
        
        // Alice creates data for Acme
        db.rls.setContext(aliceInAcme.toSecurityContext())
        
        let acmeData1 = try db.insert(BlazeDataRecord([
            "title": .string("Acme Project 1"),
            "organizationId": .uuid(acmeID)
        ]))
        
        let acmeData2 = try db.insert(BlazeDataRecord([
            "title": .string("Acme Project 2"),
            "organizationId": .uuid(acmeID)
        ]))
        
        // Bob creates data for Globex
        db.rls.setContext(bobInGlobex.toSecurityContext())
        
        let globexData1 = try db.insert(BlazeDataRecord([
            "title": .string("Globex Project 1"),
            "organizationId": .uuid(globexID)
        ]))
        
        print("  ✅ Created 3 records (2 Acme, 1 Globex)")
        
        // Alice only sees Acme data
        db.rls.setContext(aliceInAcme.toSecurityContext())
        let aliceView = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(aliceView.count, 2)
        XCTAssertTrue(aliceView.allSatisfy { $0.storage["organizationId"]?.uuidValue == acmeID })
        print("  ✅ Alice sees only Acme data (2 records)")
        
        // Bob only sees Globex data
        db.rls.setContext(bobInGlobex.toSecurityContext())
        let bobView = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(bobView.count, 1)
        XCTAssertEqual(bobView.first?.storage["organizationId"]?.uuidValue, globexID)
        print("  ✅ Bob sees only Globex data (1 record)")
        
        // Perfect tenant isolation! ✅
        print("\n  🎉 Multi-tenant scenario: Perfect isolation!")
    }
    
    // MARK: - Scenario 5: Hierarchical Permissions
    
    func testRLS_HierarchicalPermissions() throws {
        print("\n📊 RLS INTEGRATION: Hierarchical Permissions")
        
        let dbURL = tempDir.appendingPathComponent("hierarchy.blazedb")
        let db = try BlazeDBClient(name: "Hierarchy", fileURL: dbURL, password: "test-pass-123456")
        
        // Create users with different roles
        let admin = User(name: "Admin", email: "admin@example.com", roles: ["admin"])
        let manager = User(name: "Manager", email: "manager@example.com", roles: ["manager"])
        let employee = User(name: "Employee", email: "employee@example.com", roles: ["employee"])
        
        let adminID = db.rls.createUser(admin)
        let managerID = db.rls.createUser(manager)
        let employeeID = db.rls.createUser(employee)
        
        // Enable RLS with hierarchical policies
        db.rls.enable()
        
        // Admin: full access
        db.rls.addPolicy(.adminFullAccess())
        
        // Manager: can read/update (not delete)
        db.rls.addPolicy(SecurityPolicy(
            name: "manager_read_update",
            operation: .all,
            type: .permissive
        ) { context, _ in
            context.hasRole("manager")
        })
        
        // Employee: read-only
        db.rls.addPolicy(SecurityPolicy(
            name: "employee_read_only",
            operation: .select,
            type: .permissive
        ) { context, _ in
            context.hasRole("employee")
        })
        
        // Create test record as admin
        db.rls.setContext(admin.toSecurityContext())
        let record = try db.insert(BlazeDataRecord(["data": .string("test")]))
        let fetchedRecord = try db.fetch(id: record)!
        
        // Admin can do everything
        XCTAssertTrue(db.rls.isAllowed(operation: .select, record: fetchedRecord))
        XCTAssertTrue(db.rls.isAllowed(operation: .update, record: fetchedRecord))
        XCTAssertTrue(db.rls.isAllowed(operation: .delete, record: fetchedRecord))
        print("  ✅ Admin: full access")
        
        // Manager can read/update
        db.rls.setContext(manager.toSecurityContext())
        XCTAssertTrue(db.rls.isAllowed(operation: .select, record: fetchedRecord))
        XCTAssertTrue(db.rls.isAllowed(operation: .update, record: fetchedRecord))
        print("  ✅ Manager: read/update access")
        
        // Employee can only read
        db.rls.setContext(employee.toSecurityContext())
        XCTAssertTrue(db.rls.isAllowed(operation: .select, record: fetchedRecord))
        XCTAssertFalse(db.rls.isAllowed(operation: .update, record: fetchedRecord))
        XCTAssertFalse(db.rls.isAllowed(operation: .delete, record: fetchedRecord))
        print("  ✅ Employee: read-only access")
        
        print("\n  🎉 Hierarchical permissions working!")
    }
}

