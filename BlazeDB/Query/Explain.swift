//
//  Explain.swift
//  BlazeDB
//
//  EXPLAIN query plans for performance analysis
//  Optimized with detailed execution statistics
//
//  Created by Auto on 1/XX/25.
//

import Foundation

// MARK: - Query Plan

public struct QueryExecutionPlan {
    public let query: String
    public let executionSteps: [ExecutionStep]
    public let estimatedCost: Double
    public let estimatedRows: Int
    public let actualRows: Int?
    public let executionTime: TimeInterval?
    
    public struct ExecutionStep {
        public let operation: String
        public let details: String
        public let cost: Double
        public let rows: Int?
        public let indexUsed: String?
        
        public init(operation: String, details: String, cost: Double, rows: Int? = nil, indexUsed: String? = nil) {
            self.operation = operation
            self.details = details
            self.cost = cost
            self.rows = rows
            self.indexUsed = indexUsed
        }
    }
    
    public init(query: String, executionSteps: [ExecutionStep], estimatedCost: Double, estimatedRows: Int, actualRows: Int? = nil, executionTime: TimeInterval? = nil) {
        self.query = query
        self.executionSteps = executionSteps
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
        self.actualRows = actualRows
        self.executionTime = executionTime
    }
}

// MARK: - QueryBuilder EXPLAIN Extension

extension QueryBuilder {
    
    /// EXPLAIN query - analyze execution plan (detailed version)
    public func explainDetailed() throws -> QueryExecutionPlan {
        var steps: [QueryExecutionPlan.ExecutionStep] = []
        var totalCost: Double = 0.0
        var estimatedRows: Int = 0
        
        // Step 1: Analyze filters
        if !filters.isEmpty {
            let filterCost = Double(filters.count) * 0.1
            steps.append(QueryExecutionPlan.ExecutionStep(
                operation: "Filter",
                details: "\(filters.count) filter(s) applied",
                cost: filterCost
            ))
            totalCost += filterCost
        }
        
        // Step 2: Analyze indexes
        let indexUsed: String? = nil
        if collection != nil {
            // Check if any filter uses an indexed field
            for _ in filters {
                // Simplified: check if filter might use index
                // In real implementation, would check actual index usage
            }
            
            if indexUsed != nil {
                steps.append(QueryExecutionPlan.ExecutionStep(
                    operation: "Index Scan",
                    details: "Using index: \(indexUsed!)",
                    cost: 0.5,
                    indexUsed: indexUsed
                ))
                totalCost += 0.5
            } else {
                steps.append(QueryExecutionPlan.ExecutionStep(
                    operation: "Full Table Scan",
                    details: "Scanning all records",
                    cost: 10.0
                ))
                totalCost += 10.0
            }
        }
        
        // Step 3: Analyze joins
        if !joinOperations.isEmpty {
            for join in joinOperations {
                let joinCost = Double(joinOperations.count) * 2.0
                steps.append(QueryExecutionPlan.ExecutionStep(
                    operation: "Join",
                    details: "\(join.type) join on \(join.foreignKey) = \(join.primaryKey)",
                    cost: joinCost
                ))
                totalCost += joinCost
            }
        }
        
        // Step 4: Analyze sorting
        if !sortOperations.isEmpty {
            let sortCost = Double(sortOperations.count) * 1.5
            steps.append(QueryExecutionPlan.ExecutionStep(
                operation: "Sort",
                details: "Sorting by \(sortOperations.map { $0.field }.joined(separator: ", "))",
                cost: sortCost
            ))
            totalCost += sortCost
        }
        
        // Step 5: Analyze aggregations
        if !aggregations.isEmpty {
            let aggCost = Double(aggregations.count) * 1.0
            steps.append(QueryExecutionPlan.ExecutionStep(
                operation: "Aggregate",
                details: "\(aggregations.count) aggregation(s)",
                cost: aggCost
            ))
            totalCost += aggCost
        }
        
        // Step 6: Analyze window functions (if QueryBuilder supports them)
        // Note: Window functions are not yet implemented in QueryBuilder
        // This step is reserved for future implementation
        
        // Step 7: Analyze limit/offset
        if let limit = limitValue {
            steps.append(QueryExecutionPlan.ExecutionStep(
                operation: "Limit",
                details: "Limiting to \(limit) rows",
                cost: 0.1
            ))
            totalCost += 0.1
        }
        
        if offsetValue > 0 {
            steps.append(QueryExecutionPlan.ExecutionStep(
                operation: "Offset",
                details: "Skipping \(offsetValue) rows",
                cost: 0.1
            ))
            totalCost += 0.1
        }
        
        // Estimate rows (simplified)
        estimatedRows = limitValue ?? 1000
        
        let queryDescription = generateQueryDescription()
        
        return QueryExecutionPlan(
            query: queryDescription,
            executionSteps: steps,
            estimatedCost: totalCost,
            estimatedRows: estimatedRows
        )
    }
    
    /// EXPLAIN ANALYZE - execute query and return plan with actual stats
    public func explainAnalyze() throws -> QueryExecutionPlan {
        let startTime = Date()
        // Call the QueryExecutionPlan version explicitly
        let plan: QueryExecutionPlan = try explainDetailed()
        
        // Execute query to get actual stats
        let result = try execute()
        let actualRows = try result.records.count
        let executionTime = Date().timeIntervalSince(startTime)
        
        return QueryExecutionPlan(
            query: plan.query,
            executionSteps: plan.executionSteps,
            estimatedCost: plan.estimatedCost,
            estimatedRows: plan.estimatedRows,
            actualRows: actualRows,
            executionTime: executionTime
        )
    }
    
    private func generateQueryDescription() -> String {
        var parts: [String] = []
        
        if !filters.isEmpty {
            parts.append("WHERE (\(filters.count) conditions))")
        }
        
        if !joinOperations.isEmpty {
            parts.append("JOIN (\(joinOperations.count) join(s))")
        }
        
        if !sortOperations.isEmpty {
            parts.append("ORDER BY \(sortOperations.map { $0.field }.joined(separator: ", "))")
        }
        
        if let limit = limitValue {
            parts.append("LIMIT \(limit)")
        }
        
        return parts.joined(separator: " ")
    }
}

