//
//  QueryStatistics.swift
//  BlazeDB
//
//  Statistics collection for query planner
//
//  Created by Auto on 1/XX/25.
//

import Foundation

/// Field statistics for cost-based optimization
public struct FieldStatistics {
    public let distinctCount: Int
    public let nullCount: Int
    public let minValue: BlazeDocumentField?
    public let maxValue: BlazeDocumentField?
    
    public init(distinctCount: Int, nullCount: Int, minValue: BlazeDocumentField? = nil, maxValue: BlazeDocumentField? = nil) {
        self.distinctCount = distinctCount
        self.nullCount = nullCount
        self.minValue = minValue
        self.maxValue = maxValue
    }
    
    /// Calculate selectivity (how selective is this field)
    public func selectivity(totalRows: Int) -> Double {
        guard totalRows > 0 else { return 1.0 }
        return Double(distinctCount) / Double(totalRows)
    }
}

/// Index statistics
public struct IndexStatistics {
    public let indexName: String
    public let usageCount: Int
    public let averageSelectivity: Double
    public let averageExecutionTime: TimeInterval
    
    public init(indexName: String, usageCount: Int = 0, averageSelectivity: Double = 0.5, averageExecutionTime: TimeInterval = 0.0) {
        self.indexName = indexName
        self.usageCount = usageCount
        self.averageSelectivity = averageSelectivity
        self.averageExecutionTime = averageExecutionTime
    }
}

/// Collection statistics for query planning
public struct CollectionStatistics {
    public let totalRows: Int
    public let fieldStats: [String: FieldStatistics]
    public let indexStats: [String: IndexStatistics]
    
    public init(totalRows: Int, fieldStats: [String: FieldStatistics] = [:], indexStats: [String: IndexStatistics] = [:]) {
        self.totalRows = totalRows
        self.fieldStats = fieldStats
        self.indexStats = indexStats
    }
}

/// Statistics collector for query optimization (SQLite-style cost model)
public class StatisticsCollector {
    
    /// Collect statistics for a collection
    static func collect(collection: DynamicCollection) -> CollectionStatistics {
        // Access collection state in a thread-safe manner
        return collection.queue.sync {
            let totalRows = collection.indexMap.count
            
            // Collect field statistics (simplified - would sample in production)
            let fieldStats: [String: FieldStatistics] = [:]
            
            // Collect index statistics
            var indexStats: [String: IndexStatistics] = [:]
            for (indexName, indexData) in collection.secondaryIndexes {
                // Calculate average selectivity (distinct keys / total rows)
                let distinctKeys = indexData.count
                let avgSelectivity = totalRows > 0 ? Double(distinctKeys) / Double(totalRows) : 0.5
                indexStats[indexName] = IndexStatistics(
                    indexName: indexName,
                    usageCount: 0,
                    averageSelectivity: avgSelectivity,
                    averageExecutionTime: 0.0
                )
            }
            
            // Spatial index stats
            #if !BLAZEDB_LINUX_CORE
            if let spatialIndex = collection.spatialIndex {
                _ = spatialIndex.getStats()
                indexStats["spatial"] = IndexStatistics(
                    indexName: "spatial",
                    usageCount: 0,
                    averageSelectivity: 0.1, // Spatial queries typically return 10% of data
                    averageExecutionTime: 0.0
                )
            }
            #endif
            
            return CollectionStatistics(
                totalRows: totalRows,
                fieldStats: fieldStats,
                indexStats: indexStats
            )
        }
    }
    
    /// Calculate cost for full table scan
    static func costFullScan(rowCount: Int) -> Double {
        // Base cost: 1.0 per row (linear scan)
        return Double(rowCount) * 1.0
    }
    
    /// Calculate cost for index lookup
    static func costIndexLookup(rowCount: Int, selectivity: Double, indexSize: Int = 0) -> Double {
        // Index cost: log(n) traversal + selectivity * rows to scan
        let logCost = log2(Double(max(rowCount, 1))) * 2.0  // B-tree traversal
        let scanCost = Double(rowCount) * selectivity * 1.0  // Rows to scan
        return logCost + scanCost
    }
    
    /// Calculate cost for spatial index query
    static func costSpatialQuery(rowCount: Int, estimatedResults: Int) -> Double {
        // R-tree cost: log(n) + results to process
        let logCost = log2(Double(max(rowCount, 1))) * 1.5  // R-tree traversal
        let resultCost = Double(estimatedResults) * 0.5  // Distance calculations
        return logCost + resultCost
    }
    
    /// Calculate cost for vector search
    static func costVectorSearch(rowCount: Int, vectorLimit: Int) -> Double {
        // Brute-force cosine similarity: O(n) for now
        // Future: O(log n) with vector index
        return Double(min(rowCount, vectorLimit * 10)) * 2.0  // 2x cost for similarity calc
    }
    
    /// Calculate cost for full-text search
    static func costFullTextSearch(rowCount: Int, estimatedResults: Int) -> Double {
        // Inverted index: log(n) + results
        let logCost = log2(Double(max(rowCount, 1))) * 1.2
        let resultCost = Double(estimatedResults) * 0.3
        return logCost + resultCost
    }
    
    /// Calculate cost for hybrid query (multiple indexes)
    static func costHybrid(
        spatialCost: Double?,
        vectorCost: Double?,
        fullTextCost: Double?,
        intersectionPenalty: Double = 5.0
    ) -> Double {
        var costs: [Double] = []
        if let spatial = spatialCost { costs.append(spatial) }
        if let vector = vectorCost { costs.append(vector) }
        if let fullText = fullTextCost { costs.append(fullText) }
        
        guard !costs.isEmpty else { return 1000.0 }  // Fallback: expensive
        
        // Hybrid cost: sum of index costs + intersection penalty
        let indexCost = costs.reduce(0, +)
        return indexCost + intersectionPenalty
    }
    
    /// Update index usage statistics
    static func recordIndexUsage(indexName: String, selectivity: Double, executionTime: TimeInterval) {
        // In production, would update persistent statistics
        BlazeLogger.debug("Index '\(indexName)' used: selectivity=\(String(format: "%.2f", selectivity)), time=\(String(format: "%.2f", executionTime * 1000))ms")
    }
}

