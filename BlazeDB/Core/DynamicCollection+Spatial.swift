//
//  DynamicCollection+Spatial.swift
//  BlazeDB
//
//  Geospatial indexing integration for DynamicCollection.
//  Provides fast location-based queries via R-tree spatial indexing.
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE

import Foundation

// MARK: - Spatial Index Management

extension DynamicCollection {
    // Note: cachedSpatialIndex and cachedSpatialIndexedFields are now stored properties on DynamicCollection
    // This removes the need for Objective-C runtime associated objects
    
    /// Expose cached spatial index for query builder access
    public var spatialIndex: SpatialIndex? {
        return cachedSpatialIndex
    }
    
    /// Enable spatial indexing on latitude/longitude fields
    ///
    /// Once enabled, location-based queries will be O(log n) instead of O(n).
    /// The index is automatically maintained on insert/update/delete.
    ///
    /// Memory overhead: ~1-2% of database size
    ///
    /// Example:
    /// ```swift
    /// try db.collection.enableSpatialIndex(on: "latitude", lonField: "longitude")
    ///
    /// // Location queries now use spatial index (ultra-fast!)
    /// let nearby = try db.query()
    ///     .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
    ///     .execute()
    /// ```
    ///
    /// - Parameters:
    ///   - latField: Field name for latitude
    ///   - lonField: Field name for longitude
    /// - Throws: If indexing fails
    public func enableSpatialIndex(on latField: String, lonField: String) throws {
        try queue.sync(flags: .barrier) {
            // CRITICAL: Always create a fresh index to ensure we start clean
            // Even if cachedSpatialIndex exists (from disk), we rebuild it from scratch
            // This ensures the index is consistent with the current data
            let index = SpatialIndex()
            index.enable(on: latField, lonField: lonField)
            
            // Rebuild index for all existing records
            BlazeLogger.info("Rebuilding spatial index for \(indexMap.count) existing records")
            var indexedCount = 0
            
            for (id, pageIndices) in indexMap {
                guard let firstPageIndex = pageIndices.first else { continue }
                do {
                    let data = try store.readPageWithOverflow(index: firstPageIndex)
                    guard let data = data, !data.isEmpty else { continue }
                    guard !data.allSatisfy({ $0 == 0 }) else { continue }
                    
                    let record = try BlazeBinaryDecoder.decode(data)
                    
                    // Check if record has latitude and longitude
                    guard record.storage[latField]?.doubleValue != nil,
                          record.storage[lonField]?.doubleValue != nil else {
                        continue
                    }
                    
                    index.indexRecord(record)
                    indexedCount += 1
                } catch {
                    BlazeLogger.warn("Failed to index record \(id) for spatial index: \(error)")
                }
            }
            
            // Update cached index and fields
            cachedSpatialIndex = index
            cachedSpatialIndexedFields = (latField, lonField)
            
            // Save to layout
            try saveSpatialIndexToLayout()
            
            BlazeLogger.info("Spatial index enabled: indexed \(indexedCount) records")
        }
    }
    
    /// Disable spatial indexing
    public func disableSpatialIndex() {
        queue.sync(flags: .barrier) {
            cachedSpatialIndex = nil
            cachedSpatialIndexedFields = nil
            
            // Update layout
            // Note: spatialIndex and spatialIndexedFields are not stored in StorageLayout
            // Spatial index state is maintained in memory only
            BlazeLogger.info("Spatial index disabled (in-memory state cleared)")
        }
    }
    
    /// Get spatial index statistics
    public func getSpatialIndexStats() -> SpatialIndexStats? {
        return queue.sync {
            return cachedSpatialIndex?.getStats()
        }
    }
    
    /// Rebuild spatial index (useful after bulk updates)
    public func rebuildSpatialIndex() throws {
        guard let (latField, lonField) = cachedSpatialIndexedFields else {
            throw BlazeDBError.invalidQuery(reason: "Spatial index not enabled")
        }
        
        try queue.sync(flags: .barrier) {
            let index = SpatialIndex()
            index.enable(on: latField, lonField: lonField)
            
            var indexedCount = 0
            for (_, pageIndices) in indexMap {
                guard let firstPageIndex = pageIndices.first else { continue }
                do {
                    let data = try store.readPageWithOverflow(index: firstPageIndex)
                    guard let data = data, !data.isEmpty else { continue }
                    guard !data.allSatisfy({ $0 == 0 }) else { continue }
                    
                    let record = try BlazeBinaryDecoder.decode(data)
                    if record.storage[latField]?.doubleValue != nil,
                       record.storage[lonField]?.doubleValue != nil {
                        index.indexRecord(record)
                        indexedCount += 1
                    }
                } catch {
                    continue
                }
            }
            
            cachedSpatialIndex = index
            try saveSpatialIndexToLayout()
            
            BlazeLogger.info("Spatial index rebuilt: \(indexedCount) records")
        }
    }
    
    // MARK: - Internal Helpers
    
    internal func updateSpatialIndexOnInsert(_ record: BlazeDataRecord) {
        guard let index = cachedSpatialIndex,
              let (latField, lonField) = cachedSpatialIndexedFields else {
            BlazeLogger.trace("Spatial index not enabled, skipping index update")
            return
        }
        
        // Verify record has required fields before indexing
        guard let id = record.storage["id"]?.uuidValue,
              let lat = record.storage[latField]?.doubleValue,
              let lon = record.storage[lonField]?.doubleValue else {
            BlazeLogger.trace("Record missing required fields for spatial index (id, \(latField), \(lonField))")
            return
        }
        
        // Ensure indexedFields is set on the index before indexing
        // This is safe to call multiple times - enable() is idempotent
        // CRITICAL: Must call enable() to set indexedFields, otherwise indexRecord() will fail silently
        index.enable(on: latField, lonField: lonField)
        
        // Index the record - this will update the index in-memory
        // Note: indexRecord() checks indexedFields inside its queue.sync block, so enable() must complete first
        index.indexRecord(record)
        
        BlazeLogger.trace("Updated spatial index for inserted record \(id) at (\(lat), \(lon))")
    }
    
    internal func updateSpatialIndexOnUpdate(_ record: BlazeDataRecord) {
        guard let index = cachedSpatialIndex,
              let recordID = record.storage["id"]?.uuidValue else { return }
        // Remove old, add new
        index.removeRecord(recordID)
        index.indexRecord(record)
        BlazeLogger.trace("Updated spatial index for updated record \(recordID)")
    }
    
    internal func updateSpatialIndexOnDelete(_ id: UUID) {
        guard let index = cachedSpatialIndex else { return }
        index.removeRecord(id)
        BlazeLogger.trace("Removed record \(id) from spatial index")
    }
    
    private func saveSpatialIndexToLayout() throws {
        // Note: spatialIndex and spatialIndexedFields are not stored in StorageLayout
        // Spatial index state is maintained in memory only
        BlazeLogger.debug("Spatial index state - not persisted to layout")
    }
}

#endif // !BLAZEDB_LINUX_CORE
