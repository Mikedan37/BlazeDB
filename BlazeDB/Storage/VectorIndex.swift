//
//  VectorIndex.swift
//  BlazeDB
//
//  Vector embeddings index for semantic search
//  Uses cosine similarity for nearest neighbor search
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Vector embedding (array of floats)
public typealias VectorEmbedding = [Float]

/// Vector index for semantic search
public final class VectorIndex {
    private var vectors: [UUID: VectorEmbedding] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    /// Insert or update a vector
    public func insert(_ vector: VectorEmbedding, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        vectors[id] = vector
    }
    
    /// Remove a vector
    public func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        vectors.removeValue(forKey: id)
    }
    
    /// Find nearest vectors using cosine similarity
    /// - Parameters:
    ///   - query: Query vector
    ///   - limit: Maximum number of results
    ///   - threshold: Minimum similarity threshold (0.0 to 1.0)
    /// - Returns: Array of (UUID, similarity) tuples, sorted by similarity (highest first)
    public func nearest(to query: VectorEmbedding, limit: Int, threshold: Float = 0.0) -> [(UUID, Float)] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [(UUID, Float)] = []
        
        for (id, vector) in vectors {
            let similarity = cosineSimilarity(query, vector)
            if similarity >= threshold {
                results.append((id, similarity))
            }
        }
        
        // Sort by similarity (highest first)
        results.sort { $0.1 > $1.1 }
        
        return Array(results.prefix(limit))
    }
    
    /// Calculate cosine similarity between two vectors
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
    
    /// Get statistics
    public func getStats() -> VectorIndexStats {
        lock.lock()
        defer { lock.unlock() }
        return VectorIndexStats(
            totalVectors: vectors.count,
            averageDimension: vectors.values.first?.count ?? 0
        )
    }
}

/// Vector index statistics
public struct VectorIndexStats {
    public let totalVectors: Int
    public let averageDimension: Int
}

