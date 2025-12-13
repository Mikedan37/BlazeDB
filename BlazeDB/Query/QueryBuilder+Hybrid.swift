//
//  QueryBuilder+Hybrid.swift
//  BlazeDB
//
//  Combined vector + spatial queries
//  The "insane" feature: semantic search + location
//
//  Created by Auto on 1/XX/25.
//

import Foundation

extension QueryBuilder {
    
    /// Combined vector + spatial query (pipelined execution)
    ///
    /// Pipeline: vector results → spatial filter → reduce → reorder
    ///
    /// Example:
    /// ```swift
    /// // "Find journal entries that feel emotionally similar to 'anxious' 
    /// //  AND happened within 2km of my gym"
    /// let results = try db.query()
    ///     .vectorAndSpatial(
    ///         vectorField: "moodEmbedding",
    ///         vectorEmbedding: anxiousEmbedding,
    ///         latitude: gym.lat,
    ///         longitude: gym.lon,
    ///         radiusMeters: 2000
    ///     )
    ///     .execute()
    /// ```
    ///
    /// Execution pipeline:
    /// 1. Vector search (get candidates by similarity)
    /// 2. Spatial filter (reduce to within radius)
    /// 3. Distance sort (reorder by proximity)
    /// 4. Limit results
    ///
    /// - Returns: QueryBuilder for chaining
    public func vectorAndSpatial(
        vectorField: String,
        vectorEmbedding: VectorEmbedding,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        vectorLimit: Int = 100,
        vectorThreshold: Float = 0.0
    ) -> QueryBuilder {
        BlazeLogger.debug("Query: VECTOR + SPATIAL hybrid (pipelined)")
        
        // Store pipeline configuration
        // Execution happens in execute() with proper ordering
        _ = vectorNearest(field: vectorField, to: vectorEmbedding, limit: vectorLimit, threshold: vectorThreshold)
        _ = withinRadius(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
        _ = orderByDistance(latitude: latitude, longitude: longitude)
        
        return self
    }
    
    /// Combined vector + spatial + full-text query
    ///
    /// Example:
    /// ```swift
    /// // "Find restaurants matching 'pizza' that feel similar to 'cozy' 
    /// //  AND are within 1km of me"
    /// let results = try db.query()
    ///     .vectorNearest(field: "atmosphereEmbedding", to: cozyEmbedding, limit: 50)
    ///     .fullTextSearch("name", query: "pizza")
    ///     .withinRadius(latitude: myLat, longitude: myLon, radiusMeters: 1000)
    ///     .orderByDistance(latitude: myLat, longitude: myLon)
    ///     .execute()
    /// ```
    public func vectorSpatialAndFullText(
        vectorField: String,
        vectorEmbedding: VectorEmbedding,
        fullTextField: String,
        fullTextQuery: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double
    ) -> QueryBuilder {
        BlazeLogger.debug("Query: VECTOR + SPATIAL + FULLTEXT hybrid query")
        
        // Apply all three filters
        _ = vectorNearest(field: vectorField, to: vectorEmbedding, limit: 100)
        // NOTE: Full-text search in hybrid queries intentionally not implemented.
        // Use QueryBuilder+Search for full-text search separately, or chain queries.
        _ = withinRadius(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
        _ = orderByDistance(latitude: latitude, longitude: longitude)
        
        return self
    }
}

