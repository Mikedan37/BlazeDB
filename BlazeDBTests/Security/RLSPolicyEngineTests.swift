//
//  RLSPolicyEngineTests.swift
//  BlazeDBTests
//
//  Tests for PolicyEngine and policy evaluation
//

import XCTest
@testable import BlazeDB

final class RLSPolicyEngineTests: XCTestCase {
    
    var engine: PolicyEngine!
    
    override func setUp() {
        super.setUp()
        engine = PolicyEngine()
        engine.setEnabled(true)
    }
    
    // MARK: - Basic Policy Tests
    
    func testPolicyEngine_UserOwnsRecord() {
        let userID = UUID()
        let otherUserID = UUID()
        
        let context = SecurityContext(userID: userID)
        
        // Add policy: user can only access their own records
        engine.addPolicy(.userOwnsRecord())
        
        // Record owned by user
        let ownRecord = BlazeDataRecord(["userId": .uuid(userID)])
        XCTAssertTrue(engine.isAllowed(operation: .select, context: context, record: ownRecord))
        
        // Record owned by other user
        let otherRecord = BlazeDataRecord(["userId": .uuid(otherUserID)])
        XCTAssertFalse(engine.isAllowed(operation: .select, context: context, record: otherRecord))
    }
    
    func testPolicyEngine_UserInTeam() {
        let userID = UUID()
        let teamA = UUID()
        let teamB = UUID()
        
        let context = SecurityContext(userID: userID, teamIDs: [teamA])
        
        // Add policy: user can access team records
        engine.addPolicy(.userInTeam())
        
        // Record in user's team
        let teamRecord = BlazeDataRecord(["teamId": .uuid(teamA)])
        XCTAssertTrue(engine.isAllowed(operation: .select, context: context, record: teamRecord))
        
        // Record in other team
        let otherTeamRecord = BlazeDataRecord(["teamId": .uuid(teamB)])
        XCTAssertFalse(engine.isAllowed(operation: .select, context: context, record: otherTeamRecord))
    }
    
    func testPolicyEngine_AdminFullAccess() {
        let adminContext = SecurityContext(userID: UUID(), roles: ["admin"])
        let userContext = SecurityContext(userID: UUID(), roles: ["member"])
        
        // Add admin policy
        engine.addPolicy(.adminFullAccess())
        
        let record = BlazeDataRecord(["userId": .uuid(UUID())])  // Not owned by either
        
        XCTAssertTrue(engine.isAllowed(operation: .select, context: adminContext, record: record))
        XCTAssertFalse(engine.isAllowed(operation: .select, context: userContext, record: record))
    }
    
    func testPolicyEngine_PublicRead() {
        let anyContext = SecurityContext(userID: UUID())
        
        // Add public read policy
        engine.addPolicy(.publicRead)
        
        let record = BlazeDataRecord(["public": .bool(true)])
        
        XCTAssertTrue(engine.isAllowed(operation: .select, context: anyContext, record: record))
    }
    
    func testPolicyEngine_ViewerReadOnly() {
        let viewerContext = SecurityContext(userID: UUID(), roles: ["viewer"])
        
        engine.addPolicy(.viewerReadOnly())
        
        let record = BlazeDataRecord(["data": .string("test")])
        
        // Viewer can SELECT
        XCTAssertTrue(engine.isAllowed(operation: .select, context: viewerContext, record: record))
        
        // Viewer cannot INSERT/UPDATE/DELETE
        XCTAssertFalse(engine.isAllowed(operation: .insert, context: viewerContext, record: record))
        XCTAssertFalse(engine.isAllowed(operation: .update, context: viewerContext, record: record))
        XCTAssertFalse(engine.isAllowed(operation: .delete, context: viewerContext, record: record))
    }
    
    // MARK: - Multiple Policies
    
    func testPolicyEngine_MultiplePolicies() {
        let userID = UUID()
        let teamID = UUID()
        
        let context = SecurityContext(userID: userID, teamIDs: [teamID], roles: ["member"])
        
        // Add both policies
        engine.addPolicy(.userOwnsRecord())
        engine.addPolicy(.userInTeam())
        
        // Record owned by user
        let ownRecord = BlazeDataRecord(["userId": .uuid(userID)])
        XCTAssertTrue(engine.isAllowed(operation: .select, context: context, record: ownRecord))
        
        // Record in user's team
        let teamRecord = BlazeDataRecord(["teamId": .uuid(teamID)])
        XCTAssertTrue(engine.isAllowed(operation: .select, context: context, record: teamRecord))
        
        // Record neither owned nor in team
        let otherRecord = BlazeDataRecord(["userId": .uuid(UUID()), "teamId": .uuid(UUID())])
        XCTAssertFalse(engine.isAllowed(operation: .select, context: context, record: otherRecord))
    }
    
    // MARK: - Filter Records
    
    func testPolicyEngine_FilterRecords() {
        let userID = UUID()
        let context = SecurityContext(userID: userID)
        
        engine.addPolicy(.userOwnsRecord())
        
        let records = [
            BlazeDataRecord(["userId": .uuid(userID), "title": .string("My record")]),
            BlazeDataRecord(["userId": .uuid(UUID()), "title": .string("Other record")]),
            BlazeDataRecord(["userId": .uuid(userID), "title": .string("My record 2")]),
        ]
        
        let filtered = engine.filterRecords(operation: .select, context: context, records: records)
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.storage["userId"]?.uuidValue == userID })
    }
    
    // MARK: - Enable/Disable
    
    func testPolicyEngine_CanBeDisabled() {
        let userID = UUID()
        let context = SecurityContext(userID: userID)
        
        engine.addPolicy(.userOwnsRecord())
        
        let otherRecord = BlazeDataRecord(["userId": .uuid(UUID())])
        
        // Enabled: should deny
        engine.setEnabled(true)
        XCTAssertFalse(engine.isAllowed(operation: .select, context: context, record: otherRecord))
        
        // Disabled: should allow
        engine.setEnabled(false)
        XCTAssertTrue(engine.isAllowed(operation: .select, context: context, record: otherRecord))
    }
    
    // MARK: - Custom Policies
    
    func testPolicyEngine_CustomPolicy() {
        let context = SecurityContext(userID: UUID(), roles: ["moderator"])
        
        // Custom policy: moderators can only update "approved" records
        let policy = SecurityPolicy(
            name: "moderator_approved_only",
            operation: .update,
            type: .restrictive
        ) { ctx, record in
            guard ctx.hasRole("moderator") else { return false }
            return record.storage["approved"]?.boolValue == true
        }
        
        engine.addPolicy(policy)
        
        let approvedRecord = BlazeDataRecord(["approved": .bool(true)])
        let unapprovedRecord = BlazeDataRecord(["approved": .bool(false)])
        
        XCTAssertTrue(engine.isAllowed(operation: .update, context: context, record: approvedRecord))
        XCTAssertFalse(engine.isAllowed(operation: .update, context: context, record: unapprovedRecord))
    }
}

