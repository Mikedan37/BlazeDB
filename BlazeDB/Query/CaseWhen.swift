//
//  CaseWhen.swift
//  BlazeDB
//
//  CASE WHEN statement support for conditional expressions
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Case When Expression

public enum CaseWhenCondition {
    case equals(field: String, value: BlazeDocumentField)
    case greaterThan(field: String, value: BlazeDocumentField)
    case lessThan(field: String, value: BlazeDocumentField)
    case contains(field: String, value: String)
    case custom(predicate: (BlazeDataRecord) -> Bool)
}

public struct CaseWhenClause {
    public let condition: CaseWhenCondition
    public let thenValue: BlazeDocumentField
    
    public init(condition: CaseWhenCondition, thenValue: BlazeDocumentField) {
        self.condition = condition
        self.thenValue = thenValue
    }
}

public struct CaseWhenExpression {
    public let clauses: [CaseWhenClause]
    public let elseValue: BlazeDocumentField?
    
    public init(clauses: [CaseWhenClause], elseValue: BlazeDocumentField? = nil) {
        self.clauses = clauses
        self.elseValue = elseValue
    }
    
    /// Evaluate CASE WHEN for a record
    public func evaluate(for record: BlazeDataRecord) -> BlazeDocumentField {
        for clause in clauses {
            if evaluateCondition(clause.condition, for: record) {
                return clause.thenValue
            }
        }
        return elseValue ?? .data(Data())  // NULL equivalent
    }
    
    private func evaluateCondition(_ condition: CaseWhenCondition, for record: BlazeDataRecord) -> Bool {
        switch condition {
        case .equals(let field, let value):
            return record.storage[field] == value
            
        case .greaterThan(let field, let value):
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, value, isGreaterThan: true)
            
        case .lessThan(let field, let value):
            guard let fieldValue = record.storage[field] else { return false }
            return compareFields(fieldValue, value, isLessThan: true)
            
        case .contains(let field, let value):
            guard let fieldValue = record.storage[field]?.stringValue else { return false }
            return fieldValue.contains(value)
            
        case .custom(let predicate):
            return predicate(record)
        }
    }
    
    private func compareFields(_ f1: BlazeDocumentField, _ f2: BlazeDocumentField, isGreaterThan: Bool) -> Bool {
        switch (f1, f2) {
        case (.int(let v1), .int(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.double(let v1), .double(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.string(let v1), .string(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        case (.date(let v1), .date(let v2)):
            return isGreaterThan ? v1 > v2 : v1 < v2
        default:
            return false
        }
    }
    
    private func compareFields(_ f1: BlazeDocumentField, _ f2: BlazeDocumentField, isLessThan: Bool) -> Bool {
        return compareFields(f1, f2, isGreaterThan: !isLessThan)
    }
}

// MARK: - QueryBuilder Case When Extension

extension QueryBuilder {
    
    /// Add a computed field using CASE WHEN
    @discardableResult
    public func selectCaseWhen(_ expression: CaseWhenExpression, as alias: String) -> QueryBuilder {
        // Store for post-processing
        if caseWhenExpressions == nil {
            caseWhenExpressions = [:]
        }
        caseWhenExpressions?[alias] = expression
        return self
    }
    
    /// Convenience: CASE WHEN ... THEN ... ELSE
    @discardableResult
    public func selectCaseWhen(
        _ clauses: [CaseWhenClause],
        else elseValue: BlazeDocumentField? = nil,
        as alias: String
    ) -> QueryBuilder {
        let expression = CaseWhenExpression(clauses: clauses, elseValue: elseValue)
        return selectCaseWhen(expression, as: alias)
    }
}

// MARK: - QueryBuilder Case When Storage

extension QueryBuilder {
    internal var caseWhenExpressions: [String: CaseWhenExpression]? {
        get {
            #if canImport(ObjectiveC)
            return objc_getAssociatedObject(self, &AssociatedKeys.caseWhen) as? [String: CaseWhenExpression]
            #else
            return AssociatedObjects.getValue(self, key: &AssociatedKeys.caseWhen)
            #endif
        }
        set {
            #if canImport(ObjectiveC)
            objc_setAssociatedObject(self, &AssociatedKeys.caseWhen, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            #else
            AssociatedObjects.setValue(self, key: &AssociatedKeys.caseWhen, value: newValue)
            #endif
        }
    }
}

private struct AssociatedKeys {
    nonisolated(unsafe) static var caseWhen: UInt8 = 0
}

