//
//  GraphQueryTool.swift
//  BlazeMCP
//
//  Tool for running graph/aggregation queries
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for graph queries and aggregations
final class GraphQueryTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "graph_query",
            description: "Run aggregation queries for graphs/charts (count, sum, avg, min, max with grouping)"
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "xField": [
                "type": "string",
                "description": "Field to group by (X-axis)"
            ],
            "xDateBin": [
                "type": "string",
                "enum": ["hour", "day", "week", "month", "year"],
                "description": "Date binning for time-series (if xField is a date)"
            ],
            "yAggregation": [
                "type": "string",
                "enum": ["count", "sum", "avg", "min", "max"],
                "description": "Aggregation function for Y-axis"
            ],
            "yField": [
                "type": "string",
                "description": "Field to aggregate (required for sum/avg/min/max)"
            ],
            "filter": [
                "type": "object",
                "description": "Optional filter conditions"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of points",
                "minimum": 1,
                "maximum": 10000
            ]
        ]
    }
    
    override var requiredProperties: [String] {
        return ["xField", "yAggregation"]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        guard let xField = arguments["xField"] as? String,
              let yAggregation = arguments["yAggregation"] as? String else {
            throw MCPError.invalidArguments("'xField' and 'yAggregation' are required")
        }
        
        // Build graph query
        var graphQuery = database.graph()
        
        // Set X-axis
        if let dateBin = arguments["xDateBin"] as? String,
           let bin = BlazeDateBin(rawValue: dateBin) {
            graphQuery = graphQuery.x(xField, bin)
        } else {
            graphQuery = graphQuery.x(xField)
        }
        
        // Set Y-axis aggregation
        let yAgg: BlazeGraphAggregation
        switch yAggregation {
        case "count":
            yAgg = .count
        case "sum":
            guard let yField = arguments["yField"] as? String else {
                throw MCPError.invalidArguments("'yField' is required for sum aggregation")
            }
            yAgg = .sum(yField)
        case "avg":
            guard let yField = arguments["yField"] as? String else {
                throw MCPError.invalidArguments("'yField' is required for avg aggregation")
            }
            yAgg = .avg(yField)
        case "min":
            guard let yField = arguments["yField"] as? String else {
                throw MCPError.invalidArguments("'yField' is required for min aggregation")
            }
            yAgg = .min(yField)
        case "max":
            guard let yField = arguments["yField"] as? String else {
                throw MCPError.invalidArguments("'yField' is required for max aggregation")
            }
            yAgg = .max(yField)
        default:
            throw MCPError.invalidArguments("Unknown aggregation: \(yAggregation)")
        }
        
        graphQuery = graphQuery.y(yAgg)
        
        // Apply filter if provided
        if let filter = arguments["filter"] as? [String: Any] {
            if let field = filter["field"] as? String,
               let op = filter["op"] as? String,
               let value = filter["value"] {
                let blazeValue = try valueToBlazeDocumentField(value)
                if op == "eq" {
                    graphQuery = graphQuery.where(field, equals: blazeValue)
                } else {
                    // Use custom filter for other operators
                    graphQuery = graphQuery.filter { record in
                        guard let fieldValue = record.storage[field] else { return false }
                        switch op {
                        case "ne": 
                            return fieldValue != blazeValue
                        case "gt":
                            return self.compareFieldValues(fieldValue, blazeValue) > 0
                        case "gte":
                            return self.compareFieldValues(fieldValue, blazeValue) >= 0
                        case "lt":
                            return self.compareFieldValues(fieldValue, blazeValue) < 0
                        case "lte":
                            return self.compareFieldValues(fieldValue, blazeValue) <= 0
                        default: 
                            return false
                        }
                    }
                }
            }
        }
        
        // Apply limit (graph queries don't have direct limit, we'll limit after execution)
        let limit = arguments["limit"] as? Int
        
        // Execute graph query
        let points = try graphQuery.toPoints()
        
        // Apply limit if specified
        let limitedPoints = limit.map { Array(points.prefix($0)) } ?? points
        
        // Convert to JSON
        let jsonPoints = try limitedPoints.map { point in
            [
                "x": try valueToJSON(point.x),
                "y": try valueToJSON(point.y)
            ]
        }
        
        return [
            "points": jsonPoints,
            "count": jsonPoints.count,
            "description": "Graph query: \(yAggregation) of \(arguments["yField"] as? String ?? "records") grouped by \(xField)"
        ]
    }
    
    private func valueToBlazeDocumentField(_ value: Any?) throws -> BlazeDocumentField {
        guard let value = value else {
            return .null
        }
        
        if value is NSNull {
            return .null
        } else if let string = value as? String {
            return .string(string)
        } else if let int = value as? Int {
            return .int(int)
        } else if let double = value as? Double {
            return .double(double)
        } else if let bool = value as? Bool {
            return .bool(bool)
        } else {
            throw MCPError.invalidArguments("Unsupported value type for filter")
        }
    }
    
    private func compareFieldValues(_ a: BlazeDocumentField, _ b: BlazeDocumentField) -> Int {
        switch (a, b) {
        case (.int(let i1), .int(let i2)):
            return i1 < i2 ? -1 : (i1 > i2 ? 1 : 0)
        case (.double(let d1), .double(let d2)):
            return d1 < d2 ? -1 : (d1 > d2 ? 1 : 0)
        case (.string(let s1), .string(let s2)):
            return s1 < s2 ? -1 : (s1 > s2 ? 1 : 0)
        case (.date(let d1), .date(let d2)):
            return d1 < d2 ? -1 : (d1 > d2 ? 1 : 0)
        case (.int(let i), .double(let d)):
            let di = Double(i)
            return di < d ? -1 : (di > d ? 1 : 0)
        case (.double(let d), .int(let i)):
            let di = Double(i)
            return d < di ? -1 : (d > di ? 1 : 0)
        default:
            return 0
        }
    }
    
    private func valueToJSON(_ value: Any) throws -> Any {
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else if let uuid = value as? UUID {
            return uuid.uuidString
        } else {
            return value
        }
    }
}

