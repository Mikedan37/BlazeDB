//
//  QueryOptimizer.swift
//  BlazeDB
//
//  Cost-based query optimizer
//  Selects optimal query plan based on index availability and data statistics
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Query execution plan
public struct QueryPlan {
    public let useIndex: String?
    public let scanOrder: ScanOrder
    public let estimatedCost: Double
    public let estimatedRows: Int
    
    public enum ScanOrder {
        case sequential
        case index
        case parallel
    }
    
    public init(useIndex: String?, scanOrder: ScanOrder, estimatedCost: Double, estimatedRows: Int) {
        self.useIndex = useIndex
        self.scanOrder = scanOrder
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
    }
}

/// Optimized query plan (uses QueryPlan from QueryOptimizer)
public typealias OptimizedQueryPlan = QueryPlan

/// Cost-based query optimizer
public class QueryOptimizer {
    
    /// Extract filter fields from query filters
    /// Uses the tracked filterFields from QueryBuilder if available, otherwise falls back to heuristic
    private static func extractFilterFields(from query: QueryBuilder, collection: DynamicCollection) -> Set<String> {
        // Use tracked filter fields from QueryBuilder (most accurate)
        if !query.filterFields.isEmpty {
            return query.filterFields
        }
        
        // Fallback: Try to infer fields from index structure (heuristic)
        var filterFields: Set<String> = []
        if !query.filters.isEmpty && !collection.secondaryIndexes.isEmpty {
            // Extract field names from index keys
            for indexName in collection.secondaryIndexes.keys {
                let fields = indexName.components(separatedBy: "+")
                filterFields.formUnion(fields)
            }
        }
        
        return filterFields
    }
    
    /// Calculate index selectivity (how many records match)
    /// For equality queries, assumes uniform distribution: ~1/uniqueKeys
    /// Uses heuristic: if index has many unique keys relative to records, assume low selectivity (equality)
    /// Otherwise, assume higher selectivity (range queries or low cardinality)
    private static func estimateSelectivity(
        indexName: String,
        collection: DynamicCollection,
        totalRecords: Int
    ) -> Double {
        let index = collection.secondaryIndexes[indexName]
        let uniqueKeys = index?.count ?? 0
        
        if uniqueKeys == 0 || totalRecords == 0 {
            return 1.0  // Full scan
        }
        
        // Heuristic: if uniqueKeys is close to totalRecords, it's likely a unique/near-unique index
        // For such indexes, equality queries have very low selectivity: ~1/uniqueKeys
        let uniquenessRatio = Double(uniqueKeys) / Double(totalRecords)
        
        if uniquenessRatio > 0.5 {
            // High uniqueness: assume equality query with low selectivity
            // Selectivity = 1/uniqueKeys (each unique value appears approximately once)
            let selectivity = 1.0 / Double(uniqueKeys)
            return max(0.001, min(0.1, selectivity))  // Clamp between 0.1% and 10%
        } else {
            // Lower uniqueness: could be range query or low-cardinality field
            // For equality on low-cardinality: still use 1/uniqueKeys
            // For range queries, we'd want higher selectivity, but we can't detect that
            // So we use a conservative estimate: assume some values have duplicates
            // Average records per key = totalRecords/uniqueKeys
            // For equality: selectivity = avgRecordsPerKey / totalRecords = 1/uniqueKeys
            let selectivity = 1.0 / Double(uniqueKeys)
            // But allow higher selectivity for very low cardinality (e.g., boolean fields)
            return max(0.01, min(0.5, selectivity))  // Clamp between 1% and 50%
        }
    }
    
