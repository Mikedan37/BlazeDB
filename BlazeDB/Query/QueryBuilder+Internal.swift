//
//  QueryBuilder+Internal.swift
//  BlazeDB
//
//  Internal state for query planner
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension QueryBuilder {
    
    /// Internal: Vector query state (for planner)
    internal var vectorQueryState: (field: String, embedding: VectorEmbedding, limit: Int, threshold: Float)? {
        get {
            #if canImport(ObjectiveC)
            return objc_getAssociatedObject(self, &QueryBuilder.vectorQueryKey) as? (String, VectorEmbedding, Int, Float)
            #else
            return AssociatedObjects.getValue(self, key: &QueryBuilder.vectorQueryKey)
            #endif
        }
        set {
            #if canImport(ObjectiveC)
            objc_setAssociatedObject(self, &QueryBuilder.vectorQueryKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            #else
            AssociatedObjects.setValue(self, key: &QueryBuilder.vectorQueryKey, value: newValue)
            #endif
        }
    }
    
    /// Internal: Check if query has vector search
    internal var hasVectorQuery: Bool {
        return vectorQueryState != nil
    }
    
    /// Internal: Set vector query state
    internal func setVectorQuery(field: String, embedding: VectorEmbedding, limit: Int, threshold: Float) {
        vectorQueryState = (field, embedding, limit, threshold)
    }
    
    nonisolated(unsafe) private static var vectorQueryKey: UInt8 = 0
}

