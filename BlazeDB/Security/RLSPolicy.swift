//
//  RLSPolicy.swift
//  BlazeDB
//
//  Protocol-based RLS policy system (optional convenience layer)
//  Wraps existing SecurityPolicy system with type-safe protocol
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Protocol for defining type-safe RLS policies
/// This is an optional convenience layer on top of the existing SecurityPolicy system
/// 
/// Note: Model type is for type-safety, but policies work with BlazeDataRecord
public protocol RLSPolicy: Sendable {
    /// The model type this policy applies to (for type-safety and registration)
    associatedtype Model
    
    /// Generate a filter predicate for the given user context
    /// Returns a filter that determines which records the user can access
    func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool
}

/// Type-erased wrapper for RLSPolicy (for registry)
internal struct AnyRLSPolicy {
    private let _filter: (BlazeUserContext) -> (BlazeDataRecord) -> Bool
    
    init<P: RLSPolicy>(_ policy: P) {
        self._filter = { user in
            return policy.filter(for: user)
        }
    }
    
    func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
        return _filter(user)
    }
}

/// Global RLS policy registry (optional, additive only)
/// If no policies are registered, no filtering occurs
public struct BlazeRLSRegistry {
    nonisolated(unsafe) private static var policies: [String: AnyRLSPolicy] = [:]
    private static let lock = NSLock()
    
    /// Register an RLS policy for a model type
    /// 
    /// Example:
    /// ```swift
    /// struct BugRLSPolicy: RLSPolicy {
    ///     typealias Model = Bug
    ///     
    ///     func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
    ///         if user.isAdmin { return { _ in true } }
    ///         return { record in
    ///             guard let teamID = record.storage["team_id"]?.uuidValue else { return false }
    ///             return user.isMemberOf(team: teamID)
    ///         }
    ///     }
    /// }
    /// 
    /// BlazeRLSRegistry.registerRLS(Bug.self, policy: BugRLSPolicy())
    /// ```
    public static func registerRLS<T, P: RLSPolicy>(
        _ type: T.Type,
        policy: P
    ) where P.Model == T {
        lock.lock()
        defer { lock.unlock() }
        
        let key = String(describing: type)
        policies[key] = AnyRLSPolicy(policy)
        
        BlazeLogger.info("🔐 RLS policy registered for \(key)")
    }
    
    /// Get RLS policy for a model type
    internal static func getPolicy<T>(for type: T.Type) -> AnyRLSPolicy? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = String(describing: type)
        return policies[key]
    }
    
    /// Remove RLS policy for a model type
    public static func unregisterRLS<T>(_ type: T.Type) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = String(describing: type)
        policies.removeValue(forKey: key)
        
        BlazeLogger.info("🔐 RLS policy unregistered for \(key)")
    }
    
    /// Clear all registered policies
    public static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        policies.removeAll()
        BlazeLogger.info("🔐 All RLS policies cleared")
    }
}

// MARK: - Convenience Policy Implementations

/// Policy: Admin sees everything, others see only their team's records
/// Optimized: Uses Set for O(1) team membership checks
public struct TeamBasedRLSPolicy<T>: RLSPolicy {
    public typealias Model = T
    
    private let teamIDField: String
    
    public init(teamIDField: String = "team_id") {
        self.teamIDField = teamIDField
    }
    
    public func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
        // OPTIMIZATION: Admin check once, not per record
        if user.isAdmin {
            return { _ in true }  // Admin bypass
        }
        
        // OPTIMIZATION: Pre-compute teamIDSet for O(1) lookups
        let teamIDSet = Set(user.teamIDs)
        let fieldName = teamIDField  // Capture for closure
        
        return { record in
            // OPTIMIZATION: Single dictionary lookup, then Set.contains (O(1))
            guard let teamID = record.storage[fieldName]?.uuidValue else {
                return false  // No team ID = not accessible
            }
            return teamIDSet.contains(teamID)  // O(1) lookup instead of O(n) array.contains
        }
    }
}

/// Policy: Users see only records they own
/// Optimized: Pre-computes userID for direct comparison
public struct OwnerBasedRLSPolicy<T>: RLSPolicy {
    public typealias Model = T
    
    private let ownerIDField: String
    
    public init(ownerIDField: String = "owner_id") {
        self.ownerIDField = ownerIDField
    }
    
    public func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
        // OPTIMIZATION: Admin check once, not per record
        if user.isAdmin {
            return { _ in true }  // Admin bypass
        }
        
        // OPTIMIZATION: Pre-compute userID and field name for closure
        let userID = user.userID
        let fieldName = ownerIDField
        
        return { record in
            // OPTIMIZATION: Single dictionary lookup, then direct UUID comparison
            guard let ownerID = record.storage[fieldName]?.uuidValue else {
                return false  // No owner = not accessible
            }
            return ownerID == userID  // Direct comparison (no method call overhead)
        }
    }
}

/// Policy: Engineers see team records, viewers see only assigned records
/// Optimized: Pre-computes checks and uses Set for team membership
public struct RoleBasedRLSPolicy<T>: RLSPolicy {
    public typealias Model = T
    
    private let teamIDField: String
    private let assignedToField: String
    
    public init(teamIDField: String = "team_id", assignedToField: String = "assigned_to") {
        self.teamIDField = teamIDField
        self.assignedToField = assignedToField
    }
    
    public func filter(for user: BlazeUserContext) -> (BlazeDataRecord) -> Bool {
        // OPTIMIZATION: Admin check once, not per record
        if user.isAdmin {
            return { _ in true }  // Admin bypass
        }
        
        // OPTIMIZATION: Pre-compute role checks and values once
        let isEngineer = user.isEngineer
        let isViewer = user.isViewer
        let userID = user.userID
        let teamIDSet = Set(user.teamIDs)  // O(1) lookups
        let teamField = teamIDField
        let assignedField = assignedToField
        
        if isEngineer {
            // Engineers see all team records
            return { record in
                // OPTIMIZATION: Single dictionary lookup, then Set.contains (O(1))
                guard let teamID = record.storage[teamField]?.uuidValue else {
                    return false
                }
                return teamIDSet.contains(teamID)  // O(1) instead of O(n) array.contains
            }
        }
        
        if isViewer {
            // Viewers see only assigned records
            return { record in
                // OPTIMIZATION: Single dictionary lookup, then direct UUID comparison
                guard let assignedTo = record.storage[assignedField]?.uuidValue else {
                    return false
                }
                return assignedTo == userID  // Direct comparison
            }
        }
        
        // Unknown role = no access
        return { _ in false }
    }
}

