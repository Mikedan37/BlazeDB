//
//  QueryBuilder+Vector.swift
//  BlazeDB
//
//  Vector similarity search queries
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

extension QueryBuilder {
    
    /// Filter records by vector similarity (semantic search)
    ///
    /// Example:
    /// ```swift
    /// let similar = try db.query()
    ///     .vectorNearest(field: "moodEmbedding", to: anxiousEmbedding, limit: 100)
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - field: Field name containing the vector embedding
    ///   - embedding: Query vector
    ///   - limit: Maximum number of results
    ///   - threshold: Minimum similarity threshold (0.0 to 1.0)
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func vectorNearest(field: String, to embedding: VectorEmbedding, limit: Int = 10, threshold: Float = 0.0) -> QueryBuilder {
        BlazeLogger.debug("Query: VECTOR_NEAREST on field '\(field)', limit: \(limit), threshold: \(threshold)")
        
        // Mark query as having vector search (for planner)
        setVectorQuery(field: field, embedding: embedding, limit: limit, threshold: threshold)
        
        // Use vector index if available (O(log n) instead of O(n))
        if let collection = collection,
           let _ = collection.vectorIndex,
           let indexedField = collection.cachedVectorIndexedField,
           indexedField == field {
            // Fast path: Use vector index
            BlazeLogger.debug("Using vector index for field '\(field)'")
            // Store index reference for execution
            // The actual index lookup happens in execute() via planner
            filters.append { record in
                // Index already filtered, just verify record has the field
                return record.storage[field] != nil
            }
        } else {
            // Fallback: Brute force (O(n))
            BlazeLogger.debug("Vector index not available, using brute force search")
            filters.append { [weak self] record in
                guard let self = self,
                      let fieldValue = record.storage[field],
                      case .data(let data) = fieldValue else {
                    return false
                }
                
                // Decode vector from data
                // In production, would use proper vector encoding
                let vector = try? self.decodeVector(from: data)
                guard let vector = vector else { return false }
                
                // Calculate similarity
                let similarity = self.cosineSimilarity(embedding, vector)
                return similarity >= threshold
            }
        }
        
        // Store vector query info for sorting
        // NOTE: Vector sorting intentionally not implemented.
        // Vector queries return results sorted by similarity; custom sorting requires
        // post-processing or specialized index support not yet implemented.
        
        return self
    }
    
    /// Helper: Decode vector from data
    private func decodeVector(from data: Data) throws -> VectorEmbedding {
        // Simple implementation: assume data is array of floats
        let count = data.count / MemoryLayout<Float>.size
        var vector: VectorEmbedding = []
        vector.reserveCapacity(count)
        
        data.withUnsafeBytes { bytes in
            let floats = bytes.bindMemory(to: Float.self)
            for i in 0..<count {
                vector.append(floats[i])
            }
        }
        
        return vector
    }
    
    /// Helper: Calculate cosine similarity
    private func cosineSimilarity(_ a: VectorEmbedding, _ b: VectorEmbedding) -> Float {
        guard a.count == b.count else { return 0.0 }
        
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0.0 }
        
        return dotProduct / denominator
    }
}

#endif // !BLAZEDB_LINUX_CORE

