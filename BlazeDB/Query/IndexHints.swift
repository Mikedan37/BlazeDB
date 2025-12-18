//
//  IndexHints.swift
//  BlazeDB
//
//  Index hints for query optimization
//  Optimized with index selection logic
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Index Hint

public struct IndexHint {
    public let indexName: String
    public let fields: [String]
    
    public init(indexName: String, fields: [String]) {
        self.indexName = indexName
        self.fields = fields
    }
}

// MARK: - QueryBuilder Index Hints Extension

extension QueryBuilder {
    
    /// Hint to use a specific index
    @discardableResult
    public func useIndex(_ indexName: String, fields: [String]) -> QueryBuilder {
        if indexHints == nil {
            indexHints = []
        }
        indexHints?.append(IndexHint(indexName: indexName, fields: fields))
        BlazeLogger.debug("Query: USE INDEX '\(indexName)' on fields \(fields.joined(separator: ", "))")
        return self
    }
    
    /// Hint to use a specific index by field name
    @discardableResult
    public func useIndex(on field: String) -> QueryBuilder {
        return useIndex("idx_\(field)", fields: [field])
    }
    
    /// Force index usage (ignore automatic selection)
    @discardableResult
    public func forceIndex(_ indexName: String, fields: [String]) -> QueryBuilder {
        if indexHints == nil {
            indexHints = []
        }
        indexHints?.append(IndexHint(indexName: indexName, fields: fields))
        forceIndexSelection = true
        BlazeLogger.debug("Query: FORCE INDEX '\(indexName)' on fields \(fields.joined(separator: ", "))")
        return self
    }
    
    /// Internal: Get index hints
    internal func getIndexHints() -> [IndexHint] {
        return indexHints ?? []
    }
    
    /// Internal: Check if index selection is forced
    internal var shouldForceIndexSelection: Bool {
        return forceIndexSelection
    }
}

// MARK: - QueryBuilder Index Hints Storage

extension QueryBuilder {
    internal var indexHints: [IndexHint]? {
        get {
            #if canImport(ObjectiveC)
            return objc_getAssociatedObject(self, &AssociatedKeys.indexHints) as? [IndexHint]
            #else
            return AssociatedObjects.getValue(self, key: &AssociatedKeys.indexHints)
            #endif
        }
        set {
            #if canImport(ObjectiveC)
            objc_setAssociatedObject(self, &AssociatedKeys.indexHints, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            #else
            AssociatedObjects.setValue(self, key: &AssociatedKeys.indexHints, value: newValue)
            #endif
        }
    }
    
    internal var forceIndexSelection: Bool {
        get {
            #if canImport(ObjectiveC)
            return (objc_getAssociatedObject(self, &AssociatedKeys.forceIndexSelection) as? Bool) ?? false
            #else
            return AssociatedObjects.getValue(self, key: &AssociatedKeys.forceIndexSelection) ?? false
            #endif
        }
        set {
            #if canImport(ObjectiveC)
            objc_setAssociatedObject(self, &AssociatedKeys.forceIndexSelection, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            #else
            AssociatedObjects.setValue(self, key: &AssociatedKeys.forceIndexSelection, value: newValue)
            #endif
        }
    }
}

private struct AssociatedKeys {
    nonisolated(unsafe) static var indexHints: UInt8 = 0
    nonisolated(unsafe) static var forceIndexSelection: UInt8 = 1
}

