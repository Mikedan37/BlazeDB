//
//  BlazeDBClient+ConvenienceAPI.swift
//  BlazeDB
//
//  Small convenience helpers that fill common API gaps.
//

import Foundation

extension BlazeDBClient {

    /// Fetch a record by ID, throwing if not found.
    ///
    /// Use when absence is an error condition.
    /// For optional lookup, use `fetch(id:)` instead.
    ///
    /// - Parameter id: Record UUID
    /// - Returns: The record
    /// - Throws: `BlazeDBError.recordNotFound` if no record exists with this ID
    public func fetchRequired(id: UUID) throws -> BlazeDataRecord {
        guard let record = try fetch(id: id) else {
            throw BlazeDBError.recordNotFound(id: id)
        }
        return record
    }

    /// Check if a record with the given ID exists.
    ///
    /// - Parameter id: Record UUID
    /// - Returns: true if a record with this ID exists
    public func exists(id: UUID) throws -> Bool {
        return try fetch(id: id) != nil
    }

}