    /// Optimize a query and return execution plan
    static func optimize(
        query: QueryBuilder,
        collection: DynamicCollection,
        estimatedRecordCount: Int
    ) -> OptimizedQueryPlan {
        
        // Analyze query to determine best plan
        let filters = query.filters
        let hasIndexes = !collection.secondaryIndexes.isEmpty
        let hasLimit = query.limitValue != nil
        let limitValue = query.limitValue ?? estimatedRecordCount
        
        // Check if any filter can use an index
        var bestIndex: String? = nil
        var bestIndexCost: Double = Double.infinity
        
        if hasIndexes {
            let filterFields = extractFilterFields(from: query, collection: collection)
            BlazeLogger.debug("🔍 [OPTIMIZER] Filter fields: \(filterFields), Available indexes: \(collection.secondaryIndexes.keys)")
            
            for (indexName, indexData) in collection.secondaryIndexes {
                let indexFields = indexName.components(separatedBy: "+")
                let uniqueKeys = indexData.count
                
                // Check if any filter fields match index fields
                let matches = !filterFields.isDisjoint(with: Set(indexFields))
                BlazeLogger.debug("🔍 [OPTIMIZER] Index '\(indexName)': fields=\(indexFields), uniqueKeys=\(uniqueKeys), matches=\(matches)")
                
                if matches {
                    // Calculate index scan cost
                    // Index lookup: O(log n) for B-tree traversal
                    // Result retrieval: O(m) where m = selectivity * n
                    let selectivity = estimateSelectivity(
                        indexName: indexName,
                        collection: collection,
                        totalRecords: estimatedRecordCount
                    )
                    let resultCount = Double(estimatedRecordCount) * selectivity
                    
                    // Index cost: log(n) for lookup + m for results
                    let indexCost = log2(Double(estimatedRecordCount)) + resultCount
                    
                    // Apply limit discount (if limit is small relative to resultCount, index is more beneficial)
                    // If limit is smaller than expected results, we only pay for limit items
                    // If limit is larger, we still pay for all results (limit doesn't help)
                    let adjustedCost: Double
                    if hasLimit && Double(limitValue) < resultCount {
                        // Limit is smaller than expected results - only pay for limit items
                        adjustedCost = log2(Double(estimatedRecordCount)) + Double(limitValue)
                    } else {
                        // No limit or limit is larger - pay full cost
                        adjustedCost = indexCost
                    }
                    
                    BlazeLogger.debug("🔍 [OPTIMIZER] Index '\(indexName)': selectivity=\(selectivity), resultCount=\(resultCount), indexCost=\(indexCost), adjustedCost=\(adjustedCost)")
                    
                    if adjustedCost < bestIndexCost {
                        bestIndexCost = adjustedCost
                        bestIndex = indexName
                        BlazeLogger.debug("🔍 [OPTIMIZER] New best index: '\(indexName)' with cost \(adjustedCost)")
                    }
                }
            }
        }
        
        // Calculate sequential scan cost
        // Sequential scan: O(n) to read all records
        // With limit: O(min(n, limit))
        let sequentialCost = hasLimit ? Double(min(estimatedRecordCount, limitValue)) : Double(estimatedRecordCount)
        
        BlazeLogger.debug("🔍 [OPTIMIZER] Sequential cost: \(sequentialCost), Best index: \(bestIndex ?? "none"), Best index cost: \(bestIndexCost), Threshold: \(sequentialCost * 0.8)")
        
        // Determine best plan
        if let index = bestIndex, bestIndexCost < sequentialCost * 0.8 {
            // Use index (only if 20% better than sequential)
            let selectivity = estimateSelectivity(
                indexName: index,
                collection: collection,
                totalRecords: estimatedRecordCount
            )
            return QueryPlan(
                useIndex: index,
                scanOrder: .index,
                estimatedCost: bestIndexCost,
                estimatedRows: Int(Double(estimatedRecordCount) * selectivity)
            )
        } else if estimatedRecordCount > 1000 && !hasLimit {
            // Use parallel scan for large datasets without limit
            return QueryPlan(
                useIndex: nil,
                scanOrder: .parallel,
                estimatedCost: Double(estimatedRecordCount) / 8.0,  // Divide by cores
                estimatedRows: estimatedRecordCount
            )
        } else {
            // Sequential scan
            // Estimate rows: if we have filters, assume moderate selectivity (30-50% for range queries)
            // If no filters, return all rows (or limit if specified)
            let estimatedRows: Int
            if !filters.isEmpty {
                // Heuristic: range queries typically match 30-50% of records
                // Use 40% as a conservative estimate for range queries
                let selectivity = 0.4
                estimatedRows = hasLimit ? min(limitValue, Int(Double(estimatedRecordCount) * selectivity)) : Int(Double(estimatedRecordCount) * selectivity)
            } else {
                // No filters: return all rows (or limit)
                estimatedRows = hasLimit ? limitValue : estimatedRecordCount
            }
            
            return QueryPlan(
                useIndex: nil,
                scanOrder: .sequential,
                estimatedCost: sequentialCost,
                estimatedRows: estimatedRows
            )
        }
    }
    
    /// Get estimated record count (would use statistics in production)
    static func estimateRecordCount(collection: DynamicCollection) -> Int {
        return collection.indexMap.count
    }
}

/// Extension to QueryBuilder for optimizer integration
extension QueryBuilder {
    
    /// Get optimized query plan
    func getOptimizedPlan(collection: DynamicCollection) -> OptimizedQueryPlan {
        let estimatedCount = QueryOptimizer.estimateRecordCount(collection: collection)
        return QueryOptimizer.optimize(
            query: self,
            collection: collection,
            estimatedRecordCount: estimatedCount
        )
    }
    
    /// Execute query using optimized plan
    func executeWithOptimizer() throws -> QueryResult {
        guard let collection = collection else {
            throw BlazeDBError.transactionFailed("Collection deallocated")
        }
        
        let plan = getOptimizedPlan(collection: collection)
        
        // Execute based on plan
        switch plan.scanOrder {
        case .index:
            // Use index-based execution
            if let indexName = plan.useIndex {
                return try executeWithIndex(indexName)
            }
            return try execute()
        case .parallel:
            // Use parallel execution (if available)
            // Note: executeParallel is async, so we'd need async version
            // For now, fall back to standard execution
            return try execute()
        case .sequential:
            // Use standard execution
            return try execute()
        }
    }
    
    /// Execute query using specific index
    private func executeWithIndex(_ indexName: String) throws -> QueryResult {
        // Index-based execution would go here
        // For now, fall back to standard execution
        return try execute()
    }
}

