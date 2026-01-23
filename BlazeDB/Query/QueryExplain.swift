//  QueryExplain.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Query Explain

/// Detailed query execution plan (explain output)
public struct DetailedQueryPlan: CustomStringConvertible {
    public let steps: [QueryStep]
    public let estimatedRecords: Int
    public let usesIndexes: [String]
    public let estimatedTime: TimeInterval
    public let warnings: [String]
    
    public var description: String {
        var output = "Query Execution Plan:\n"
        output += "  Estimated records: \(estimatedRecords)\n"
        
        if !usesIndexes.isEmpty {
            output += "  Using indexes: \(usesIndexes.joined(separator: ", "))\n"
        } else {
            output += "  ⚠️  No indexes used (full table scan)\n"
        }
        
        output += "  Estimated time: \(String(format: "%.2f", estimatedTime * 1000))ms\n"
        output += "\nExecution steps:\n"
        
        for (index, step) in steps.enumerated() {
            output += "  \(index + 1). \(step.description)\n"
        }
        
        if !warnings.isEmpty {
            output += "\n⚠️  Warnings:\n"
            for warning in warnings {
                output += "  - \(warning)\n"
            }
        }
        
        return output
    }
}

/// Individual query execution step
public struct QueryStep: CustomStringConvertible {
    public enum StepType {
        case tableScan
        case indexScan(String)
        case filter
        case join
        case sort
        case limit
        case aggregate
        case groupBy
    }
    
    public let type: StepType
    public let estimatedRecords: Int
    public let estimatedTime: TimeInterval
    
    public var description: String {
        switch type {
        case .tableScan:
            return "Table Scan (~\(estimatedRecords) records, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .indexScan(let index):
            return "Index Scan on '\(index)' (~\(estimatedRecords) records, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .filter:
            return "Apply Filters (~\(estimatedRecords) records remaining, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .join:
            return "Perform Join (~\(estimatedRecords) results, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .sort:
            return "Sort Results (~\(estimatedRecords) records, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .limit:
            return "Apply Limit (~\(estimatedRecords) records, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .aggregate:
            return "Compute Aggregations (~\(estimatedRecords) records, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        case .groupBy:
            return "Group By (~\(estimatedRecords) groups, ~\(String(format: "%.2f", estimatedTime * 1000))ms)"
        }
    }
}

// MARK: - QueryBuilder Extension

extension QueryBuilder {
    /// Generate query execution plan without executing
    /// - Returns: Detailed query plan with estimates
    public func explain() throws -> DetailedQueryPlan {
        guard let collection = collection else {
            throw BlazeDBError.transactionFailed("Collection has been deallocated")
        }
        
        var steps: [QueryStep] = []
        var estimatedRecords = collection.count()
        var estimatedTime: TimeInterval = 0
        var usesIndexes: [String] = []
        var warnings: [String] = []
        
        BlazeLogger.info("Generating query execution plan")
        
        // Step 1: Scan estimation
        if estimatedRecords < 1000 {
            // Small dataset: table scan is fine
            steps.append(QueryStep(
                type: .tableScan,
                estimatedRecords: estimatedRecords,
                estimatedTime: Double(estimatedRecords) * 0.00005  // 0.05ms per record
            ))
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        } else {
            // Large dataset: check if indexes would help
            // NOTE: Index matching analysis intentionally not implemented in explain output.
            // Query planner automatically selects indexes; explain focuses on execution steps.
            steps.append(QueryStep(
                type: .tableScan,
                estimatedRecords: estimatedRecords,
                estimatedTime: Double(estimatedRecords) * 0.00005
            ))
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
            
            warnings.append("Large dataset (\(estimatedRecords) records) - consider adding indexes")
        }
        
        // Step 2: Filter estimation
        if !filters.isEmpty {
            // Estimate 10% selectivity per filter (conservative)
            let filteredCount = Swift.max(1, Int(Double(estimatedRecords) * pow(0.1, Double(filters.count))))
            steps.append(QueryStep(
                type: .filter,
                estimatedRecords: filteredCount,
                estimatedTime: Double(estimatedRecords) * 0.00001  // 0.01ms per record
            ))
            estimatedRecords = filteredCount
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        }
        
        // Step 3: Join estimation
        if !joinOperations.isEmpty {
            steps.append(QueryStep(
                type: .join,
                estimatedRecords: estimatedRecords,
                estimatedTime: Double(estimatedRecords) * 0.0001  // 0.1ms per record
            ))
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        }
        
        // Step 4: Aggregation/Group By estimation
        if !groupByFields.isEmpty {
            // Estimate ~10 groups (conservative)
            let estimatedGroups = Swift.min(estimatedRecords, 10)
            steps.append(QueryStep(
                type: .groupBy,
                estimatedRecords: estimatedGroups,
                estimatedTime: Double(estimatedRecords) * 0.00002  // 0.02ms per record
            ))
            estimatedRecords = estimatedGroups
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        } else if !aggregations.isEmpty {
            steps.append(QueryStep(
                type: .aggregate,
                estimatedRecords: 1,
                estimatedTime: Double(estimatedRecords) * 0.00002
            ))
            estimatedRecords = 1
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        }
        
        // Step 5: Sort estimation
        if !sortOperations.isEmpty {
            steps.append(QueryStep(
                type: .sort,
                estimatedRecords: estimatedRecords,
                estimatedTime: Double(estimatedRecords) * log2(Double(estimatedRecords)) * 0.000001
            ))
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        }
        
        // Step 6: Limit estimation
        if let limit = limitValue {
            steps.append(QueryStep(
                type: .limit,
                estimatedRecords: Swift.min(estimatedRecords, limit),
                estimatedTime: 0.0001  // Negligible
            ))
            estimatedRecords = Swift.min(estimatedRecords, limit)
            if let lastStep = steps.last {
                estimatedTime += lastStep.estimatedTime
            }
        }
        
        // Warnings
        if filters.count > 5 {
            warnings.append("Many filters (\(filters.count)) - consider simplifying query")
        }
        
        if !sortOperations.isEmpty && estimatedRecords > 10000 {
            warnings.append("Sorting \(estimatedRecords) records - may be slow")
        }
        
        return DetailedQueryPlan(
            steps: steps,
            estimatedRecords: estimatedRecords,
            usesIndexes: usesIndexes,
            estimatedTime: estimatedTime,
            warnings: warnings
        )
    }
    
    /// Print query plan to console (convenience)
    public func explainQuery() throws {
        let plan = try explain()
        print(plan.description)
    }
}

// MARK: - Index Hints

extension QueryBuilder {
    /// Hint to use specific index
    /// - Parameter indexName: Name of the index to use
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func useIndex(_ indexName: String) -> QueryBuilder {
        BlazeLogger.debug("Query hint: USE INDEX '\(indexName)'")
        // Note: Actual index usage would require integration with DynamicCollection
        // For now, this is a hint for future optimization
        return self
    }
    
    /// Force full table scan (ignore all indexes)
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func forceTableScan() -> QueryBuilder {
        BlazeLogger.debug("Query hint: FORCE TABLE SCAN")
        // Note: Actual implementation would bypass index lookups
        return self
    }
}

