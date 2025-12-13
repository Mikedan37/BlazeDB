//
//  MCPServer.swift
//  BlazeMCP
//
//  MCP (Model Context Protocol) server implementation
//  Handles JSON-RPC over stdin/stdout
//
//  Created by Auto on 1/XX/25.
//

import Foundation
@preconcurrency import BlazeDB

/// MCP Server that handles JSON-RPC requests
public final class MCPServer {
    private let database: BlazeDBClient
    private var isRunning = false
    private let tools: [any MCPTool]
    
    public init(database: BlazeDBClient) {
        self.database = database
        
        // Register base tools
        var toolList: [any MCPTool] = [
            ListSchemaTool(database: database),
            RunQueryTool(database: database),
            InsertRecordTool(database: database),
            UpdateRecordTool(database: database),
            DeleteRecordTool(database: database),
            GraphQueryTool(database: database),
            SuggestIndexesTool(database: database),
            BinaryQueryTool(database: database)
        ]
        
        // Conditionally add ordering tools (only if ordering is enabled)
        if database.isOrderingEnabled() {
            toolList.append(contentsOf: [
                MoveBeforeTool(database: database),
                MoveAfterTool(database: database),
                MoveToIndexTool(database: database)
            ])
            BlazeLogger.info("MCPServer.init: ordering tools enabled (move_before, move_after, move_to_index)")
        } else {
            BlazeLogger.debug("MCPServer.init: ordering disabled, skipping ordering tools")
        }
        
        self.tools = toolList
        
        BlazeLogger.info("MCP Server initialized with \(tools.count) tools")
    }
    
    /// Run the MCP server (reads from stdin, writes to stdout)
    public func run() {
        isRunning = true
        
        // Set up stdin/stdout
        _ = FileHandle.standardInput
        _ = FileHandle.standardOutput
        
        // Read line by line from stdin
        while isRunning {
            guard let line = readLine() else {
                // EOF or error
                break
            }
            
            // Parse JSON-RPC request
            guard let request = parseRequest(line) else {
                sendError(id: nil, code: -32700, message: "Parse error", data: nil)
                continue
            }
            
            // Handle request
            handleRequest(request)
        }
    }
    
    // MARK: - Request Handling
    
    private func handleRequest(_ request: MCPRequest) {
        switch request.method {
        case "initialize":
            handleInitialize(request)
        case "tools/list":
            handleListTools(request)
        case "tools/call":
            handleCallTool(request)
        case "ping":
            handlePing(request)
        default:
            sendError(id: request.id, code: -32601, message: "Method not found", data: nil)
        }
    }
    
    private func handleInitialize(_ request: MCPRequest) {
        let response = MCPResponse(
            id: request.id,
            result: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:]
                ],
                "serverInfo": [
                    "name": "BlazeMCP",
                    "version": "1.0.0"
                ]
            ]
        )
        sendResponse(response)
    }
    
    private func handleListTools(_ request: MCPRequest) {
        let toolSchemas = tools.map { $0.schema }
        let response = MCPResponse(
            id: request.id,
            result: [
                "tools": toolSchemas
            ]
        )
        sendResponse(response)
    }
    
    private func handleCallTool(_ request: MCPRequest) {
        guard let params = request.params as? [String: Any],
              let toolName = params["name"] as? String else {
            sendError(id: request.id, code: -32602, message: "Invalid params", data: nil)
            return
        }
        
        // Find tool
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            sendError(id: request.id, code: -32601, message: "Tool not found: \(toolName)", data: nil)
            return
        }
        
        // Get tool arguments
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        
        // Execute tool
        do {
            let result = try tool.execute(arguments: arguments)
            let response = MCPResponse(id: request.id, result: result)
            sendResponse(response)
        } catch {
            let errorMessage = error.localizedDescription
            sendError(id: request.id, code: -32000, message: "Tool execution failed", data: ["error": errorMessage])
        }
    }
    
    private func handlePing(_ request: MCPRequest) {
        let response = MCPResponse(id: request.id, result: ["pong": true])
        sendResponse(response)
    }
    
    // MARK: - JSON-RPC Protocol
    
    private func parseRequest(_ json: String) -> MCPRequest? {
        guard let data = json.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        guard let method = json["method"] as? String else {
            return nil
        }
        
        let id = json["id"]
        let params = json["params"]
        
        return MCPRequest(id: id, method: method, params: params)
    }
    
    private func sendResponse(_ response: MCPResponse) {
        guard let json = try? JSONSerialization.data(withJSONObject: response.toJSON(), options: []),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }
        
        print(jsonString)
        fflush(stdout)
    }
    
    private func sendError(id: Any?, code: Int, message: String, data: Any?) {
        let error: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
                "data": data ?? NSNull()
            ]
        ]
        
        guard let json = try? JSONSerialization.data(withJSONObject: error, options: []),
              let jsonString = String(data: json, encoding: .utf8) else {
            return
        }
        
        print(jsonString)
        fflush(stdout)
    }
}

// MARK: - MCP Protocol Types

private struct MCPRequest {
    let id: Any?
    let method: String
    let params: Any?
}

private struct MCPResponse {
    let id: Any?
    let result: [String: Any]
    
    func toJSON() -> [String: Any] {
        return [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
    }
}

