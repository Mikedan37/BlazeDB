//
//  BlazeUserContext.swift
//  BlazeDB
//
//  Convenience wrapper for user context with role-based access
//  Integrates with existing SecurityContext system
//  Created by Auto on 1/XX/25.
//

import Foundation

/// User role for simplified role-based access control
public enum UserRole: String, Sendable, Codable {
    case admin
    case engineer
    case viewer
    
    /// Convert to SecurityContext role string
    internal var securityRole: String {
        return rawValue
    }
}

/// Convenience user context wrapper for GraphQuery RLS integration
/// Wraps the existing SecurityContext system with simplified role enum
public struct BlazeUserContext: Sendable {
    /// Unique user identifier
    public let userID: UUID
    
    /// User's role (admin/engineer/viewer)
    public let role: UserRole
    
    /// IDs of teams/organizations the user belongs to
    public let teamIDs: [UUID]
    
    /// Initialize a user context
    public init(
        userID: UUID,
        role: UserRole,
        teamIDs: [UUID] = []
    ) {
        self.userID = userID
        self.role = role
        self.teamIDs = teamIDs
    }
    
    /// Convert to SecurityContext (for existing RLS system)
    public func toSecurityContext(customClaims: [String: String] = [:]) -> SecurityContext {
        return SecurityContext(
            userID: userID,
            teamIDs: teamIDs,
            roles: [role.securityRole],
            customClaims: customClaims
        )
    }
    
    /// Check if user is admin (bypasses RLS)
    public var isAdmin: Bool {
        return role == .admin
    }
    
    /// Check if user is engineer
    public var isEngineer: Bool {
        return role == .engineer
    }
    
    /// Check if user is viewer (read-only)
    public var isViewer: Bool {
        return role == .viewer
    }
    
    /// Check if user is member of a team
    public func isMemberOf(team teamID: UUID) -> Bool {
        return teamIDs.contains(teamID)
    }
}

// MARK: - Convenience Constructors

extension BlazeUserContext {
    /// Create admin context (bypasses RLS)
    public static func admin(userID: UUID = UUID(), teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .admin, teamIDs: teamIDs)
    }
    
    /// Create engineer context
    public static func engineer(userID: UUID, teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .engineer, teamIDs: teamIDs)
    }
    
    /// Create viewer context (read-only)
    public static func viewer(userID: UUID, teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .viewer, teamIDs: teamIDs)
    }
}

