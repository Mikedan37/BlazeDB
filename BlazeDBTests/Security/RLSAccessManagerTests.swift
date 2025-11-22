//
//  RLSAccessManagerTests.swift
//  BlazeDBTests
//
//  Tests for AccessManager (user/team management)
//

import XCTest
@testable import BlazeDB

final class RLSAccessManagerTests: XCTestCase {
    
    var accessManager: AccessManager!
    
    override func setUp() {
        super.setUp()
        accessManager = AccessManager()
    }
    
    // MARK: - User Management Tests
    
    func testAccessManager_CreateUser() {
        let user = User(
            name: "Alice",
            email: "alice@example.com",
            roles: ["developer"]
        )
        
        let userID = accessManager.createUser(user)
        
        XCTAssertEqual(userID, user.id)
        
        let retrieved = accessManager.getUser(id: userID)
        XCTAssertEqual(retrieved?.name, "Alice")
        XCTAssertEqual(retrieved?.email, "alice@example.com")
        XCTAssertTrue(retrieved?.roles.contains("developer") ?? false)
    }
    
    func testAccessManager_UpdateUser() {
        var user = User(name: "Bob", email: "bob@example.com")
        accessManager.createUser(user)
        
        user.name = "Bob Updated"
        user.roles.insert("admin")
        accessManager.updateUser(user)
        
        let retrieved = accessManager.getUser(id: user.id)
        XCTAssertEqual(retrieved?.name, "Bob Updated")
        XCTAssertTrue(retrieved?.roles.contains("admin") ?? false)
    }
    
    func testAccessManager_DeleteUser() {
        let user = User(name: "Carol", email: "carol@example.com")
        let userID = accessManager.createUser(user)
        
        accessManager.deleteUser(id: userID)
        
        let retrieved = accessManager.getUser(id: userID)
        XCTAssertNil(retrieved)
    }
    
    func testAccessManager_ListUsers() {
        let user1 = User(name: "Alice", email: "alice@example.com")
        let user2 = User(name: "Bob", email: "bob@example.com")
        
        accessManager.createUser(user1)
        accessManager.createUser(user2)
        
        let users = accessManager.listUsers()
        
        XCTAssertEqual(users.count, 2)
        XCTAssertTrue(users.contains { $0.name == "Alice" })
        XCTAssertTrue(users.contains { $0.name == "Bob" })
    }
    
    // MARK: - Team Management Tests
    
    func testAccessManager_CreateTeam() {
        let team = Team(name: "Engineering")
        
        let teamID = accessManager.createTeam(team)
        
        XCTAssertEqual(teamID, team.id)
        
        let retrieved = accessManager.getTeam(id: teamID)
        XCTAssertEqual(retrieved?.name, "Engineering")
    }
    
    func testAccessManager_UpdateTeam() {
        var team = Team(name: "Design")
        accessManager.createTeam(team)
        
        team.name = "Design Team"
        accessManager.updateTeam(team)
        
        let retrieved = accessManager.getTeam(id: team.id)
        XCTAssertEqual(retrieved?.name, "Design Team")
    }
    
    func testAccessManager_DeleteTeam() {
        let team = Team(name: "Marketing")
        let teamID = accessManager.createTeam(team)
        
        accessManager.deleteTeam(id: teamID)
        
        let retrieved = accessManager.getTeam(id: teamID)
        XCTAssertNil(retrieved)
    }
    
    // MARK: - Team Membership Tests
    
    func testAccessManager_AddUserToTeam() {
        let user = User(name: "Alice", email: "alice@example.com")
        let team = Team(name: "Engineering")
        
        let userID = accessManager.createUser(user)
        let teamID = accessManager.createTeam(team)
        
        accessManager.addUserToTeam(userID: userID, teamID: teamID)
        
        let retrievedTeam = accessManager.getTeam(id: teamID)
        let retrievedUser = accessManager.getUser(id: userID)
        
        XCTAssertTrue(retrievedTeam?.memberIDs.contains(userID) ?? false)
        XCTAssertTrue(retrievedUser?.teamIDs.contains(teamID) ?? false)
    }
    
    func testAccessManager_AddUserAsTeamAdmin() {
        let user = User(name: "Bob", email: "bob@example.com")
        let team = Team(name: "Leadership")
        
        let userID = accessManager.createUser(user)
        let teamID = accessManager.createTeam(team)
        
        accessManager.addUserToTeam(userID: userID, teamID: teamID, asAdmin: true)
        
        let retrievedTeam = accessManager.getTeam(id: teamID)
        
        XCTAssertTrue(retrievedTeam?.memberIDs.contains(userID) ?? false)
        XCTAssertTrue(retrievedTeam?.adminIDs.contains(userID) ?? false)
    }
    
    func testAccessManager_RemoveUserFromTeam() {
        let user = User(name: "Carol", email: "carol@example.com")
        let team = Team(name: "Sales")
        
        let userID = accessManager.createUser(user)
        let teamID = accessManager.createTeam(team)
        
        accessManager.addUserToTeam(userID: userID, teamID: teamID)
        accessManager.removeUserFromTeam(userID: userID, teamID: teamID)
        
        let retrievedTeam = accessManager.getTeam(id: teamID)
        let retrievedUser = accessManager.getUser(id: userID)
        
        XCTAssertFalse(retrievedTeam?.memberIDs.contains(userID) ?? true)
        XCTAssertFalse(retrievedUser?.teamIDs.contains(teamID) ?? true)
    }
    
    // MARK: - Role Management Tests
    
    func testAccessManager_AddRole() {
        let user = User(name: "Dave", email: "dave@example.com")
        let userID = accessManager.createUser(user)
        
        accessManager.addRole("admin", to: userID)
        
        let retrieved = accessManager.getUser(id: userID)
        XCTAssertTrue(retrieved?.roles.contains("admin") ?? false)
    }
    
    func testAccessManager_RemoveRole() {
        let user = User(name: "Eve", email: "eve@example.com", roles: ["admin", "developer"])
        let userID = accessManager.createUser(user)
        
        accessManager.removeRole("admin", from: userID)
        
        let retrieved = accessManager.getUser(id: userID)
        XCTAssertFalse(retrieved?.roles.contains("admin") ?? true)
        XCTAssertTrue(retrieved?.roles.contains("developer") ?? false)
    }
    
    // MARK: - Security Context Generation
    
    func testAccessManager_GetSecurityContext() {
        let teamID = UUID()
        let user = User(
            name: "Frank",
            email: "frank@example.com",
            roles: ["developer"],
            teamIDs: [teamID]
        )
        
        let userID = accessManager.createUser(user)
        
        let context = accessManager.getSecurityContext(for: userID)
        
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.userID, userID)
        XCTAssertTrue(context?.hasRole("developer") ?? false)
        XCTAssertTrue(context?.isMemberOf(team: teamID) ?? false)
    }
    
    func testAccessManager_InactiveUserNoContext() {
        var user = User(name: "Grace", email: "grace@example.com", isActive: false)
        let userID = accessManager.createUser(user)
        
        let context = accessManager.getSecurityContext(for: userID)
        
        XCTAssertNil(context, "Inactive users should not get security context")
    }
}

