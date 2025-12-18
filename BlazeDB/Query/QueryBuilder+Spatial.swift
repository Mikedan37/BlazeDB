//
//  QueryBuilder+Spatial.swift
//  BlazeDB
//
//  Geospatial query methods for QueryBuilder.
//  Provides fluent API for location-based queries.
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

// MARK: - Geospatial Queries

extension QueryBuilder {
    
    /// Filter records within radius (meters) of a point
    ///
    /// Uses spatial index if enabled, otherwise falls back to full scan.
    ///
    /// Example:
    /// ```swift
    /// let nearby = try db.query()
    ///     .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - latitude: Center point latitude
    ///   - longitude: Center point longitude
    ///   - radiusMeters: Search radius in meters
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func withinRadius(latitude: Double, longitude: Double, radiusMeters: Double) -> QueryBuilder {
        BlazeLogger.debug("Query: WITHIN_RADIUS (\(latitude), \(longitude)), radius: \(radiusMeters)m")
        
        let center = SpatialPoint(latitude: latitude, longitude: longitude)
        _ = BoundingBox.from(center: center, radiusMeters: radiusMeters)
        
        // Try to use spatial index first
        if let collection = collection,
           let spatialIndex = collection.spatialIndex,
           let (latField, lonField) = collection.cachedSpatialIndexedFields {
            
            BlazeLogger.debug("Using spatial index for radius query")
            let stats = spatialIndex.getStats()
            BlazeLogger.debug("Spatial index stats before query: totalRecords=\(stats.totalRecords), treeHeight=\(stats.treeHeight)")
            let candidateIds = spatialIndex.withinRadius(center: center, radiusMeters: radiusMeters)
            
            BlazeLogger.debug("Spatial index found \(candidateIds.count) candidate records (query center: \(center.latitude), \(center.longitude), radius: \(radiusMeters)m)")
            if candidateIds.count == 0 && stats.totalRecords > 0 {
                BlazeLogger.warn("⚠️ Spatial index has \(stats.totalRecords) records but query returned 0 candidates - possible issue with query or index")
            }
            
            // Filter by candidate IDs and verify distance
            filters.append { [weak self] (record: BlazeDataRecord) -> Bool in
                guard self != nil,
                      let recordId = record.storage["id"]?.uuidValue,
                      candidateIds.contains(recordId) else { return false }
                
                guard let lat = record.storage[latField]?.doubleValue,
                      let lon = record.storage[lonField]?.doubleValue else {
                    return false
                }
                
                let point = SpatialPoint(latitude: lat, longitude: lon)
                let distance = center.distance(to: point)
                return distance <= radiusMeters
            }
        } else {
            // Fallback: full scan with distance calculation
            BlazeLogger.debug("Spatial index not enabled, using full scan")
            filters.append { [weak self] (record: BlazeDataRecord) -> Bool in
                guard let self = self else { return false }
                // Try common field names
                let latField = self.collection?.cachedSpatialIndexedFields?.latField ?? "latitude"
                let lonField = self.collection?.cachedSpatialIndexedFields?.lonField ?? "longitude"
                
                guard let lat = record.storage[latField]?.doubleValue,
                      let lon = record.storage[lonField]?.doubleValue else {
                    return false
                }
                
                let point = SpatialPoint(latitude: lat, longitude: lon)
                let distance = center.distance(to: point)
                return distance <= radiusMeters
            }
        }
        
        return self
    }
    
    /// Filter records within bounding box
    ///
    /// Uses spatial index if enabled, otherwise falls back to full scan.
    ///
    /// Example:
    /// ```swift
    /// let inArea = try db.query()
    ///     .withinBoundingBox(
    ///         minLat: 37.7, maxLat: 37.8,
    ///         minLon: -122.5, maxLon: -122.4
    ///     )
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - minLat: Minimum latitude
    ///   - maxLat: Maximum latitude
    ///   - minLon: Minimum longitude
    ///   - maxLon: Maximum longitude
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func withinBoundingBox(
        minLat: Double,
        maxLat: Double,
        minLon: Double,
        maxLon: Double
    ) -> QueryBuilder {
        BlazeLogger.debug("Query: WITHIN_BOUNDING_BOX (\(minLat), \(minLon)) to (\(maxLat), \(maxLon))")
        
        let box = BoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        
        // Try to use spatial index first
        if let collection = collection,
           let spatialIndex = collection.spatialIndex,
           let (latField, lonField) = collection.cachedSpatialIndexedFields {
            
            BlazeLogger.debug("Using spatial index for bounding box query")
            let candidateIds = spatialIndex.withinBoundingBox(box)
            
            // Filter by candidate IDs
            filters.append { (record: BlazeDataRecord) -> Bool in
                guard let recordId = record.storage["id"]?.uuidValue,
                      candidateIds.contains(recordId) else { return false }
                
                guard let lat = record.storage[latField]?.doubleValue,
                      let lon = record.storage[lonField]?.doubleValue else {
                    return false
                }
                
                let point = SpatialPoint(latitude: lat, longitude: lon)
                return box.contains(point)
            }
        } else {
            // Fallback: full scan
            BlazeLogger.debug("Spatial index not enabled, using full scan")
            filters.append { [weak self] (record: BlazeDataRecord) -> Bool in
                guard let self = self else { return false }
                let latField = self.collection?.cachedSpatialIndexedFields?.latField ?? "latitude"
                let lonField = self.collection?.cachedSpatialIndexedFields?.lonField ?? "longitude"
                
                guard let lat = record.storage[latField]?.doubleValue,
                      let lon = record.storage[lonField]?.doubleValue else {
                    return false
                }
                
                let point = SpatialPoint(latitude: lat, longitude: lon)
                return box.contains(point)
            }
        }
        
        return self
    }
    
