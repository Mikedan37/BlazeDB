//
//  main.swift
//  BlazeInfo
//
//  CLI tool to print database information
//  Works on Linux and macOS
//

import Foundation
import BlazeDBCore

func printDatabaseInfo(dbPath: String, password: String) {
    do {
        let url = URL(fileURLWithPath: dbPath)
        let db = try BlazeDBClient(name: "info-check", fileURL: url, password: password)
        
        print("📊 Database Information")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        // Use the path from the URL passed to open
        print("Path: \(url.path)")
        print("Name: \(db.name)")
        
        // Get stats
        let stats = try db.stats()
        print("")
        print("Size: \(formatBytes(stats.databaseSize))")
        print("Records: \(stats.recordCount)")
        print("Pages: \(stats.pageCount)")
        print("Indexes: \(stats.indexCount)")
        
        if let walSize = stats.walSize {
            print("WAL Size: \(formatBytes(walSize))")
        }
        
        // Get health
        let health = try db.health()
        print("")
        print("Health: \(health.status.rawValue)")
        if !health.reasons.isEmpty {
            for reason in health.reasons {
                print("  • \(reason)")
            }
        }
        
        // Get schema version
        if let schemaVersion = try? db.getSchemaVersion() {
            print("")
            print("Schema Version: \(schemaVersion)")
        }
        
        exit(0)
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        if let blazeError = error as? BlazeDBError {
            print("   💡 \(blazeError.guidance)")
        }
        exit(1)
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// Parse command line arguments
let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    BlazeDB Info Tool
    
    Usage:
      blazedb info <db-path> [<password>]
    
    Password (prefer BLAZEDB_PASSWORD over argv — argv is visible in process listings):
      1. export BLAZEDB_PASSWORD=... then omit the password argument
      2. Legacy: pass <password> as the second argument (deprecated)
    
    Prints database information:
      - Path and name
      - Size and record count
      - Health status
      - Schema version
    
    Options:
      -h, --help    Show this help message
    
    Examples:
      BLAZEDB_PASSWORD='...' blazedb info /path/to/db.blazedb
      blazedb info /path/to/db.blazedb mypassword
    
    Exit codes:
      0    Success
      1    Failure
    """)
    exit(0)
}

let positional = Array(args.dropFirst())
guard positional.count >= 1 else {
    print("Error: Missing required arguments")
    print("Usage: blazedb info <db-path> [<password>]")
    print("Prefer BLAZEDB_PASSWORD over argv. Use --help for more information")
    exit(1)
}

let dbPath = positional[0]
let envPassword = ProcessInfo.processInfo.environment["BLAZEDB_PASSWORD"]
let password: String
if let envPassword, !envPassword.isEmpty {
    if positional.count >= 2 {
        fputs("warning: password argument ignored; using BLAZEDB_PASSWORD (#310/#313)\n", stderr)
    }
    password = envPassword
} else if positional.count >= 2 {
    fputs("warning: passing the database password on argv exposes it via process listings; prefer BLAZEDB_PASSWORD (#310/#313)\n", stderr)
    password = positional[1]
} else {
    print("Error: Missing password (set BLAZEDB_PASSWORD or pass <password>)")
    exit(1)
}

printDatabaseInfo(dbPath: dbPath, password: password)
