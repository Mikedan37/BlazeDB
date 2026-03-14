//
//  QueryPlanner+Explain.swift
//  BlazeDB
//
//  EXPLAIN API for query plans
//
import Foundation

/// Human-readable query plan explanation
@available(*, deprecated, message: "Use DetailedQueryPlan from QueryBuilder.explain() instead.")
public struct QueryPlanExplanation {
    public let strategy: String
    public let estimatedCost: Double
    public let estimatedRows: Int
    public let executionOrder: [String]
    public let indexesUsed: [String]
    public let notes: [String]

    public var description: String {
        var lines: [String] = []
        lines.append("Query Plan:")
        lines.append("  Strategy: \(strategy)")
        lines.append("  Estimated Cost: \(String(format: "%.2f", estimatedCost))")
        lines.append("  Estimated Rows: \(estimatedRows)")
        lines.append("  Execution Order: \(executionOrder.joined(separator: " → "))")
        if !indexesUsed.isEmpty {
            lines.append("  Indexes Used: \(indexesUsed.joined(separator: ", "))")
        }
        if !notes.isEmpty {
            lines.append("  Notes:")
            for note in notes {
                lines.append("    - \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension QueryPlanner {
    
    /// Explain a query plan
    @available(*, deprecated, message: "Use QueryBuilder.explain() instead, which returns a DetailedQueryPlan.")
    static func explain(
        query: QueryBuilder,
        collection: DynamicCollection
    ) throws -> QueryPlanExplanation {
        let plan = try plan(query: query, collection: collection)
        
        var strategy: String
        var indexesUsed: [String] = []
        var notes: [String] = []
        
        switch plan.strategy {
        case .spatialIndex(let latField, let lonField):
            strategy = "Spatial Index (R-tree)"
            indexesUsed.append("spatial(\(latField), \(lonField))")
            notes.append("Using R-tree spatial index for location queries")
            
        case .vectorIndex(let field, _):
            strategy = "Vector Search (Cosine Similarity)"
            indexesUsed.append("vector(\(field))")
            notes.append("Planner selected vector strategy (advisory)")
            notes.append("Vector execution currently falls back to standard query execution")
            
        case .fullTextIndex(let field, let query):
            strategy = "Full-Text Search"
            indexesUsed.append("fulltext(\(field))")
            notes.append("Searching for: '\(query)'")
            notes.append("Planner full-text strategy is advisory; execution is handled by standard query paths")
            
        case .regularIndex(let name):
            strategy = "B-Tree Index"
            indexesUsed.append(name)
            notes.append("Planner selected secondary index (advisory)")
            notes.append("Execution may still fall back to table-scan code paths for some query shapes")
            
        case .sequential:
            strategy = "Sequential Scan"
            notes.append("No suitable index found, scanning all records")
            
        case .hybrid(let spatial, let vector, let fullText):
            strategy = "Hybrid Query"
            if spatial { indexesUsed.append("spatial") }
            if vector { indexesUsed.append("vector") }
            if fullText { indexesUsed.append("fulltext") }
            notes.append("Combining multiple index types (advisory plan)")
            notes.append("Hybrid/vector/full-text execution currently relies on fallback execution paths")
        }
        
        return QueryPlanExplanation(
            strategy: strategy,
            estimatedCost: plan.estimatedCost,
            estimatedRows: plan.estimatedRows,
            executionOrder: plan.executionOrder,
            indexesUsed: indexesUsed,
            notes: notes
        )
    }
}

extension BlazeDBClient {
    
    /// Explain a query plan
    ///
    /// Example:
    /// ```swift
    /// let explanation = try db.explain {
    ///     db.query()
    ///         .where("status", equals: .string("open"))
    ///         .withinRadius(latitude: 37.7749, longitude: -122.4194, radiusMeters: 1000)
    /// }
    /// print(explanation.description)
    /// ```
    @available(*, deprecated, message: "Use QueryBuilder.explain() instead, which returns a DetailedQueryPlan.")
    public func explain(_ queryBuilder: () throws -> QueryBuilder) throws -> QueryPlanExplanation {
        let query = try queryBuilder()
        guard let collection = query.collection else {
            throw BlazeDBError.invalidData(reason: "Query builder's collection has been deallocated. Recreate the query from a live database.")
        }
        return try QueryPlanner.explain(query: query, collection: collection)
    }
}

