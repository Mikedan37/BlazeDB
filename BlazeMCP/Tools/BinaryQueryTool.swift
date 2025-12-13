//
//  BinaryQueryTool.swift
//  BlazeMCP
//
//  Tool for binary query/result support (Base64 encoded BlazeBinary)
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for binary query/result support
final class BinaryQueryTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "binary_query",
            description: "Execute query using Base64-encoded BlazeBinary format (faster, but requires BlazeBinary encoding)"
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "binaryQuery": [
                "type": "string",
                "description": "Base64-encoded BlazeBinary query document"
            ],
            "returnBinary": [
                "type": "boolean",
                "description": "Return results as Base64-encoded BlazeBinary (default: false, returns JSON)",
                "default": false
            ]
        ]
    }
    
    override var requiredProperties: [String] {
        return ["binaryQuery"]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        guard let base64Query = arguments["binaryQuery"] as? String,
              let queryData = Data(base64Encoded: base64Query) else {
            throw MCPError.invalidArguments("'binaryQuery' must be valid Base64-encoded data")
        }
        
        // Decode BlazeBinary query
        // Note: This is a simplified implementation
        // In a full implementation, we'd have a BlazeBinary query format
        // For now, we'll decode as a record and extract query parameters
        
        // Parse query from BlazeBinary (simplified - would need proper query format)
        let record = try BlazeBinaryDecoder.decode(queryData)
        
        // Extract query parameters from record
        guard let filterField = record.storage["filterField"]?.stringValue,
              let filterValue = record.storage["filterValue"] else {
            throw MCPError.invalidArguments("Binary query must contain 'filterField' and 'filterValue'")
        }
        
        // Execute query (RLS enforced)
        let query = database.query()
            .where(filterField, equals: filterValue)
        
        let result = try query.execute()
        let records = try result.records
        
        // Return results
        let returnBinary = arguments["returnBinary"] as? Bool ?? false
        
        if returnBinary {
            // Encode results as BlazeBinary
            var binaryResults: [String] = []
            for record in records {
                let encoded = try BlazeBinaryEncoder.encode(record)
                binaryResults.append(encoded.base64EncodedString())
            }
            
            return [
                "results": binaryResults,
                "format": "blazebinary",
                "count": binaryResults.count
            ]
        } else {
            // Return as JSON
            let jsonRecords = try records.map { record in
                try recordToJSON(record)
            }
            
            return [
                "results": jsonRecords,
                "format": "json",
                "count": jsonRecords.count
            ]
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
            return vec
        case .null:
            return NSNull()
        }
    }
}

