//
//  RLSSecurityContextTests.swift
//  BlazeDBTests
//
//  Tests for SecurityContext and basic RLS
//

import XCTest
@testable import BlazeDB

final class RLSSecurityContextTests: XCTestCase {
    
    // MARK: - SecurityContext Tests
    
    func testSecurityContext_Initialization() {
        let userID = UUID()
        let teamA = UUID()
        let teamB = UUID()
        
        let context = SecurityContext(
            userID: userID,
            teamIDs: [teamA, teamB],
            roles: ["member", "developer"],
            customClaims: ["department": "engineering"]
        )
        
        XCTAssertEqual(context.userID, userID)
        XCTAssertEqual(context.teamIDs.count, 2)
        XCTAssertTrue(context.roles.contains("member"))
        XCTAssertTrue(context.roles.contains("developer"))
        XCTAssertEqual(context.customClaims["department"], "engineering")
    }
    
    func testSecurityContext_HasRole() {
        let context = SecurityContext(
            userID: UUID(),
            roles: ["admin", "developer"]
        )
        
        XCTAssertTrue(context.hasRole("admin"))
        XCTAssertTrue(context.hasRole("developer"))
        XCTAssertFalse(context.hasRole("viewer"))
    }
    
    func testSecurityContext_IsMemberOf() {
        let teamA = UUID()
        let teamB = UUID()
        let teamC = UUID()
        
        let context = SecurityContext(
            userID: UUID(),
            teamIDs: [teamA, teamB]
        )
        
        XCTAssertTrue(context.isMemberOf(team: teamA))
        XCTAssertTrue(context.isMemberOf(team: teamB))
        XCTAssertFalse(context.isMemberOf(team: teamC))
    }
    
    func testSecurityContext_HasClaim() {
        let context = SecurityContext(
            userID: UUID(),
            customClaims: ["department": "engineering", "level": "senior"]
        )
        
        XCTAssertTrue(context.hasClaim("department", value: "engineering"))
        XCTAssertTrue(context.hasClaim("level", value: "senior"))
        XCTAssertFalse(context.hasClaim("department", value: "sales"))
        XCTAssertFalse(context.hasClaim("nonexistent", value: "value"))
    }
    
    func testSecurityContext_AdminContext() {
        let admin = SecurityContext.admin
        
        XCTAssertTrue(admin.hasRole("admin"))
        XCTAssertTrue(admin.hasRole("superuser"))
    }
    
    func testSecurityContext_AnonymousContext() {
        let anon = SecurityContext.anonymous
        
        XCTAssertTrue(anon.hasRole("anonymous"))
        XCTAssertFalse(anon.hasRole("admin"))
    }
}

