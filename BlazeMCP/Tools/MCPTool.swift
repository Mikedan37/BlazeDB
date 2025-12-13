//
//  MCPTool.swift
//  BlazeMCP
//
//  Base protocol for MCP tools
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

/// Protocol for MCP tools
protocol MCPTool {
    var name: String { get }
    var description: String { get }
    var schema: [String: Any] { get }
    func execute(arguments: [String: Any]) throws -> [String: Any]
}

/// Base implementation with common functionality
class BaseMCPTool: MCPTool {
    let database: BlazeDBClient
    let name: String
    let description: String
    
    init(database: BlazeDBClient, name: String, description: String) {
        self.database = database
        self.name = name
        self.description = description
    }
    
    var schema: [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": inputSchema
        ]
    }
    
    var inputSchema: [String: Any] {
        return [
            "type": "object",
            "properties": toolProperties,
            "required": requiredProperties
        ]
    }
    
    var toolProperties: [String: Any] {
        return [:]
    }
    
    var requiredProperties: [String] {
        return []
    }
    
    func execute(arguments: [String: Any]) throws -> [String: Any] {
        throw MCPError.notImplemented
    }
}

/// MCP-specific errors
enum MCPError: Error, LocalizedError {
    case invalidArguments(String)
    case databaseError(String)
    case notFound(String)
    case permissionDenied(String)
    case notImplemented
    case invalidOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg):
            return "Invalid arguments: \(msg)"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .permissionDenied(let msg):
            return "Permission denied: \(msg)"
        case .notImplemented:
            return "Not implemented"
        case .invalidOperation(let msg):
            return "Invalid operation: \(msg)"
        }
    }
}

