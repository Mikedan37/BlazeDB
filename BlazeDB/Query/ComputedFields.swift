//
//  ComputedFields.swift
//  BlazeDB
//
//  Computed field expressions for field-to-field calculations
//  Supports: +, -, *, /, %, and functions like abs(), round(), etc.
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Expression Types

/// Mathematical expression for computed fields
public indirect enum MathExpression {
    /// Field reference
    case field(String)
    
    /// Literal value
    case literal(BlazeDocumentField)
    
    /// Addition: left + right
    case add(MathExpression, MathExpression)
    
    /// Subtraction: left - right
    case subtract(MathExpression, MathExpression)
    
    /// Multiplication: left * right
    case multiply(MathExpression, MathExpression)
    
    /// Division: left / right
    case divide(MathExpression, MathExpression)
    
    /// Modulo: left % right
    case modulo(MathExpression, MathExpression)
    
    /// Absolute value: abs(expr)
    case abs(MathExpression)
    
    /// Round: round(expr)
    case round(MathExpression)
    
    /// Floor: floor(expr)
    case floor(MathExpression)
    
    /// Ceiling: ceil(expr)
    case ceil(MathExpression)
    
    /// Square root: sqrt(expr)
    case sqrt(MathExpression)
    
    /// Power: pow(base, exponent)
    case power(MathExpression, MathExpression)
    
    /// Maximum: max(expr1, expr2)
    case max(MathExpression, MathExpression)
    
    /// Minimum: min(expr1, expr2)
    case min(MathExpression, MathExpression)
}

// MARK: - Expression Evaluation

extension MathExpression {
    /// Evaluate expression for a record
    func evaluate(for record: BlazeDataRecord) -> BlazeDocumentField? {
        switch self {
        case .field(let fieldName):
            return record.storage[fieldName]
            
        case .literal(let value):
            return value
            
        case .add(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return addFields(leftVal, rightVal)
            
        case .subtract(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return subtractFields(leftVal, rightVal)
            
        case .multiply(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return multiplyFields(leftVal, rightVal)
            
        case .divide(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return divideFields(leftVal, rightVal)
            
        case .modulo(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return moduloFields(leftVal, rightVal)
            
        case .abs(let expr):
            guard let value = expr.evaluate(for: record) else { return nil }
            return absField(value)
            
        case .round(let expr):
            guard let value = expr.evaluate(for: record) else { return nil }
            return roundField(value)
            
        case .floor(let expr):
            guard let value = expr.evaluate(for: record) else { return nil }
            return floorField(value)
            
        case .ceil(let expr):
            guard let value = expr.evaluate(for: record) else { return nil }
            return ceilField(value)
            
        case .sqrt(let expr):
            guard let value = expr.evaluate(for: record) else { return nil }
            return sqrtField(value)
            
        case .power(let base, let exponent):
            guard let baseVal = base.evaluate(for: record),
                  let expVal = exponent.evaluate(for: record) else { return nil }
            return powerFields(baseVal, expVal)
            
        case .max(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return maxFields(leftVal, rightVal)
            
        case .min(let left, let right):
            guard let leftVal = left.evaluate(for: record),
                  let rightVal = right.evaluate(for: record) else { return nil }
            return minFields(leftVal, rightVal)
        }
    }
}

// MARK: - Field Arithmetic Operations

private func addFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return .int(l + r)
    case (.int(let l), .double(let r)):
        return .double(Double(l) + r)
    case (.double(let l), .int(let r)):
        return .double(l + Double(r))
    case (.double(let l), .double(let r)):
        return .double(l + r)
    default:
        return .double(0)
    }
}

private func subtractFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return .int(l - r)
    case (.int(let l), .double(let r)):
        return .double(Double(l) - r)
    case (.double(let l), .int(let r)):
        return .double(l - Double(r))
    case (.double(let l), .double(let r)):
        return .double(l - r)
    default:
        return .double(0)
    }
}

private func multiplyFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return .int(l * r)
    case (.int(let l), .double(let r)):
        return .double(Double(l) * r)
    case (.double(let l), .int(let r)):
        return .double(l * Double(r))
    case (.double(let l), .double(let r)):
        return .double(l * r)
    default:
        return .double(0)
    }
}

