//
//  main.swift
//  BlazeMCP
//
//  MCP (Model Context Protocol) server for BlazeDB
//  Allows AI tools to safely interact with BlazeDB databases
//
//  Created by Auto on 1/XX/25.
//

import Foundation
import BlazeDB

// Parse command line arguments
let args = CommandLine.arguments
var dbPath: String?
var password: String?
var dbName: String?

var i = 1
while i < args.count {
    switch args[i] {
    case "--db", "-d":
        i += 1
        if i < args.count {
            dbPath = args[i]
        }
    case "--password", "-p":
        i += 1
        if i < args.count {
            password = args[i]
        }
    case "--name", "-n":
        i += 1
        if i < args.count {
            dbName = args[i]
        }
    case "--help", "-h":
        print("""
        BlazeMCP - Model Context Protocol server for BlazeDB
        
        Usage:
          blazemcp [options]
        
        Options:
          --db, -d <path>      Database file path
          --password, -p <pwd> Database password
          --name, -n <name>    Database name (if using default location)
          --help, -h           Show this help
        
        Examples:
          blazemcp --db /path/to/db.blazedb --password "secret"
          blazemcp --name mydb --password "secret"
        
        The server reads MCP JSON-RPC messages from stdin and writes responses to stdout.
        """)
        exit(0)
    default:
        print("Unknown option: \(args[i])")
        print("Use --help for usage information")
        exit(1)
    }
    i += 1
}

// Initialize database connection
guard let db = try? initializeDatabase(path: dbPath, name: dbName, password: password ?? "") else {
    let error = """
    {
      "jsonrpc": "2.0",
      "id": null,
      "error": {
        "code": -32603,
        "message": "Failed to initialize database",
        "data": "Check database path and password"
      }
    }
    """
    print(error)
    exit(1)
}

// Create and run MCP server
let server = MCPServer(database: db)
server.run()

// Helper function to initialize database
func initializeDatabase(path: String?, name: String?, password: String) throws -> BlazeDBClient? {
    if let path = path {
        let url = URL(fileURLWithPath: path)
        return try BlazeDBClient(name: name ?? "mcp_db", fileURL: url, password: password)
    } else if let name = name {
        return try BlazeDBClient(name: name, password: password)
    } else {
        // Default: use "mcp_db" in default location
        return try BlazeDBClient(name: "mcp_db", password: password)
    }
}

