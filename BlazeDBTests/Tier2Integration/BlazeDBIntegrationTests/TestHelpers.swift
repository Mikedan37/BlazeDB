//
//  TestHelpers.swift
//  BlazeDBIntegrationTests
//
//  Helper extensions for integration tests
//

import Foundation
@testable import BlazeDBCore

// MARK: - Search Helper Extension

extension DynamicCollection {
    /// Convenience search method for integration tests
    func search(query: String, in fields: [String]? = nil) throws -> [FullTextSearchResult] {
        let searchFields = fields ?? self.integrationTestDefaultSearchFields
        #if BLAZEDB_LINUX_CORE
        return try integrationTestManualSearch(query: query, in: searchFields)
        #else
        return try self.searchOptimized(query: query, in: searchFields)
        #endif
    }
    
    /// Convenience search method with just query
    func search(query: String) throws -> [FullTextSearchResult] {
        return try search(query: query, in: nil)
    }
    
    /// Convenience enableSearch for tests (`fields:` matches call sites; Apple delegates to inverted index)
    func enableSearch(fields: [String]) throws {
        #if BLAZEDB_LINUX_CORE
        // Inverted index path is not in Linux core; scan-based `search` still works for tests.
        _ = fields
        #else
        try self.enableSearch(on: fields)
        #endif
    }
    
    fileprivate var integrationTestDefaultSearchFields: [String] {
        if !self.cachedSearchIndexedFields.isEmpty {
            return self.cachedSearchIndexedFields
        }
        return ["title", "description", "content", "name", "bio"]
    }
    
    #if BLAZEDB_LINUX_CORE
    fileprivate func integrationTestManualSearch(query: String, in fields: [String]) throws -> [FullTextSearchResult] {
        let allRecords = try fetchAll()
        var results: [FullTextSearchResult] = []
        let q = query.lowercased()
        for record in allRecords {
            for field in fields {
                guard let value = record.storage[field]?.stringValue else { continue }
                let searchValue = value.lowercased()
                if searchValue.contains(q) {
                    results.append(FullTextSearchResult(
                        record: record,
                        score: 1.0,
                        matches: [field: [query]]
                    ))
                    break
                }
            }
        }
        return results
    }
    #endif
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
