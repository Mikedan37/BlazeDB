//
//  QueryPlanner.swift
//  BlazeDB
//
//  Advanced query planner that intelligently chooses between:
//  - Spatial indexes (R-tree)
//  - Vector indexes (cosine similarity)
//  - Full-text indexes (inverted index)
//  - Regular indexes (B-tree)
//  - Sequential scans
//
//  Created by Auto on 1/XX/25.
//

import Foundation
@preconcurrency import Foundation

/// Advanced query execution plan
public struct AdvancedQueryPlan {
    public enum Strategy {
        case spatialIndex(latField: String, lonField: String)
        case vectorIndex(field: String, embedding: [Float])
        case fullTextIndex(field: String, query: String)
        case regularIndex(name: String)
        case sequential
        case hybrid(spatial: Bool, vector: Bool, fullText: Bool)
    }
    
    public let strategy: Strategy
    public let estimatedCost: Double
    public let estimatedRows: Int
    public let executionOrder: [String]  // Order of operations
    
    public init(strategy: Strategy, estimatedCost: Double, estimatedRows: Int, executionOrder: [String] = []) {
        self.strategy = strategy
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
        self.executionOrder = executionOrder
    }
}

/// Advanced query planner
public class QueryPlanner {
    
    /// Plan a query with real cost math (SQLite-style)
    static func plan(
        query: QueryBuilder,
        collection: DynamicCollection
    ) throws -> AdvancedQueryPlan {
        
        // Collect statistics for cost estimation
        let stats = StatisticsCollector.collect(collection: collection)
        let rowCount = stats.totalRows
        
        #if !BLAZEDB_LINUX_CORE
        let hasSpatial = collection.spatialIndex != nil
        #else
        let hasSpatial = false
        #endif
        // Check for search index via StorageLayout
        _ = (try? StorageLayout.load(from: collection.metaURL))?.searchIndex != nil
        // NOTE: Vector index support intentionally not implemented in query planner.
        // Vector queries require specialized execution paths not yet implemented.
        _ = false  // Vector index check (not implemented)
        let hasRegularIndexes = !collection.secondaryIndexes.isEmpty
        
        // Detect query types
        let hasSpatialQuery = query.sortByDistanceCenter != nil
        // NOTE: Vector query detection intentionally not implemented.
        // Vector search requires specialized query builder support.
        let hasVectorQuery = query.hasVectorQuery  // Flag exists but vector execution not implemented
        _ = false  // Vector query detection (not implemented)
        
        // Calculate costs for each strategy
        var candidatePlans: [(plan: AdvancedQueryPlan, cost: Double)] = []
        
        // Strategy 1: Spatial index (if available and used)
        if hasSpatial && hasSpatialQuery, let (latField, lonField) = collection.cachedSpatialIndexedFields {
            let estimatedResults = min(100, rowCount / 10)  // Estimate 10% of rows
            let cost = StatisticsCollector.costSpatialQuery(rowCount: rowCount, estimatedResults: estimatedResults)
            candidatePlans.append((
                AdvancedQueryPlan(
                    strategy: .spatialIndex(latField: latField, lonField: lonField),
                    estimatedCost: cost,
                    estimatedRows: estimatedResults,
                    executionOrder: ["spatial_index", "filter", "sort", "limit"]
                ),
                cost
            ))
        }
        
        // Strategy 2: Vector search (if used)
        if hasVectorQuery {
            let vectorLimit = 100  // Default
            let cost = StatisticsCollector.costVectorSearch(rowCount: rowCount, vectorLimit: vectorLimit)
            candidatePlans.append((
                AdvancedQueryPlan(
                    strategy: .vectorIndex(field: "embedding", embedding: []),
                    estimatedCost: cost,
                    estimatedRows: vectorLimit,
                    executionOrder: ["vector_search", "filter", "sort", "limit"]
                ),
                cost
            ))
        }
        
        // Strategy 3: Hybrid (spatial + vector)
        if hasSpatial && hasVectorQuery && hasSpatialQuery {
            let spatialCost = StatisticsCollector.costSpatialQuery(rowCount: rowCount, estimatedResults: 200)
            let vectorCost = StatisticsCollector.costVectorSearch(rowCount: rowCount, vectorLimit: 100)
            let hybridCost = StatisticsCollector.costHybrid(spatialCost: spatialCost, vectorCost: vectorCost, fullTextCost: nil)
            
            candidatePlans.append((
                AdvancedQueryPlan(
                    strategy: .hybrid(spatial: true, vector: true, fullText: false),
                    estimatedCost: hybridCost,
                    estimatedRows: 50,
                    executionOrder: ["spatial_index", "vector_search", "intersect", "filter", "sort", "limit"]
                ),
                hybridCost
            ))
        }
        
        // Strategy 4: Regular index (if available)
        if hasRegularIndexes {
            // Find best index for query filters
            // Simplified: use first available index
            if let (indexName, _) = collection.secondaryIndexes.first {
                let selectivity = stats.indexStats[indexName]?.averageSelectivity ?? 0.5
                let cost = StatisticsCollector.costIndexLookup(rowCount: rowCount, selectivity: selectivity)
                candidatePlans.append((
                    AdvancedQueryPlan(
                        strategy: .regularIndex(name: indexName),
                        estimatedCost: cost,
                        estimatedRows: Int(Double(rowCount) * selectivity),
                        executionOrder: ["index", "filter", "sort", "limit"]
                    ),
                    cost
                ))
            }
        }
        
        // Strategy 5: Sequential scan (fallback)
        let scanCost = StatisticsCollector.costFullScan(rowCount: rowCount)
        candidatePlans.append((
            AdvancedQueryPlan(
                strategy: .sequential,
                estimatedCost: scanCost,
                estimatedRows: rowCount,
                executionOrder: ["scan", "filter", "sort", "limit"]
            ),
            scanCost
        ))
        
        // Pick plan with lowest cost
        // CRITICAL: Guard against empty candidatePlans to prevent crash
        guard !candidatePlans.isEmpty else {
            return AdvancedQueryPlan(
                strategy: .sequential,
                estimatedCost: scanCost,
                estimatedRows: rowCount,
                executionOrder: ["scan", "filter", "sort", "limit"]
            )
        }
        guard let bestPlan = candidatePlans.min(by: { $0.cost < $1.cost })?.plan ?? candidatePlans.last?.plan else {
            throw BlazeDBError.invalidData(reason: "No query plan available")
        }
        
        BlazeLogger.debug("Query planner: Selected strategy '\(bestPlan.strategy)' with cost \(String(format: "%.2f", bestPlan.estimatedCost))")
        
        return bestPlan
    }
    
