//
//  SecurityPolicy.swift
//  BlazeDB
//
//  Row-Level Security: Policy definitions
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Type of operation the policy applies to
public enum PolicyOperation: String, Codable {
    case select  // Read/fetch operations
    case insert  // Insert operations
    case update  // Update operations
    case delete  // Delete operations
    case all     // All operations
}

/// Type of policy check
public enum PolicyType: String, Codable {
    case permissive  // Allow by default, policies can grant
    case restrictive  // Deny by default, policies can grant
}

/// A security policy that controls access to records
public struct SecurityPolicy {
    /// Unique policy name
    public let name: String
    
    /// Operation this policy applies to
    public let operation: PolicyOperation
    
    /// Type of policy (permissive or restrictive)
    public let type: PolicyType
    
    /// Check function: (context, record) -> Bool
    /// Returns true if access should be granted
    public let check: (SecurityContext, BlazeDataRecord) -> Bool
    
    /// Optional description for debugging
    public let description: String?
    
    public init(
        name: String,
        operation: PolicyOperation = .all,
        type: PolicyType = .restrictive,
        description: String? = nil,
        check: @escaping (SecurityContext, BlazeDataRecord) -> Bool
    ) {
        self.name = name
        self.operation = operation
        self.type = type
        self.description = description
        self.check = check
    }
}

// MARK: - Common Policy Builders

extension SecurityPolicy {
    
    /// Policy: User can only access their own records
    public static func userOwnsRecord(userIDField: String = "userId") -> SecurityPolicy {
        return SecurityPolicy(
            name: "user_owns_record",
            operation: .all,
            type: .restrictive,
            description: "User can only access their own records"
        ) { context, record in
            guard let recordUserID = record.storage[userIDField]?.uuidValue else {
                return false  // No userId field = deny
            }
            return recordUserID == context.userID
        }
    }
    
    /// Policy: User can access records in their teams
    public static func userInTeam(teamIDField: String = "teamId") -> SecurityPolicy {
        return SecurityPolicy(
            name: "user_in_team",
            operation: .all,
            type: .restrictive,
            description: "User can access records from their teams"
        ) { context, record in
            guard let recordTeamID = record.storage[teamIDField]?.uuidValue else {
                return false
            }
            return context.teamIDs.contains(recordTeamID)
        }
    }
    
    /// Policy: Admins can access everything
    public static func adminFullAccess(adminRole: String = "admin") -> SecurityPolicy {
        return SecurityPolicy(
            name: "admin_full_access",
            operation: .all,
            type: .permissive,
            description: "Admins have full access"
        ) { context, _ in
            return context.hasRole(adminRole)
        }
    }
    
    /// Policy: Read-only for viewers
    public static func viewerReadOnly(viewerRole: String = "viewer") -> SecurityPolicy {
        return SecurityPolicy(
            name: "viewer_read_only",
            operation: .select,
            type: .permissive,
            description: "Viewers can read but not modify"
        ) { context, _ in
            return context.hasRole(viewerRole)
        }
    }
    
    /// Policy: Public read access (anyone can read)
    public static var publicRead: SecurityPolicy {
        return SecurityPolicy(
            name: "public_read",
            operation: .select,
            type: .permissive,
            description: "Anyone can read"
        ) { _, _ in
            return true
        }
    }
    
    /// Policy: Authenticated users only
    public static var authenticatedOnly: SecurityPolicy {
        return SecurityPolicy(
            name: "authenticated_only",
            operation: .all,
            type: .restrictive,
            description: "Only authenticated users"
        ) { context, _ in
            return !context.hasRole("anonymous")
        }
    }
}

