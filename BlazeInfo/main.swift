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
      blazedb info <db-path> <password>
    
    Prints database information:
      - Path and name
      - Size and record count
      - Health status
      - Schema version
    
    Options:
      -h, --help    Show this help message
    
    Examples:
      blazedb info /path/to/db.blazedb mypassword
      blazedb info ./mydb.blazedb mypassword
    
    Exit codes:
      0    Success
      1    Failure
    """)
    exit(0)
}

guard args.count >= 3 else {
    print("Error: Missing required arguments")
    print("Usage: blazedb info <db-path> <password>")
    print("Use --help for more information")
    exit(1)
}

let dbPath = args[1]
let password = args[2]

printDatabaseInfo(dbPath: dbPath, password: password)
