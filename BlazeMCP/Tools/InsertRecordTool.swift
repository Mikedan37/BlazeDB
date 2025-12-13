//
//  InsertRecordTool.swift
//  BlazeMCP
//
//  Tool for inserting records into BlazeDB
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Tool for inserting records
final class InsertRecordTool: BaseMCPTool {
    
    init(database: BlazeDBClient) {
        super.init(
            database: database,
            name: "insert_record",
            description: "Insert a new record into the database. RLS policies are enforced."
        )
    }
    
    override var toolProperties: [String: Any] {
        return [
            "record": [
                "type": "object",
                "description": "Record data as key-value pairs",
                "additionalProperties": true
            ]
        ]
    }
    
    override var requiredProperties: [String] {
        return ["record"]
    }
    
    override func execute(arguments: [String: Any]) throws -> [String: Any] {
        guard let recordData = arguments["record"] as? [String: Any] else {
            throw MCPError.invalidArguments("'record' is required and must be an object")
        }
        
        // Convert to BlazeDataRecord
        var storage: [String: BlazeDocumentField] = [:]
        for (key, value) in recordData {
            storage[key] = try valueToBlazeDocumentField(value)
        }
        
        let record = BlazeDataRecord(storage)
        
        // Insert (RLS is automatically enforced)
        let id = try database.insert(record)
        
        return [
            "id": id.uuidString,
            "success": true,
            "message": "Record inserted successfully"
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

