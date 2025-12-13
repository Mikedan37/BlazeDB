//
//  MoveAfterTool.swift
//  BlazeMCP
//
//  MCP tool for moving a record after another record (ordering index)
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for moving a record after another record (only modifies orderingIndex)
final class MoveAfterTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "move_after",
            description: "Move a record after another record (only modifies orderingIndex). Requires ordering to be enabled."
        )
    }
    
    override var requiredProperties: [String] {
        return ["recordId", "afterId"]
    }
    
    override var toolProperties: [String: Any] {
        return [
            "recordId": [
                "type": "string",
                "description": "UUID of the record to move"
            ],
            "afterId": [
                "type": "string",
                "description": "UUID of the record to move after"
            ]
        ]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        BlazeLogger.info("MoveAfterTool.execute: move_after requested")
        
        // Check if ordering is enabled
        guard database.isOrderingEnabled() else {
            BlazeLogger.error("MoveAfterTool.execute: ordering not enabled")
            throw MCPError.invalidOperation("Ordering not enabled. Call enableOrdering() first.")
        }
        
        guard let recordIdString = arguments["recordId"] as? String,
              let recordId = UUID(uuidString: recordIdString) else {
            throw MCPError.invalidArguments("'recordId' must be a valid UUID string")
        }
        
        guard let afterIdString = arguments["afterId"] as? String,
              let afterId = UUID(uuidString: afterIdString) else {
            throw MCPError.invalidArguments("'afterId' must be a valid UUID string")
        }
        
        // Move record
        try database.moveAfter(recordId: recordId, afterId: afterId)
        
        BlazeLogger.info("MoveAfterTool.execute: successfully moved \(recordIdString) after \(afterIdString)")
        
        return [
            "success": true,
            "message": "Record moved after target",
            "recordId": recordIdString,
            "afterId": afterIdString
        ]
    }
}

