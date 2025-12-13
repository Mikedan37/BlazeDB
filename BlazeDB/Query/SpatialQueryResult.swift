//
//  SpatialQueryResult.swift
//  BlazeDB
//
//  Spatial query result with distance information.
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// A record with its distance from a query point
public struct SpatialQueryResult {
    public let record: BlazeDataRecord
    public let distance: Double  // Distance in meters
    
    public init(record: BlazeDataRecord, distance: Double) {
        self.record = record
        self.distance = distance
    }
}

// MARK: - BlazeDataRecord Distance Extension

extension BlazeDataRecord {
    /// Calculate distance to a point (requires latitude/longitude fields)
    ///
    /// - Parameters:
    ///   - point: Target point
    ///   - latField: Latitude field name (default: "latitude")
    ///   - lonField: Longitude field name (default: "longitude")
    /// - Returns: Distance in meters, or nil if coordinates missing
    public func distance(to point: SpatialPoint, latField: String = "latitude", lonField: String = "longitude") -> Double? {
        guard let lat = storage[latField]?.doubleValue,
              let lon = storage[lonField]?.doubleValue else {
            return nil
        }
        
        let recordPoint = SpatialPoint(latitude: lat, longitude: lon)
        return point.distance(to: recordPoint)
    }
    
    /// Get distance from a query center (if calculated)
    ///
    /// This is populated when using `.orderByDistance()` or `.near()`
    public var distance: Double? {
        return storage["_queryDistance"]?.doubleValue
    }
}

