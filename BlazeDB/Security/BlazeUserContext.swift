//
//  BlazeUserContext.swift
//  BlazeDB
//
//  Convenience wrapper for user context with role-based access
//  Integrates with existing SecurityContext system
import Foundation

/// User role for simplified role-based access control
internal enum UserRole: String, Sendable, Codable {
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
internal struct BlazeUserContext: Sendable {
    /// Unique user identifier
    internal let userID: UUID
    
    /// User's role (admin/engineer/viewer)
    internal let role: UserRole
    
    /// IDs of teams/organizations the user belongs to
    internal let teamIDs: [UUID]
    
    /// Initialize a user context
    internal init(
        userID: UUID,
        role: UserRole,
        teamIDs: [UUID] = []
    ) {
        self.userID = userID
        self.role = role
        self.teamIDs = teamIDs
    }
    
    /// Convert to SecurityContext (for existing RLS system)
    internal func toSecurityContext(customClaims: [String: String] = [:]) -> SecurityContext {
        return SecurityContext(
            userID: userID,
            teamIDs: teamIDs,
            roles: [role.securityRole],
            customClaims: customClaims
        )
    }
    
    /// Check if user is admin (bypasses RLS)
    internal var isAdmin: Bool {
        return role == .admin
    }
    
    /// Check if user is engineer
    internal var isEngineer: Bool {
        return role == .engineer
    }
    
    /// Check if user is viewer (read-only)
    internal var isViewer: Bool {
        return role == .viewer
    }
    
    /// Check if user is member of a team
    internal func isMemberOf(team teamID: UUID) -> Bool {
        return teamIDs.contains(teamID)
    }
}

// MARK: - Convenience Constructors

extension BlazeUserContext {
    /// Create admin context (bypasses RLS)
    internal static func admin(userID: UUID = UUID(), teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .admin, teamIDs: teamIDs)
    }
    
    /// Create engineer context
    internal static func engineer(userID: UUID, teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .engineer, teamIDs: teamIDs)
    }
    
    /// Create viewer context (read-only)
    internal static func viewer(userID: UUID, teamIDs: [UUID] = []) -> BlazeUserContext {
        return BlazeUserContext(userID: userID, role: .viewer, teamIDs: teamIDs)
    }
}

