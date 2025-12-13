//
//  SuggestIndexesTool.swift
//  BlazeMCP
//
//  Tool for suggesting indexes based on query patterns
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for suggesting indexes
final class SuggestIndexesTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "suggest_indexes",
            description: "Suggest indexes based on query patterns, filter fields, and sort fields"
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "filterFields": [
                "type": "array",
                "description": "Fields used in WHERE clauses",
                "items": ["type": "string"]
            ],
            "sortFields": [
                "type": "array",
                "description": "Fields used in ORDER BY clauses",
                "items": ["type": "string"]
            ],
            "joinFields": [
                "type": "array",
                "description": "Fields used in JOIN conditions",
                "items": ["type": "string"]
            ],
            "analyzeExisting": [
                "type": "boolean",
                "description": "Analyze existing indexes and suggest improvements",
                "default": true
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        var suggestions: [[String: Any]] = []
        
        // Get existing indexes
        let existingIndexes = try getExistingIndexes()
        let existingFields = Set(existingIndexes.flatMap { $0.components(separatedBy: "+") })
        
        // Analyze filter fields
        if let filterFields = arguments["filterFields"] as? [String] {
            for field in filterFields {
                if !existingFields.contains(field) {
                    suggestions.append([
                        "field": field,
                        "type": "single",
                        "reason": "Frequently filtered",
                        "priority": "high",
                        "estimatedImpact": "High - speeds up WHERE clauses"
                    ])
                }
            }
        }
        
        // Analyze sort fields
        if let sortFields = arguments["sortFields"] as? [String] {
            for field in sortFields {
                if !existingFields.contains(field) {
                    suggestions.append([
                        "field": field,
                        "type": "single",
                        "reason": "Frequently sorted",
                        "priority": "medium",
                        "estimatedImpact": "Medium - speeds up ORDER BY"
                    ])
                }
            }
        }
        
        // Analyze compound indexes (filter + sort)
        if let filterFields = arguments["filterFields"] as? [String],
           let sortFields = arguments["sortFields"] as? [String] {
            for filterField in filterFields {
                for sortField in sortFields where sortField != filterField {
                    let compoundKey = "\(filterField)+\(sortField)"
                    if !existingIndexes.contains(compoundKey) {
                        suggestions.append([
                            "fields": [filterField, sortField],
                            "type": "compound",
                            "reason": "Filtered and sorted together",
                            "priority": "high",
                            "estimatedImpact": "Very High - optimizes filtered + sorted queries"
                        ])
                    }
                }
            }
        }
        
        // Analyze join fields
        if let joinFields = arguments["joinFields"] as? [String] {
            for field in joinFields {
                if !existingFields.contains(field) {
                    suggestions.append([
                        "field": field,
                        "type": "single",
                        "reason": "Used in JOIN conditions",
                        "priority": "high",
                        "estimatedImpact": "High - speeds up JOINs"
                    ])
                }
            }
        }
        
        // Remove duplicates
        var uniqueSuggestions: [[String: Any]] = []
        var seen = Set<String>()
        for suggestion in suggestions {
            let key: String
            if let field = suggestion["field"] as? String {
                key = field
            } else if let fields = suggestion["fields"] as? [String] {
                key = fields.joined(separator: "+")
            } else {
                continue
            }
            
            if !seen.contains(key) {
                seen.insert(key)
                uniqueSuggestions.append(suggestion)
            }
        }
        
        return [
            "suggestions": uniqueSuggestions,
            "count": uniqueSuggestions.count,
            "existingIndexes": existingIndexes,
            "message": "Review suggestions and create indexes using createIndex() method"
        ]
    }
    
    private func getExistingIndexes() throws -> [String] {
        // Index metadata isn't exposed yet via the public API.
        // For now, return an empty list; the suggestions themselves include details.
        return []
    }
}