    /// Filter records near a point (within radius, automatically sorted by distance)
    ///
    /// This is a convenience method that combines `.withinRadius()` and `.orderByDistance()`.
    ///
    /// Example:
    /// ```swift
    /// let nearest = try db.query()
    ///     .near(latitude: 37.7749, longitude: -122.4194, radiusMeters: 5000)
    ///     .limit(10)
    ///     .execute()
    /// 
    /// // Results are automatically sorted by distance
    /// for result in nearest {
    ///     print("\(result.name) - \(result.distance ?? 0)m away")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - latitude: Center point latitude
    ///   - longitude: Center point longitude
    ///   - radiusMeters: Search radius in meters
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func near(latitude: Double, longitude: Double, radiusMeters: Double) -> QueryBuilder {
        let center = SpatialPoint(latitude: latitude, longitude: longitude)
        sortByDistanceCenter = center
        BlazeLogger.debug("Query: NEAR (\(latitude), \(longitude)), radius: \(radiusMeters)m (auto-sorted by distance)")
        return withinRadius(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }
    
    /// Find nearest N records (true k-NN query)
    ///
    /// Uses expanding search radius to find the nearest records efficiently.
    ///
    /// Example:
    /// ```swift
    /// let nearest = try db.query()
    ///     .nearest(to: SpatialPoint(latitude: 37.7749, longitude: -122.4194), limit: 10)
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - point: Center point
    ///   - limit: Maximum number of results
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func nearest(to point: SpatialPoint, limit: Int) -> QueryBuilder {
        sortByDistanceCenter = point
        BlazeLogger.debug("Query: NEAREST to (\(point.latitude), \(point.longitude)), limit: \(limit)")
        
        // Use a large initial radius, then filter and sort
        // The spatial index will handle the k-NN search
        if let collection = collection,
           let spatialIndex = collection.spatialIndex {
            // Get candidate IDs from spatial index
            let candidates = spatialIndex.nearest(to: point, limit: limit * 2) // Get more candidates
            
            // Filter by candidate IDs
            let candidateIdSet = Set(candidates.map { $0.0 })
            filters.append { (record: BlazeDataRecord) -> Bool in
                guard let recordId = record.storage["id"]?.uuidValue else { return false }
                return candidateIdSet.contains(recordId)
            }
            
            // Limit will be applied in execute()
            if limitValue == nil {
                limitValue = limit
            }
        } else {
            // Fallback: use large bounding box
            let largeBox = BoundingBox.from(center: point, radiusMeters: 100_000)
            return withinBoundingBox(
                minLat: largeBox.minLat,
                maxLat: largeBox.maxLat,
                minLon: largeBox.minLon,
                maxLon: largeBox.maxLon
            )
        }
        
        return self
    }
    
    /// Sort results by distance from a point
    ///
    /// Example:
    /// ```swift
    /// let results = try db.query()
    ///     .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 5000)
    ///     .orderByDistance(from: SpatialPoint(latitude: 37.7749, longitude: -122.4194))
    ///     .limit(10)
    ///     .execute()
    /// ```
    ///
    /// - Parameter center: Center point to calculate distance from
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func orderByDistance(from center: SpatialPoint) -> QueryBuilder {
        sortByDistanceCenter = center
        BlazeLogger.debug("Query: ORDER BY DISTANCE from (\(center.latitude), \(center.longitude))")
        return self
    }
    
    /// Sort results by distance from coordinates
    ///
    /// - Parameters:
    ///   - latitude: Center point latitude
    ///   - longitude: Center point longitude
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func orderByDistance(latitude: Double, longitude: Double) -> QueryBuilder {
        return orderByDistance(from: SpatialPoint(latitude: latitude, longitude: longitude))
    }
}

#endif // !BLAZEDB_LINUX_CORE

