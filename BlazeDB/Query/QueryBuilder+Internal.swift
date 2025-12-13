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
            return objc_getAssociatedObject(self, &QueryBuilder.vectorQueryKey) as? (String, VectorEmbedding, Int, Float)
        }
        set {
            objc_setAssociatedObject(self, &QueryBuilder.vectorQueryKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
    
    private static var vectorQueryKey: UInt8 = 0
}

