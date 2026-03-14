//
//  BlazeDBClient+RLS.swift
//  BlazeDB
//
//  Row-Level Security integration with BlazeDBClient
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

// MARK: - RLS Manager

/// RLS manager for a BlazeDBClient
internal final class RLS {
    internal let policyEngine: PolicyEngine
    private let accessManager: AccessManager
    private weak var client: BlazeDBClient?
    private var currentContext: SecurityContext?
    private let lock = NSLock()
    
    init(client: BlazeDBClient) {
        self.client = client
        self.policyEngine = PolicyEngine()
        self.accessManager = AccessManager()
    }
    
    // MARK: - Enable/Disable
    
    /// Enable RLS enforcement
    internal func enable() {
        policyEngine.setEnabled(true)
        BlazeLogger.info("🔐 RLS enabled for '\(client?.name ?? "unknown")'")
    }
    
    /// Disable RLS enforcement
    internal func disable() {
        policyEngine.setEnabled(false)
        BlazeLogger.info("🔐 RLS disabled for '\(client?.name ?? "unknown")'")
    }
    
    /// Check if RLS is enabled
    internal func isEnabled() -> Bool {
        return policyEngine.isEnabled()
    }
    
    // MARK: - Context Management
    
    /// Set security context for current operations
    internal func setContext(_ context: SecurityContext) {
        lock.lock()
        defer { lock.unlock() }
        
        currentContext = context
        BlazeLogger.debug("🔐 Security context set: \(context.userID)")
    }
    
    /// Clear security context
    internal func clearContext() {
        lock.lock()
        defer { lock.unlock() }
        
        currentContext = nil
        BlazeLogger.debug("🔐 Security context cleared")
    }
    
    /// Get current security context
    internal func getContext() -> SecurityContext? {
        lock.lock()
        defer { lock.unlock() }
        
        return currentContext
    }
    
    // MARK: - Policy Management
    
    /// Add a security policy
    internal func addPolicy(_ policy: SecurityPolicy) {
        policyEngine.addPolicy(policy)
    }
    
    /// Remove a policy
    internal func removePolicy(named name: String) {
        policyEngine.removePolicy(named: name)
    }
    
    /// Clear all policies
    internal func clearPolicies() {
        policyEngine.clearPolicies()
    }
    
    /// Get all policies
    internal func getPolicies() -> [SecurityPolicy] {
        return policyEngine.getPolicies()
    }
    
    // MARK: - User Management
    
    /// Create a new user
    @discardableResult
    internal func createUser(_ user: User) -> UUID {
        return accessManager.createUser(user)
    }
    
    /// Get user
    internal func getUser(id: UUID) -> User? {
        return accessManager.getUser(id: id)
    }
    
    /// Update user
    internal func updateUser(_ user: User) {
        accessManager.updateUser(user)
    }
    
    /// Delete user
    internal func deleteUser(id: UUID) {
        accessManager.deleteUser(id: id)
    }
    
    /// List all users
    internal func listUsers() -> [User] {
        return accessManager.listUsers()
    }
    
    // MARK: - Team Management
    
    /// Create a new team
    @discardableResult
    internal func createTeam(_ team: Team) -> UUID {
        return accessManager.createTeam(team)
    }
    
    /// Get team
    internal func getTeam(id: UUID) -> Team? {
        return accessManager.getTeam(id: id)
    }
    
    /// Update team
    internal func updateTeam(_ team: Team) {
        accessManager.updateTeam(team)
    }
    
    /// Delete team
    internal func deleteTeam(id: UUID) {
        accessManager.deleteTeam(id: id)
    }
    
    /// List all teams
    internal func listTeams() -> [Team] {
        return accessManager.listTeams()
    }
    
    // MARK: - Team Membership
    
    /// Add user to team
    internal func addUserToTeam(userID: UUID, teamID: UUID, asAdmin: Bool = false) {
        accessManager.addUserToTeam(userID: userID, teamID: teamID, asAdmin: asAdmin)
    }
    
    /// Remove user from team
    internal func removeUserFromTeam(userID: UUID, teamID: UUID) {
        accessManager.removeUserFromTeam(userID: userID, teamID: teamID)
    }
    
    // MARK: - Role Management
    
    /// Add role to user
    internal func addRole(_ role: String, to userID: UUID) {
        accessManager.addRole(role, to: userID)
    }
    
    /// Remove role from user
    internal func removeRole(_ role: String, from userID: UUID) {
        accessManager.removeRole(role, from: userID)
    }
    
    // MARK: - Internal Policy Evaluation
    
    /// Check if operation is allowed on record
    internal func isAllowed(operation: PolicyOperation, record: BlazeDataRecord) -> Bool {
        guard let context = getContext() else {
            // No context = allow (RLS optional)
            return true
        }
        
        return policyEngine.isAllowed(operation: operation, context: context, record: record)
    }
    
    /// Filter records based on policies
    internal func filterRecords(operation: PolicyOperation, records: [BlazeDataRecord]) -> [BlazeDataRecord] {
        guard let context = getContext() else {
            return records  // No context = return all
        }
        
        return policyEngine.filterRecords(operation: operation, context: context, records: records)
    }
}

// MARK: - BlazeDBClient RLS Extension

extension BlazeDBClient {
    
    nonisolated(unsafe) private static var rlsManagers: [String: RLS] = [:]
    private static let rlsLock = NSLock()
    
    /// RLS manager for this database
    internal var rls: RLS {
        let key = "\(name)-\(fileURL.path)"
        
        Self.rlsLock.lock()
        defer { Self.rlsLock.unlock() }
        
        if let existing = Self.rlsManagers[key] {
            return existing
        }
        
        let manager = RLS(client: self)
        Self.rlsManagers[key] = manager
        return manager
    }
    
    // MARK: - RLS-Aware Operations
    
    /// Fetch with RLS enforcement
    internal func fetchWithRLS(id: UUID) throws -> BlazeDataRecord? {
        guard let record = try fetch(id: id) else {
            return nil
        }
        
        // Check if user can read this record
        if rls.isAllowed(operation: .select, record: record) {
            return record
        } else {
            BlazeLogger.debug("🔐 RLS denied SELECT for record \(id)")
            return nil  // Policy denied access
        }
    }
    
    /// Fetch all with RLS filtering
    internal func fetchAllWithRLS() throws -> [BlazeDataRecord] {
        let allRecords = try fetchAll()
        return rls.filterRecords(operation: .select, records: allRecords)
    }
}

