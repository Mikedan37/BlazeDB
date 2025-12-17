//
//  CheckConstraints.swift
//  BlazeDB
//
//  Check constraints for data validation
//  Optimized with compiled predicates and caching
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Check Constraint

public struct CheckConstraint {
    public let name: String
    public let field: String?
    public let predicate: (BlazeDataRecord) -> Bool
    
    public init(name: String, field: String? = nil, predicate: @escaping (BlazeDataRecord) -> Bool) {
        self.name = name
        self.field = field
        self.predicate = predicate
    }
}

// MARK: - Check Constraint Manager

public class CheckConstraintManager {
    private var constraints: [CheckConstraint] = []
    private let lock = NSLock()
    
    public init() {}
    
    /// Add a check constraint
    public func addConstraint(_ constraint: CheckConstraint) {
        lock.lock()
        defer { lock.unlock() }
        constraints.append(constraint)
        BlazeLogger.info("Added check constraint '\(constraint.name)' for field '\(constraint.field ?? "all")'")
    }
    
    /// Remove a constraint by name
    public func removeConstraint(name: String) {
        lock.lock()
        defer { lock.unlock() }
        constraints.removeAll { $0.name == name }
        BlazeLogger.info("Removed check constraint '\(name)'")
    }
    
    /// Get constraints for a field
    public func getConstraints(for field: String?) -> [CheckConstraint] {
        lock.lock()
        defer { lock.unlock() }
        if let field = field {
            return constraints.filter { $0.field == field || $0.field == nil }
        }
        return constraints.filter { $0.field == nil }
    }
    
    /// Validate record against all constraints
    public func validate(_ record: BlazeDataRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        
        // Check all constraints that apply:
        // 1. Constraints with field == nil (apply to all records)
        // 2. Constraints that match any field in the record
        let relevantConstraints = constraints.filter { constraint in
            if constraint.field == nil {
                return true  // Applies to all records
            }
            // Check if the constraint's field exists in the record
            guard let field = constraint.field else {
                return false
            }
            return record.storage[field] != nil
        }
        
        for constraint in relevantConstraints {
            if !constraint.predicate(record) {
                throw BlazeDBError.checkConstraintViolation(
                    constraint: constraint.name,
                    field: constraint.field ?? "record",
                    message: "Check constraint '\(constraint.name)' failed"
                )
            }
        }
    }
    
    /// Validate field against constraints
    public func validateField(_ field: String, value: BlazeDocumentField, in record: BlazeDataRecord) throws {
        let fieldConstraints = getConstraints(for: field)
        
        for constraint in fieldConstraints {
            if !constraint.predicate(record) {
                throw BlazeDBError.checkConstraintViolation(
                    constraint: constraint.name,
                    field: field,
                    message: "Check constraint '\(constraint.name)' failed for field '\(field)'"
                )
            }
        }
    }
}

// MARK: - BlazeDBClient Check Constraints Extension

extension BlazeDBClient {
    nonisolated(unsafe) private static var checkConstraintManagerKey: UInt8 = 0
    
    private var checkConstraintManager: CheckConstraintManager {
        #if canImport(ObjectiveC)
        if let manager = objc_getAssociatedObject(self, &Self.checkConstraintManagerKey) as? CheckConstraintManager {
            return manager
        }
        let manager = CheckConstraintManager()
        objc_setAssociatedObject(self, &Self.checkConstraintManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
        #else
        if let manager: CheckConstraintManager = AssociatedObjects.get(self, key: &Self.checkConstraintManagerKey) {
            return manager
        }
        let manager = CheckConstraintManager()
        AssociatedObjects.set(self, key: &Self.checkConstraintManagerKey, value: manager)
        return manager
        #endif
    }
    
    /// Add a check constraint
    public func addCheckConstraint(_ constraint: CheckConstraint) {
        checkConstraintManager.addConstraint(constraint)
    }
    
    /// Remove a check constraint
    public func removeCheckConstraint(name: String) {
        checkConstraintManager.removeConstraint(name: name)
    }
    
    /// Validate record against check constraints
    internal func validateCheckConstraints(in record: BlazeDataRecord) throws {
        try checkConstraintManager.validate(record)
    }
}

// MARK: - BlazeDBError Check Constraint Extension

extension BlazeDBError {
    public static func checkConstraintViolation(constraint: String, field: String, message: String) -> BlazeDBError {
        return .transactionFailed("Check constraint violation on '\(field)' (constraint '\(constraint)'): \(message)")
    }
}

