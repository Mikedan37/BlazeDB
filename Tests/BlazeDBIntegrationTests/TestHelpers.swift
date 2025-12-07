//
//  TestHelpers.swift
//  BlazeDBIntegrationTests
//
//  Helper extensions for integration tests
//

import Foundation
@testable import BlazeDB

// MARK: - Search Helper Extension

extension DynamicCollection {
    /// Convenience search method for integration tests
    func search(query: String, in fields: [String]? = nil) throws -> [FullTextSearchResult] {
        let searchFields = fields ?? self.searchFields
        return try self.searchOptimized(query: query, in: searchFields)
    }
    
    /// Convenience search method with just query
    func search(query: String) throws -> [FullTextSearchResult] {
        return try self.searchOptimized(query: query, in: self.searchFields)
    }
    
    /// Convenience enableSearch for tests
    func enableSearch(fields: [String]) throws {
        try self.enableSearch(on: fields)
    }
    
    private var searchFields: [String] {
        // For test helpers, just return empty array
        // Search fields are managed internally by DynamicCollection
        return []
    }
}

// MARK: - BlazeDBClient Extensions

extension BlazeDBClient {
    /// Convenience updateMany for tests
    func updateMany(
        where predicate: @escaping (BlazeDataRecord) -> Bool,
        with record: BlazeDataRecord
    ) async throws -> Int {
        return try await self.updateMany(
            where: predicate,
            set: record.storage
        )
    }
}

