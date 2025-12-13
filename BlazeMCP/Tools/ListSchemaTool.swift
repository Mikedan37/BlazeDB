//
//  ListSchemaTool.swift
//  BlazeMCP
//
//  Tool for listing database schema (models, fields, indexes, relationships)
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for listing database schema
final class ListSchemaTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "list_schema",
            description: "List database schema including models, fields, types, indexes, and relationships"
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "includeSamples": [
                "type": "boolean",
                "description": "Include sample values for type inference (default: false)",
                "default": false
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        // Get schema info from database monitoring snapshot
        let snapshot = try database.getMonitoringSnapshot()
        let schemaInfo = snapshot.schema
        
        // Get indexes
        let indexes = try getIndexes()
        
        // Build models array
        var models: [[String: Any]] = []
        
        // Group fields by inferred model (for now, use single "Record" model)
        var fields: [[String: Any]] = []
        
        // Check if ordering is enabled
        let orderingEnabled = database.isOrderingEnabled()
        // Default field name is "orderingIndex" (can't access internal collection, but this is the default)
        let orderingFieldName = orderingEnabled ? "orderingIndex" : nil
        
        for (fieldName, fieldType) in schemaInfo.inferredTypes {
            var fieldInfo: [String: Any] = [
                "name": fieldName,
                "type": fieldType,
                "isCommon": schemaInfo.commonFields.contains(fieldName)
            ]
            
            // Mark ordering field if enabled
            if orderingEnabled && fieldName == orderingFieldName {
                fieldInfo["isOrderIndex"] = true
            }
            
            fields.append(fieldInfo)
        }
        
        models.append([
            "name": "Record",
            "fields": fields,
            "totalFields": schemaInfo.totalFields
        ])
        
        // Build response
        var result: [String: Any] = [
            "models": models,
            "indexes": indexes,
            "totalFields": schemaInfo.totalFields,
            "commonFields": schemaInfo.commonFields,
            "customFields": schemaInfo.customFields
        ]
        
        // Include sample values if requested
        if let includeSamples = arguments["includeSamples"] as? Bool, includeSamples {
            result["samples"] = try getSampleValues(limit: 5)
        }
        
        return result
    }
    
    private func getIndexes() throws -> [[String: Any]] {
        // Index metadata is not exposed through the public API yet.
        // Return an empty list; suggestions will focus on field usage stats instead.
        return []
    }
    
    private func getSampleValues(limit: Int) throws -> [[String: Any]] {
        let allRecords = try database.fetchAll()
        let samples = Array(allRecords.prefix(limit))
        
        return try samples.map { record in
            var sample: [String: Any] = [:]
            for (key, value) in record.storage {
                sample[key] = try valueToJSON(value)
            }
            return sample
        }
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
        case .vector(let v):
            return v
        case .null:
            return NSNull()
        }
    }
}

