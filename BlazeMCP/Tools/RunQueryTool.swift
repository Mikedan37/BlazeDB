//
//  RunQueryTool.swift
//  BlazeMCP
//
//  Tool for running queries on BlazeDB
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for running queries
final class RunQueryTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "run_query",
            description: "Run a query on the database with filters, sorting, and pagination"
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "filter": [
                "type": "object",
                "description": "Filter conditions (field, op, value)",
                "properties": [
                    "field": ["type": "string"],
                    "op": ["type": "string", "enum": ["eq", "ne", "gt", "gte", "lt", "lte", "contains", "in", "nil", "notNil"]],
                    "value": ["description": "Value to compare (type depends on field)"]
                ]
            ],
            "filters": [
                "type": "array",
                "description": "Multiple filter conditions (AND logic)",
                "items": ["type": "object"]
            ],
            "sort": [
                "type": "array",
                "description": "Sort specifications",
                "items": [
                    "type": "object",
                    "properties": [
                        "field": ["type": "string"],
                        "direction": ["type": "string", "enum": ["asc", "desc"]]
                    ]
                ]
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of results",
                "minimum": 1,
                "maximum": 10000
            ],
            "offset": [
                "type": "integer",
                "description": "Number of results to skip",
                "minimum": 0
            ],
            "project": [
                "type": "array",
                "description": "Fields to include in results (field projection)",
                "items": ["type": "string"]
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        var query = database.query()
        
        // Apply filters
        if let filter = arguments["filter"] as? [String: Any] {
            try applyFilter(filter, to: &query)
        }
        
        if let filters = arguments["filters"] as? [[String: Any]] {
            for filter in filters {
                try applyFilter(filter, to: &query)
            }
        }
        
        // Apply sorting
        if let sort = arguments["sort"] as? [[String: Any]] {
            for sortSpec in sort {
                guard let field = sortSpec["field"] as? String,
                      let direction = sortSpec["direction"] as? String else {
                    continue
                }
                query = query.orderBy(field, descending: direction == "desc")
            }
        }
        
        // Apply limit
        if let limit = arguments["limit"] as? Int {
            query = query.limit(limit)
        }
        
        // Apply offset
        if let offset = arguments["offset"] as? Int {
            query = query.offset(offset)
        }
        
        // Apply projection
        if let project = arguments["project"] as? [String] {
            query = query.project(project)
        }
        
        // Execute query
        let result = try query.execute()
        let records = try result.records
        
        // Convert to JSON
        let jsonRecords = try records.map { record in
            try recordToJSON(record)
        }
        
        return [
            "records": jsonRecords,
            "count": jsonRecords.count,
            "hasMore": (arguments["limit"] as? Int ?? 0) > 0 && jsonRecords.count == (arguments["limit"] as? Int ?? 0)
        ]
    }
    
    private func applyFilter(_ filter: [String: Any], to query: inout QueryBuilder) throws {
        guard let field = filter["field"] as? String,
              let op = filter["op"] as? String else {
            throw MCPError.invalidArguments("Filter must have 'field' and 'op'")
        }
        
        let value = filter["value"]
        let blazeValue = try valueToBlazeDocumentField(value)
        
        switch op {
        case "eq":
            query = query.where(field, equals: blazeValue)
        case "ne":
            // Not equals: use custom filter
            query = query.where { record in
                guard let fieldValue = record.storage[field] else { return true }
                return fieldValue != blazeValue
            }
        case "gt":
            query = query.where(field, greaterThan: blazeValue)
        case "gte":
            query = query.where(field, greaterThanOrEqual: blazeValue)
        case "lt":
            query = query.where(field, lessThan: blazeValue)
        case "lte":
            query = query.where(field, lessThanOrEqual: blazeValue)
        case "contains":
            if case .string(let str) = blazeValue {
                query = query.where(field, contains: str)
            } else {
                throw MCPError.invalidArguments("'contains' requires string value")
            }
        case "in":
            if let array = value as? [Any] {
                let blazeArray = try array.map { try valueToBlazeDocumentField($0) }
                query = query.where(field, in: blazeArray)
            } else {
                throw MCPError.invalidArguments("'in' requires array value")
            }
        case "nil":
            query = query.whereNil(field)
        case "notNil":
            query = query.whereNotNil(field)
        default:
            throw MCPError.invalidArguments("Unknown operator: \(op)")
        }
    }
    
    private func valueToBlazeDocumentField(_ value: Any?) throws -> BlazeDocumentField {
        guard let value = value else {
            return .null
        }
        
        if let string = value as? String {
            return .string(string)
        } else if let int = value as? Int {
            return .int(int)
        } else if let double = value as? Double {
            return .double(double)
        } else if let bool = value as? Bool {
            return .bool(bool)
        } else if let uuidString = value as? String, let uuid = UUID(uuidString: uuidString) {
            return .uuid(uuid)
        } else if let dateString = value as? String, let date = ISO8601DateFormatter().date(from: dateString) {
            return .date(date)
        } else if let base64 = value as? String, let data = Data(base64Encoded: base64) {
            return .data(data)
        } else {
            throw MCPError.invalidArguments("Unsupported value type: \(type(of: value))")
        }
    }
    
    private func recordToJSON(_ record: BlazeDataRecord) throws -> [String: Any] {
        var json: [String: Any] = [:]
        for (key, value) in record.storage {
            json[key] = try valueToJSON(value)
        }
        return json
    }
    
    private func valueToJSON(_ value: BlazeDocumentField) throws -> Any {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .bool(let b):
            return b
        case .uuid(let u):
            return u.uuidString
        case .date(let d):
            return ISO8601DateFormatter().string(from: d)
        case .data(let d):
            return d.base64EncodedString()
        case .array(let a):
            return try a.map { try valueToJSON($0) }
        case .dictionary(let d):
            var dict: [String: Any] = [:]
            for (k, v) in d {
                dict[k] = try valueToJSON(v)
            }
            return dict
        case .vector(let vec):
            return vec  // Return as array of doubles
        case .null:
            return NSNull()
        }
    }
}