private func divideFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        guard r != 0 else { return .double(0) }
        return .double(Double(l) / Double(r))
    case (.int(let l), .double(let r)):
        guard r != 0 else { return .double(0) }
        return .double(Double(l) / r)
    case (.double(let l), .int(let r)):
        guard r != 0 else { return .double(0) }
        return .double(l / Double(r))
    case (.double(let l), .double(let r)):
        guard r != 0 else { return .double(0) }
        return .double(l / r)
    default:
        return .double(0)
    }
}

private func moduloFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        guard r != 0 else { return .int(0) }
        return .int(l % r)
    case (.int(let l), .double(let r)):
        guard r != 0 else { return .double(0) }
        return .double(Double(l).truncatingRemainder(dividingBy: r))
    case (.double(let l), .int(let r)):
        guard r != 0 else { return .double(0) }
        return .double(l.truncatingRemainder(dividingBy: Double(r)))
    case (.double(let l), .double(let r)):
        guard r != 0 else { return .double(0) }
        return .double(l.truncatingRemainder(dividingBy: r))
    default:
        return .int(0)
    }
}

// MARK: - Math Functions

private func absField(_ field: BlazeDocumentField) -> BlazeDocumentField {
    switch field {
    case .int(let v):
        return .int(abs(v))
    case .double(let v):
        return .double(abs(v))
    default:
        return field
    }
}

private func roundField(_ field: BlazeDocumentField) -> BlazeDocumentField {
    switch field {
    case .int(let v):
        return .int(v)
    case .double(let v):
        return .double(round(v))
    default:
        return field
    }
}

private func floorField(_ field: BlazeDocumentField) -> BlazeDocumentField {
    switch field {
    case .int(let v):
        return .int(v)
    case .double(let v):
        return .double(floor(v))
    default:
        return field
    }
}

private func ceilField(_ field: BlazeDocumentField) -> BlazeDocumentField {
    switch field {
    case .int(let v):
        return .int(v)
    case .double(let v):
        return .double(ceil(v))
    default:
        return field
    }
}

private func sqrtField(_ field: BlazeDocumentField) -> BlazeDocumentField {
    switch field {
    case .int(let v):
        guard v >= 0 else { return .double(0) }
        return .double(sqrt(Double(v)))
    case .double(let v):
        guard v >= 0 else { return .double(0) }
        return .double(sqrt(v))
    default:
        return .double(0)
    }
}

private func powerFields(_ base: BlazeDocumentField, _ exponent: BlazeDocumentField) -> BlazeDocumentField {
    let baseVal: Double
    let expVal: Double
    
    switch base {
    case .int(let v): baseVal = Double(v)
    case .double(let v): baseVal = v
    default: return .double(0)
    }
    
    switch exponent {
    case .int(let v): expVal = Double(v)
    case .double(let v): expVal = v
    default: return .double(0)
    }
    
    return .double(pow(baseVal, expVal))
}

private func maxFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return .int(max(l, r))
    case (.int(let l), .double(let r)):
        return .double(max(Double(l), r))
    case (.double(let l), .int(let r)):
        return .double(max(l, Double(r)))
    case (.double(let l), .double(let r)):
        return .double(max(l, r))
    default:
        return lhs
    }
}

private func minFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> BlazeDocumentField {
    switch (lhs, rhs) {
    case (.int(let l), .int(let r)):
        return .int(min(l, r))
    case (.int(let l), .double(let r)):
        return .double(min(Double(l), r))
    case (.double(let l), .int(let r)):
        return .double(min(l, Double(r)))
    case (.double(let l), .double(let r)):
        return .double(min(l, r))
    default:
        return lhs
    }
}

