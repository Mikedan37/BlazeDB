//
//  BlazeDBClient+Vector.swift
//  BlazeDB
//
//  Vector index convenience methods for BlazeDBClient
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

extension BlazeDBClient {
    
    /// Enable vector index for a field
    /// - Parameter fieldName: Field name containing vector embeddings
    public func enableVectorIndex(fieldName: String) throws {
        try collection.enableVectorIndex(fieldName: fieldName)
    }
    
    /// Disable vector index
    public func disableVectorIndex() throws {
        try collection.disableVectorIndex()
    }
    
    /// Rebuild vector index (useful after bulk updates)
    public func rebuildVectorIndex() throws {
        try collection.rebuildVectorIndex()
    }
    
    /// Get vector index statistics
    public func getVectorIndexStats() -> VectorIndexStats? {
        return collection.getVectorIndexStats()
    }
}
#endif // !BLAZEDB_LINUX_CORE
