//
//  SecurityContext.swift
//  BlazeDB
//
//  Row-Level Security: User context for access control
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Represents the current user's security context (who is making the request)
public struct SecurityContext: Codable, Equatable {
    /// Unique user identifier
    public let userID: UUID
    
    /// IDs of teams/organizations the user belongs to
    public let teamIDs: [UUID]
    
    /// User's roles (e.g., "admin", "team_lead", "member", "viewer")
    public let roles: Set<String>
    
    /// Custom claims for application-specific logic
    public let customClaims: [String: String]
    
    /// Initialize a security context
    public init(
        userID: UUID,
        teamIDs: [UUID] = [],
        roles: Set<String> = [],
        customClaims: [String: String] = [:]
    ) {
        self.userID = userID
        self.teamIDs = teamIDs
        self.roles = roles
        self.customClaims = customClaims
    }
    
    /// Check if user has a specific role
    public func hasRole(_ role: String) -> Bool {
        return roles.contains(role)
    }
    
    /// Check if user is a member of a specific team
    public func isMemberOf(team teamID: UUID) -> Bool {
        return teamIDs.contains(teamID)
    }
    
    /// Check if user has a specific custom claim with a specific value
    public func hasClaim(_ key: String, value: String) -> Bool {
        return customClaims[key] == value
    }
    
    /// Special admin context that bypasses all policies (use with caution!)
    public static var admin: SecurityContext {
        return SecurityContext(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            roles: ["admin", "superuser"]
        )
    }
    
    /// Anonymous/unauthenticated context
    public static var anonymous: SecurityContext {
        return SecurityContext(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            roles: ["anonymous"]
        )
    }
}

extension SecurityContext: CustomStringConvertible {
    public var description: String {
        return """
        SecurityContext(
          userID: \(userID),
          teams: \(teamIDs.count),
          roles: \(roles.sorted().joined(separator: ", ")),
          claims: \(customClaims.count)
        )
        """
    }
}

