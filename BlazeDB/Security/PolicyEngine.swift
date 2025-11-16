//
//  PolicyEngine.swift
//  BlazeDB
//
//  Row-Level Security: Policy evaluation engine
//  Created by Michael Danylchuk on 11/12/25.
//

import Foundation

/// Engine that evaluates security policies
public final class PolicyEngine {
    private var policies: [SecurityPolicy] = []
    private let lock = NSLock()
    private var enabled: Bool = false
    
    public init() {}
    
    // MARK: - Policy Management
    
    /// Add a security policy
    public func addPolicy(_ policy: SecurityPolicy) {
        lock.lock()
        defer { lock.unlock() }
        
        policies.append(policy)
        BlazeLogger.info("🔐 Policy added: '\(policy.name)' for \(policy.operation)")
    }
    
    /// Remove a policy by name
    public func removePolicy(named name: String) {
        lock.lock()
        defer { lock.unlock() }
        
        policies.removeAll { $0.name == name }
        BlazeLogger.info("🔐 Policy removed: '\(name)'")
    }
    
    /// Clear all policies
    public func clearPolicies() {
        lock.lock()
        defer { lock.unlock() }
        
        policies.removeAll()
        BlazeLogger.info("🔐 All policies cleared")
    }
    
    /// Get all policies
    public func getPolicies() -> [SecurityPolicy] {
        lock.lock()
        defer { lock.unlock() }
        
        return policies
    }
    
    /// Enable/disable policy enforcement
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        self.enabled = enabled
        BlazeLogger.info("🔐 Policy enforcement \(enabled ? "enabled" : "disabled")")
    }
    
    /// Check if policy enforcement is enabled
    public func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return enabled
    }
    
    // MARK: - Policy Evaluation
    
    /// Check if operation is allowed on a record
    public func isAllowed(
        operation: PolicyOperation,
        context: SecurityContext,
        record: BlazeDataRecord
    ) -> Bool {
        lock.lock()
        let isEnabled = self.enabled
        let currentPolicies = self.policies
        lock.unlock()
        
        // If disabled, allow everything
        guard isEnabled else {
            return true
        }
        
        // Filter policies for this operation
        let applicablePolicies = currentPolicies.filter { policy in
            policy.operation == operation || policy.operation == .all
        }
        
        // If no policies, default behavior based on type
        guard !applicablePolicies.isEmpty else {
            // No policies = allow (permissive default)
            return true
        }
        
        // Evaluate policies
        // PERMISSIVE: Allow if ANY policy grants access
        // RESTRICTIVE: Deny unless ALL policies grant access
        
        var hasPermissive = false
        var hasRestrictive = false
        var permissiveResult = false
        var restrictiveResult = true
        
        for policy in applicablePolicies {
            let result = policy.check(context, record)
            
            switch policy.type {
            case .permissive:
                hasPermissive = true
                permissiveResult = permissiveResult || result  // OR logic
                
            case .restrictive:
                hasRestrictive = true
                restrictiveResult = restrictiveResult && result  // AND logic
            }
        }
        
        // Combine results:
        // - If has permissive policies: allow if ANY granted
        // - If has restrictive policies: allow if ALL granted
        // - If both: allow if EITHER condition met
        
        if hasPermissive && hasRestrictive {
            return permissiveResult || restrictiveResult
        } else if hasPermissive {
            return permissiveResult
        } else if hasRestrictive {
            return restrictiveResult
        } else {
            return true  // No applicable policies = allow
        }
    }
    
    /// Filter records based on policies
    public func filterRecords(
        operation: PolicyOperation,
        context: SecurityContext,
        records: [BlazeDataRecord]
    ) -> [BlazeDataRecord] {
        guard isEnabled() else {
            return records  // Policy enforcement disabled
        }
        
        return records.filter { record in
            isAllowed(operation: operation, context: context, record: record)
        }
    }
    
    /// Check if operation is allowed (for operations without record)
    public func canPerformOperation(
        operation: PolicyOperation,
        context: SecurityContext
    ) -> Bool {
        lock.lock()
        let isEnabled = self.enabled
        let currentPolicies = self.policies
        lock.unlock()
        
        guard isEnabled else {
            return true
        }
        
        // Check role-based policies that don't need record context
        let applicablePolicies = currentPolicies.filter { policy in
            policy.operation == operation || policy.operation == .all
        }
        
        guard !applicablePolicies.isEmpty else {
            return true  // No policies = allow
        }
        
        // For operation-level checks, use empty record
        let dummyRecord = BlazeDataRecord([:])
        
        for policy in applicablePolicies {
            if policy.type == .permissive && policy.check(context, dummyRecord) {
                return true  // At least one permissive policy grants access
            }
        }
        
        return false
    }
}