// MARK: - QueryBuilder Extension

extension QueryBuilder {
    /// Storage for computed fields (ordered array to preserve evaluation order)
    internal var computedFields: [(String, MathExpression)]? {
        get {
            #if canImport(ObjectiveC)
            return objc_getAssociatedObject(self, &ComputedFieldsKeys.computedFields) as? [(String, MathExpression)]
            #else
            return AssociatedObjects.getValue(self, key: &ComputedFieldsKeys.computedFields)
            #endif
        }
        set {
            #if canImport(ObjectiveC)
            objc_setAssociatedObject(self, &ComputedFieldsKeys.computedFields, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            #else
            AssociatedObjects.setValue(self, key: &ComputedFieldsKeys.computedFields, value: newValue)
            #endif
        }
    }
    
    /// Add a computed field to the query
    /// 
    /// Example:
    /// ```swift
    /// let results = try db.query()
    ///     .compute("total", expression: .multiply(.field("price"), .field("quantity")))
    ///     .execute()
    /// ```
    @discardableResult
    public func compute(_ alias: String, expression: MathExpression) -> QueryBuilder {
        BlazeLogger.debug("Query: COMPUTE \(alias) = \(expression)")
        if computedFields == nil {
            computedFields = []
        }
        // Remove existing field with same alias if present (to allow redefinition)
        computedFields?.removeAll { $0.0 == alias }
        computedFields?.append((alias, expression))
        return self
    }
    
    /// Convenience: Multiply two fields
    @discardableResult
    public func compute(_ alias: String, multiply field1: String, by field2: String) -> QueryBuilder {
        return compute(alias, expression: .multiply(.field(field1), .field(field2)))
    }
    
    /// Convenience: Add two fields
    @discardableResult
    public func compute(_ alias: String, add field1: String, to field2: String) -> QueryBuilder {
        return compute(alias, expression: .add(.field(field1), .field(field2)))
    }
    
    /// Convenience: Subtract two fields
    @discardableResult
    public func compute(_ alias: String, subtract field1: String, from field2: String) -> QueryBuilder {
        return compute(alias, expression: .subtract(.field(field2), .field(field1)))
    }
    
    /// Convenience: Divide two fields
    @discardableResult
    public func compute(_ alias: String, divide field1: String, by field2: String) -> QueryBuilder {
        return compute(alias, expression: .divide(.field(field1), .field(field2)))
    }
    
    /// Apply computed fields to a record
    internal func applyComputedFields(to record: BlazeDataRecord) -> BlazeDataRecord {
        guard let computed = computedFields, !computed.isEmpty else {
            return record
        }
        
        // Start with a mutable copy of the original record storage
        var resultStorage = record.storage
        
        // Apply computed fields one by one in insertion order, so later fields can reference earlier computed fields
        // CRITICAL: Use array iteration to preserve order (dictionary iteration order is not guaranteed)
        for (alias, expression) in computed {
            // Create a temporary record with current storage state for evaluation
            // This includes all previously computed fields, allowing dependencies
            let tempRecord = BlazeDataRecord(resultStorage)
            
            // Evaluate expression against the temporary record (which includes previously computed fields)
            if let computedValue = expression.evaluate(for: tempRecord) {
                resultStorage[alias] = computedValue
                BlazeLogger.trace("Computed field '\(alias)' = \(computedValue)")
            } else {
                // Log if evaluation fails
                BlazeLogger.debug("Failed to evaluate computed field '\(alias)' for record. Available fields: \(resultStorage.keys.joined(separator: ", "))")
            }
        }
        
        // Preserve the record ID if it exists in original storage
        if let id = record.storage["id"] {
            resultStorage["id"] = id
        }
        
        return BlazeDataRecord(resultStorage)
    }
}

private struct ComputedFieldsKeys {
    nonisolated(unsafe) static var computedFields: UInt8 = 0
}

