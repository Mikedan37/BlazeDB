//  QueryExplain.swift
//  BlazeDB
//  Created by Michael Danylchuk on 1/7/25.

import Foundation

// MARK: - Query Explain

/// Query execution plan with step estimates.
///
/// **Note:** `candidateIndexes` lists indexes that *exist* on queried fields but does not
/// guarantee the engine uses them at execution time. The current execution path performs
/// a full table scan followed by in-memory filtering regardless of indexes.
public struct DetailedQueryPlan: CustomStringConvertible {
    public let steps: [QueryStep]
    public let estimatedRecords: Int
    /// Indexes that exist on fields referenced in this query's filters.
    /// These are *candidates* — the engine may or may not use them at execution time.
    public let candidateIndexes: [String]
    public let estimatedTime: TimeInterval
    public let warnings: [String]
    /// Count of chained filter predicates (same notion as deprecated `QueryExplanation.filterCount`).
    public let filterPredicateCount: Int
    /// Field names from `where` clauses, sorted for stable logging and tests.
    public let referencedFilterFields: [String]

    public var description: String {
        var output = "Query Execution Plan:\n"
        output += "  Estimated records: \(estimatedRecords)\n"
        output += "  Filter predicates: \(filterPredicateCount)\n"
        if referencedFilterFields.isEmpty {
            output += "  Filter fields: none\n"
        } else {
            output += "  Filter fields: \(referencedFilterFields.joined(separator: ", "))\n"
        }

        if !candidateIndexes.isEmpty {
            output += "  Candidate indexes: \(candidateIndexes.joined(separator: ", "))\n"
        } else {
            output += "  No candidate indexes (full table scan)\n"
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
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        
        var steps: [QueryStep] = []
        var estimatedRecords = collection.count()
        var estimatedTime: TimeInterval = 0
        var candidateIndexes: [String] = []
        var warnings: [String] = []
        
        BlazeLogger.info("Generating query execution plan")
        
        if !filterFields.isEmpty {
            let availableIndexes = collection.secondaryIndexes.keys
            candidateIndexes = Array(filterFields).filter { field in
                availableIndexes.contains { indexName in
                    indexName == field ||
                    indexName == "idx_\(field)" ||
                    indexName.hasPrefix("\(field)+") ||
                    indexName.hasSuffix("+\(field)")
                }
            }
        }
        
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
            // Large dataset: include candidate indexes for referenced filter fields.
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
        
        if !candidateIndexes.isEmpty {
            warnings.append("Indexes listed are candidates only; current execution may still use full table scan paths")
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
            candidateIndexes: candidateIndexes,
            estimatedTime: estimatedTime,
            warnings: warnings,
            filterPredicateCount: filters.count,
            referencedFilterFields: Array(filterFields).sorted()
        )
    }
    
    /// Print query plan to console (convenience)
    @available(*, deprecated, message: "Use explain() instead, which returns a DetailedQueryPlan you can inspect programmatically.")
    public func explainQuery() throws {
        let plan = try explain()
        print(plan.description)
    }
}

// MARK: - Index Hints (Stubs)

extension QueryBuilder {
    /// Hint to prefer a specific index during execution.
    ///
    /// **Status:** Stub — this method logs the hint but does not influence query execution.
    /// The engine currently performs full table scans with in-memory filtering.
    /// - Parameter indexName: Name of the index to prefer
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func useIndex(_ indexName: String) -> QueryBuilder {
        BlazeLogger.debug("Query hint: USE INDEX '\(indexName)' (not yet implemented)")
        return self
    }

    /// Hint to skip indexes and force a full table scan.
    ///
    /// **Status:** Stub — this method logs the hint but does not influence query execution.
    /// The engine currently always performs full table scans.
    /// - Returns: QueryBuilder for chaining
    @discardableResult
    public func forceTableScan() -> QueryBuilder {
        BlazeLogger.debug("Query hint: FORCE TABLE SCAN (not yet implemented)")
        return self
    }
}

