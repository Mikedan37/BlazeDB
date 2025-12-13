//
//  MoveToIndexTool.swift
//  BlazeMCP
//
//  MCP tool for setting a specific ordering index for a record
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for setting a specific ordering index for a record
final class MoveToIndexTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "move_to_index",
            description: "Set a specific ordering index for a record. Requires ordering to be enabled."
        )
    }
    
    override var requiredProperties: [String] {
        return ["recordId", "index"]
    }
    
    override var toolProperties: [String: Any] {
        return [
            "recordId": [
                "type": "string",
                "description": "UUID of the record to update"
            ],
            "index": [
                "type": "number",
                "description": "Ordering index value (Double)"
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        BlazeLogger.info("MoveToIndexTool.execute: move_to_index requested")
        
        // Check if ordering is enabled
        guard database.isOrderingEnabled() else {
            BlazeLogger.error("MoveToIndexTool.execute: ordering not enabled")
            throw MCPError.invalidOperation("Ordering not enabled. Call enableOrdering() first.")
        }
        
        guard let recordIdString = arguments["recordId"] as? String,
              let recordId = UUID(uuidString: recordIdString) else {
            throw MCPError.invalidArguments("'recordId' must be a valid UUID string")
        }
        
        guard let index = arguments["index"] as? Double else {
            throw MCPError.invalidArguments("'index' must be a number (Double)")
        }
        
        // Set index
        try database.moveToIndex(recordId: recordId, index: index)
        
        BlazeLogger.info("MoveToIndexTool.execute: successfully set \(recordIdString) to index \(index)")
        
        return [
            "success": true,
            "message": "Ordering index set",
            "recordId": recordIdString,
            "index": index
        ]
    }
}

