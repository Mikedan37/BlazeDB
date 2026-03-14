//
//  AccessManager.swift
//  BlazeDB
//
//  User and access management for RLS
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// User account for access management
internal struct User: Codable {
    internal let id: UUID
    internal var name: String
    internal var email: String
    internal var roles: Set<String>
    internal var teamIDs: [UUID]
    internal var customClaims: [String: String]
    internal var isActive: Bool
    internal let createdAt: Date
    internal var updatedAt: Date
    
    internal init(
        id: UUID = UUID(),
        name: String,
        email: String,
        roles: Set<String> = [],
        teamIDs: [UUID] = [],
        customClaims: [String: String] = [:],
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.roles = roles
        self.teamIDs = teamIDs
        self.customClaims = customClaims
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Convert to SecurityContext
    internal func toSecurityContext() -> SecurityContext {
        return SecurityContext(
            userID: id,
            teamIDs: teamIDs,
            roles: roles,
            customClaims: customClaims
        )
    }
}

/// Team/Organization for multi-tenant access
internal struct Team: Codable {
    internal let id: UUID
    internal var name: String
    internal var memberIDs: [UUID]
    internal var adminIDs: [UUID]
    internal let createdAt: Date
    internal var updatedAt: Date
    
    internal init(
        id: UUID = UUID(),
        name: String,
        memberIDs: [UUID] = [],
        adminIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.adminIDs = adminIDs
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Manages users, teams, and access control
internal final class AccessManager {
    private var users: [UUID: User] = [:]
    private var teams: [UUID: Team] = [:]
    private let lock = NSLock()
    
    internal init() {}
    
    // MARK: - User Management
    
    /// Create a new user
    @discardableResult
    internal func createUser(_ user: User) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        
        users[user.id] = user
        BlazeLogger.info("👤 User created: \(user.name) (\(user.id))")
        return user.id
    }
    
    /// Get user by ID
    internal func getUser(id: UUID) -> User? {
        lock.lock()
        defer { lock.unlock() }
        
        return users[id]
    }
    
    /// Update user
    internal func updateUser(_ user: User) {
        lock.lock()
        defer { lock.unlock() }
        
        var updated = user
        updated.updatedAt = Date()
        users[user.id] = updated
        BlazeLogger.info("👤 User updated: \(user.name)")
    }
    
    /// Delete user
    internal func deleteUser(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        users.removeValue(forKey: id)
        BlazeLogger.info("👤 User deleted: \(id)")
    }
    
    /// List all users
    internal func listUsers() -> [User] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(users.values)
    }
    
    // MARK: - Team Management
    
    /// Create a new team
    @discardableResult
    internal func createTeam(_ team: Team) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        
        teams[team.id] = team
        BlazeLogger.info("🏢 Team created: \(team.name) (\(team.id))")
        return team.id
    }
    
    /// Get team by ID
    internal func getTeam(id: UUID) -> Team? {
        lock.lock()
        defer { lock.unlock() }
        
        return teams[id]
    }
    
    /// Update team
    internal func updateTeam(_ team: Team) {
        lock.lock()
        defer { lock.unlock() }
        
        var updated = team
        updated.updatedAt = Date()
        teams[team.id] = updated
        BlazeLogger.info("🏢 Team updated: \(team.name)")
    }
    
    /// Delete team
    internal func deleteTeam(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        teams.removeValue(forKey: id)
        BlazeLogger.info("🏢 Team deleted: \(id)")
    }
    
    /// List all teams
    internal func listTeams() -> [Team] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(teams.values)
    }
    
    // MARK: - Team Membership
    
    /// Add user to team
    internal func addUserToTeam(userID: UUID, teamID: UUID, asAdmin: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var team = teams[teamID] else {
            BlazeLogger.warn("Team \(teamID) not found")
            return
        }
        
        if !team.memberIDs.contains(userID) {
            team.memberIDs.append(userID)
        }
        
        if asAdmin && !team.adminIDs.contains(userID) {
            team.adminIDs.append(userID)
        }
        
        // Update user's teamIDs
        if var user = users[userID] {
            if !user.teamIDs.contains(teamID) {
                user.teamIDs.append(teamID)
            }
            users[userID] = user
        }
        
        teams[teamID] = team
        BlazeLogger.info("👤 User \(userID) added to team \(teamID)")
    }
    
    /// Remove user from team
    internal func removeUserFromTeam(userID: UUID, teamID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var team = teams[teamID] else { return }
        
        team.memberIDs.removeAll { $0 == userID }
        team.adminIDs.removeAll { $0 == userID }
        
        // Update user's teamIDs
        if var user = users[userID] {
            user.teamIDs.removeAll { $0 == teamID }
            users[userID] = user
        }
        
        teams[teamID] = team
        BlazeLogger.info("👤 User \(userID) removed from team \(teamID)")
    }
    
    // MARK: - Role Management
    
    /// Add role to user
    internal func addRole(_ role: String, to userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var user = users[userID] else { return }
        
        user.roles.insert(role)
        users[userID] = user
        BlazeLogger.info("👤 Role '\(role)' added to user \(userID)")
    }
    
    /// Remove role from user
    internal func removeRole(_ role: String, from userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var user = users[userID] else { return }
        
        user.roles.remove(role)
        users[userID] = user
        BlazeLogger.info("👤 Role '\(role)' removed from user \(userID)")
    }
    
    // MARK: - Helper Methods
    
    /// Get security context for a user
    internal func getSecurityContext(for userID: UUID) -> SecurityContext? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let user = users[userID], user.isActive else {
            return nil
        }
        
        return user.toSecurityContext()
    }
    
    /// Check if user exists and is active
    internal func isUserActive(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return users[id]?.isActive ?? false
    }
}

