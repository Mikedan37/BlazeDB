//
//  MoveBeforeTool.swift
//  BlazeMCP
//
//  MCP tool for moving a record before another record (ordering index)
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for moving a record before another record (only modifies orderingIndex)
final class MoveBeforeTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "move_before",
            description: "Move a record before another record (only modifies orderingIndex). Requires ordering to be enabled."
        )
    }
    
    override var requiredProperties: [String] {
        return ["recordId", "beforeId"]
    }
    
    override var toolProperties: [String: Any] {
        return [
            "recordId": [
                "type": "string",
                "description": "UUID of the record to move"
            ],
            "beforeId": [
                "type": "string",
                "description": "UUID of the record to move before"
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        BlazeLogger.info("MoveBeforeTool.execute: move_before requested")
        
        // Check if ordering is enabled
        guard database.isOrderingEnabled() else {
            BlazeLogger.error("MoveBeforeTool.execute: ordering not enabled")
            throw MCPError.invalidOperation("Ordering not enabled. Call enableOrdering() first.")
        }
        
        guard let recordIdString = arguments["recordId"] as? String,
              let recordId = UUID(uuidString: recordIdString) else {
            throw MCPError.invalidArguments("'recordId' must be a valid UUID string")
        }
        
        guard let beforeIdString = arguments["beforeId"] as? String,
              let beforeId = UUID(uuidString: beforeIdString) else {
            throw MCPError.invalidArguments("'beforeId' must be a valid UUID string")
        }
        
        // Move record
        try database.moveBefore(recordId: recordId, beforeId: beforeId)
        
        BlazeLogger.info("MoveBeforeTool.execute: successfully moved \(recordIdString) before \(beforeIdString)")
        
        return [
            "success": true,
            "message": "Record moved before target",
            "recordId": recordIdString,
            "beforeId": beforeIdString
        ]
    }
}

