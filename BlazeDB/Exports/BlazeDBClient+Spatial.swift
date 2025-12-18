//
//  BlazeDBClient+Spatial.swift
//  BlazeDB
//
//  Geospatial query convenience methods for BlazeDBClient.
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

// MARK: - Spatial Index Management

extension BlazeDBClient {
    
    /// Enable spatial indexing on latitude/longitude fields
    ///
    /// Once enabled, location-based queries will be O(log n) instead of O(n).
    /// The index is automatically maintained on insert/update/delete.
    ///
    /// Memory overhead: ~1-2% of database size
    ///
    /// Example:
    /// ```swift
    /// try db.enableSpatialIndex(on: "latitude", lonField: "longitude")
    ///
    /// // Location queries now use spatial index (ultra-fast!)
    /// let nearby = try db.query()
    ///     .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - latField: Field name for latitude (default: "latitude")
    ///   - lonField: Field name for longitude (default: "longitude")
    /// - Throws: If indexing fails
    public func enableSpatialIndex(on latField: String = "latitude", lonField: String = "longitude") throws {
        BlazeLogger.info("Enabling spatial index on fields: \(latField), \(lonField)")
        try collection.enableSpatialIndex(on: latField, lonField: lonField)
    }
    
    /// Disable spatial indexing
    public func disableSpatialIndex() {
        BlazeLogger.info("Disabling spatial index")
        collection.disableSpatialIndex()
    }
    
    /// Check if spatial indexing is enabled
    public func isSpatialIndexEnabled() -> Bool {
        return collection.cachedSpatialIndex != nil
    }
    
    /// Get spatial index statistics
    public func getSpatialIndexStats() -> SpatialIndexStats? {
        return collection.getSpatialIndexStats()
    }
    
    /// Rebuild spatial index (useful after bulk updates)
    public func rebuildSpatialIndex() throws {
        BlazeLogger.info("Rebuilding spatial index")
        try collection.rebuildSpatialIndex()
    }
}
#endif // !BLAZEDB_LINUX_CORE
