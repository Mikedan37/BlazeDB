//
//  AccessManager.swift
//  BlazeDB
//
//  User and access management for RLS
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// User account for access management
public struct User: Codable {
    public let id: UUID
    public var name: String
    public var email: String
    public var roles: Set<String>
    public var teamIDs: [UUID]
    public var customClaims: [String: String]
    public var isActive: Bool
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
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
    public func toSecurityContext() -> SecurityContext {
        return SecurityContext(
            userID: id,
            teamIDs: teamIDs,
            roles: roles,
            customClaims: customClaims
        )
    }
}

/// Team/Organization for multi-tenant access
public struct Team: Codable {
    public let id: UUID
    public var name: String
    public var memberIDs: [UUID]
    public var adminIDs: [UUID]
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
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
public final class AccessManager {
    private var users: [UUID: User] = [:]
    private var teams: [UUID: Team] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    // MARK: - User Management
    
    /// Create a new user
    @discardableResult
    public func createUser(_ user: User) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        
        users[user.id] = user
        BlazeLogger.info("👤 User created: \(user.name) (\(user.id))")
        return user.id
    }
    
    /// Get user by ID
    public func getUser(id: UUID) -> User? {
        lock.lock()
        defer { lock.unlock() }
        
        return users[id]
    }
    
    /// Update user
    public func updateUser(_ user: User) {
        lock.lock()
        defer { lock.unlock() }
        
        var updated = user
        updated.updatedAt = Date()
        users[user.id] = updated
        BlazeLogger.info("👤 User updated: \(user.name)")
    }
    
    /// Delete user
    public func deleteUser(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        users.removeValue(forKey: id)
        BlazeLogger.info("👤 User deleted: \(id)")
    }
    
    /// List all users
    public func listUsers() -> [User] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(users.values)
    }
    
    // MARK: - Team Management
    
    /// Create a new team
    @discardableResult
    public func createTeam(_ team: Team) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        
        teams[team.id] = team
        BlazeLogger.info("🏢 Team created: \(team.name) (\(team.id))")
        return team.id
    }
    
    /// Get team by ID
    public func getTeam(id: UUID) -> Team? {
        lock.lock()
        defer { lock.unlock() }
        
        return teams[id]
    }
    
    /// Update team
    public func updateTeam(_ team: Team) {
        lock.lock()
        defer { lock.unlock() }
        
        var updated = team
        updated.updatedAt = Date()
        teams[team.id] = updated
        BlazeLogger.info("🏢 Team updated: \(team.name)")
    }
    
    /// Delete team
    public func deleteTeam(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        teams.removeValue(forKey: id)
        BlazeLogger.info("🏢 Team deleted: \(id)")
    }
    
    /// List all teams
    public func listTeams() -> [Team] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(teams.values)
    }
    
    // MARK: - Team Membership
    
    /// Add user to team
    public func addUserToTeam(userID: UUID, teamID: UUID, asAdmin: Bool = false) {
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
    public func removeUserFromTeam(userID: UUID, teamID: UUID) {
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
    public func addRole(_ role: String, to userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var user = users[userID] else { return }
        
        user.roles.insert(role)
        users[userID] = user
        BlazeLogger.info("👤 Role '\(role)' added to user \(userID)")
    }
    
    /// Remove role from user
    public func removeRole(_ role: String, from userID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard var user = users[userID] else { return }
        
        user.roles.remove(role)
        users[userID] = user
        BlazeLogger.info("👤 Role '\(role)' removed from user \(userID)")
    }
    
    // MARK: - Helper Methods
    
    /// Get security context for a user
    public func getSecurityContext(for userID: UUID) -> SecurityContext? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let user = users[userID], user.isActive else {
            return nil
        }
        
        return user.toSecurityContext()
    }
    
    /// Check if user exists and is active
    public func isUserActive(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return users[id]?.isActive ?? false
    }
}

