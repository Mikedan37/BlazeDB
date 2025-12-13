//
//  DeleteRecordTool.swift
//  BlazeMCP
//
//  Tool for deleting records from BlazeDB
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for deleting records
final class DeleteRecordTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "delete_record",
            description: "Delete a record by ID. RLS policies are enforced."
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "id": [
                "type": "string",
                "description": "Record ID (UUID string)"
            ]
        ]
    }
    
    override var requiredProperties: [String] {
        return ["id"]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        guard let idString = arguments["id"] as? String,
              let uuid = UUID(uuidString: idString) else {
            throw MCPError.invalidArguments("'id' must be a valid UUID string")
        }
        
        // Check if record exists (RLS enforced)
        guard try database.fetch(id: uuid) != nil else {
            throw MCPError.notFound("Record with id \(idString) not found")
        }
        
        // Delete (RLS is automatically enforced)
        try database.delete(id: uuid)
        
        return [
            "id": idString,
            "success": true,
            "message": "Record deleted successfully"
        ]
    }
}

