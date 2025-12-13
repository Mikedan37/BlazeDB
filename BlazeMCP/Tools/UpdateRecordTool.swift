//
//  UpdateRecordTool.swift
//  BlazeMCP
//
//  Tool for updating records in BlazeDB
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for updating records
final class UpdateRecordTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "update_record",
            description: "Update an existing record by ID. RLS policies are enforced."
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "id": [
                "type": "string",
                "description": "Record ID (UUID string)"
            ],
            "values": [
                "type": "object",
                "description": "Fields to update (key-value pairs)",
                "additionalProperties": true
            ]
        ]
    }
    
    override var requiredProperties: [String] {
        return ["id", "values"]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        guard let idString = arguments["id"] as? String,
              let uuid = UUID(uuidString: idString) else {
            throw MCPError.invalidArguments("'id' must be a valid UUID string")
        }
        
        guard let values = arguments["values"] as? [String: Any] else {
            throw MCPError.invalidArguments("'values' must be an object")
        }
        
        // Check if record exists (RLS enforced)
        guard let existing = try database.fetch(id: uuid) else {
            throw MCPError.notFound("Record with id \(idString) not found")
        }
        
        // Merge existing with new values
        var updatedStorage = existing.storage
        for (key, value) in values {
            updatedStorage[key] = try valueToBlazeDocumentField(value)
        }
        
        let updatedRecord = BlazeDataRecord(updatedStorage)
        
        // Update (RLS is automatically enforced)
        try database.update(id: uuid, with: updatedRecord)
        
        return [
            "id": idString,
            "success": true,
            "message": "Record updated successfully"
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
        } else if let uuidString = value as? String, let uuid = UUID(uuidString: uuidString) {
            return .uuid(uuid)
        } else if let dateString = value as? String, let date = ISO8601DateFormatter().date(from: dateString) {
            return .date(date)
        } else if let base64 = value as? String, let data = Data(base64Encoded: base64) {
            return .data(data)
        } else if let array = value as? [Any] {
            return .array(try array.map { try valueToBlazeDocumentField($0) })
        } else if let dict = value as? [String: Any] {
            var blazeDict: [String: BlazeDocumentField] = [:]
            for (k, v) in dict {
                blazeDict[k] = try valueToBlazeDocumentField(v)
            }
            return .dictionary(blazeDict)
        } else {
            throw MCPError.invalidArguments("Unsupported value type: \(type(of: value))")
        }
    }
}