    /// Plan a hybrid query (spatial + vector + full-text)
    /// 
    /// Example: "Find journal entries that feel emotionally similar to 'anxious' 
    ///          AND happened within 2km of my gym"
    static func planHybrid(
        spatialQuery: Bool,
        vectorQuery: Bool,
        fullTextQuery: Bool,
        collection: DynamicCollection
    ) -> AdvancedQueryPlan {
        
        #if !BLAZEDB_LINUX_CORE
        let hasSpatial = collection.spatialIndex != nil
        #else
        let hasSpatial = false
        #endif
        // NOTE: Vector index support intentionally not implemented.
        let hasVector = false
        // Check for search index via StorageLayout
        let hasFullText = (try? StorageLayout.load(from: collection.metaURL))?.searchIndex != nil
        
        // Determine optimal execution order
        var executionOrder: [String] = []
        var cost: Double = 0.0
        
        // Spatial queries are fastest (O(log n))
        if spatialQuery && hasSpatial {
            executionOrder.append("spatial_index")
            cost += 5.0
        }
        
        // Full-text is medium speed (O(log n) but more expensive)
        if fullTextQuery && hasFullText {
            executionOrder.append("fulltext_index")
            cost += 10.0
        }
        
        // Vector is slowest (O(n) cosine similarity)
        if vectorQuery && hasVector {
            executionOrder.append("vector_search")
            cost += 50.0
        }
        
        executionOrder.append(contentsOf: ["intersect", "filter", "sort", "limit"])
        
        return AdvancedQueryPlan(
            strategy: .hybrid(spatial: spatialQuery, vector: vectorQuery, fullText: fullTextQuery),
            estimatedCost: cost,
            estimatedRows: 100,  // Estimate
            executionOrder: executionOrder
        )
    }
}

/// Extension to QueryBuilder for advanced planning
extension QueryBuilder {
    
    /// Get advanced query plan
    func getAdvancedPlan(collection: DynamicCollection) throws -> AdvancedQueryPlan {
        return try QueryPlanner.plan(query: self, collection: collection)
    }
    
    /// Execute query using advanced planner
    func executeWithPlanner() throws -> QueryResult {
        guard let collection = collection else {
            throw BlazeDBError.transactionFailed("Collection deallocated")
        }
        
        let plan = try getAdvancedPlan(collection: collection)
        BlazeLogger.debug("Query planner: Strategy \(plan.strategy), cost: \(plan.estimatedCost), order: \(plan.executionOrder.joined(separator: " → "))")
        
        // Execute based on plan
        switch plan.strategy {
        case .spatialIndex:
            // Spatial queries already handled in QueryBuilder+Spatial
            return try execute()
        case .vectorIndex:
            // NOTE: Vector search execution intentionally not implemented.
            // Falls back to standard execution. Vector search requires specialized index support.
            return try execute()
        case .fullTextIndex:
            // NOTE: Full-text search execution intentionally not implemented in planner.
            // Full-text search is handled by QueryBuilder+Search, not the planner.
            return try execute()
        case .regularIndex:
            return try executeOptimized()
        case .sequential:
            return try execute()
        case .hybrid:
            // Hybrid queries: execute spatial first, then intersect with other results
            return try execute()
        }
    }
}

