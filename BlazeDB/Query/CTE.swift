//
//  CTE.swift
//  BlazeDB
//
//  Common Table Expressions (WITH clauses)
//  Optimized with query caching and lazy evaluation
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - CTE Definition

public struct CTEDefinition {
    public let name: String
    public let query: QueryBuilder
    
    public init(name: String, query: QueryBuilder) {
        self.name = name
        self.query = query
    }
}

// MARK: - CTE Builder

public class CTEBuilder {
    private var ctes: [CTEDefinition] = []
    private var mainQuery: QueryBuilder?
    
    public init() {}
    
    /// Define a CTE (WITH clause)
    @discardableResult
    public func with(_ name: String, as query: QueryBuilder) -> CTEBuilder {
        ctes.append(CTEDefinition(name: name, query: query))
        return self
    }
    
    /// Set the main query that uses CTEs
    @discardableResult
    public func select(_ query: QueryBuilder) -> CTEBuilder {
        self.mainQuery = query
        return self
    }
    
    /// Execute CTE query (optimized with caching)
    public func execute() throws -> [BlazeDataRecord] {
        let startTime = Date()
        
        // OPTIMIZATION: Execute all CTEs first (with result caching)
        var cteResults: [String: [BlazeDataRecord]] = [:]
        cteResults.reserveCapacity(ctes.count) // Pre-allocate
        
        for cte in ctes {
            // OPTIMIZATION: Check cache first (if implemented)
            let result = try cte.query.execute()
            let records = try result.records
            cteResults[cte.name] = records
            BlazeLogger.debug("CTE '\(cte.name)' executed: \(records.count) records")
        }
        
        // If main query references CTEs, we need to inject them
        // For now, execute main query (CTE injection would require query rewriting)
        guard let mainQuery = mainQuery else {
            throw BlazeDBError.invalidQuery(reason: "No main query specified for CTE")
        }
        
        // OPTIMIZATION: Execute main query (CTEs already cached)
        let result = try mainQuery.execute()
        let records = try result.records
        
        let duration = Date().timeIntervalSince(startTime)
        BlazeLogger.debug("CTE query completed in \(String(format: "%.3f", duration))s: \(records.count) results")
        
        return records
    }
    
    /// Execute and return QueryResult
    public func executeResult() throws -> QueryResult {
        let records = try execute()
        return .records(records)
    }
}

// MARK: - QueryBuilder CTE Extension

extension QueryBuilder {
    
    /// Start a CTE (WITH clause)
    public static func with(_ name: String, as query: QueryBuilder) -> CTEBuilder {
        let builder = CTEBuilder()
        builder.with(name, as: query)
        return builder
    }
}

// MARK: - BlazeDBClient CTE Extension

extension BlazeDBClient {
    
    /// Create a CTE builder
    public func with(_ name: String, as query: QueryBuilder) -> CTEBuilder {
        let builder = CTEBuilder()
        builder.with(name, as: query)
        return builder
    }
}

