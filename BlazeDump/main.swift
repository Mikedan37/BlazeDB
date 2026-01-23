//
//  main.swift
//  BlazeDump
//
//  CLI tool for database dump/restore/verify
//  Uses public APIs only
//

import Foundation
import BlazeDBCore

func dumpDatabase(dbPath: String, dumpPath: String, password: String) {
    do {
        let dbURL = URL(fileURLWithPath: dbPath)
        let dumpURL = URL(fileURLWithPath: dumpPath)
        
        let db = try BlazeDBClient(name: "dump-tool", fileURL: dbURL, password: password)
        
        print("Exporting database to \(dumpPath)...")
        try db.export(to: dumpURL)
        
        print("✅ Export successful")
        exit(0)
    } catch {
        print("❌ Export failed: \(error.localizedDescription)")
        if let blazeError = error as? BlazeDBError {
            print("   💡 \(blazeError.guidance)")
        }
        exit(1)
    }
}

func restoreDatabase(dumpPath: String, dbPath: String, password: String, allowSchemaMismatch: Bool) {
    do {
        let dumpURL = URL(fileURLWithPath: dumpPath)
        let dbURL = URL(fileURLWithPath: dbPath)
        
        // Create or open target database
        let db = try BlazeDBClient(name: "restore-target", fileURL: dbURL, password: password)
        
        print("Restoring database from \(dumpPath)...")
        try BlazeDBImporter.restore(from: dumpURL, to: db, allowSchemaMismatch: allowSchemaMismatch)
        
        print("✅ Restore successful")
        exit(0)
    } catch {
        print("❌ Restore failed: \(error.localizedDescription)")
        if let blazeError = error as? BlazeDBError {
            print("   💡 \(blazeError.guidance)")
        }
        exit(1)
    }
}

func verifyDump(dumpPath: String) {
    do {
        let dumpURL = URL(fileURLWithPath: dumpPath)
        
        print("Verifying dump file \(dumpPath)...")
        let header = try BlazeDBImporter.verify(dumpURL)
        
        print("✅ Dump file is valid")
        print("   Format version: \(header.formatVersion.rawValue)")
        print("   Schema version: \(header.schemaVersion)")
        print("   Database: \(header.databaseName)")
        print("   Exported at: \(header.exportedAt)")
        exit(0)
    } catch {
        print("❌ Verification failed: \(error.localizedDescription)")
        if let blazeError = error as? BlazeDBError {
            print("   💡 \(blazeError.guidance)")
        }
        exit(1)
    }
}

// Parse command line arguments
let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    BlazeDB Dump Tool
    
    Commands:
      dump <db-path> <dump-path> <password>
        Export database to dump file
        
      restore <dump-path> <db-path> <password> [--allow-schema-mismatch]
        Restore database from dump file
        
      verify <dump-path>
        Verify dump file integrity
        
    Options:
      --allow-schema-mismatch    Allow restore even if schema versions don't match
      -h, --help                 Show this help message
    
    Examples:
      blazedb dump /path/to/db.blazedb /path/to/backup.blazedump mypassword
      blazedb restore /path/to/backup.blazedump /path/to/newdb.blazedb mypassword
      blazedb verify /path/to/backup.blazedump
    
    Exit codes:
      0    Success
      1    Failure
    """)
    exit(0)
}

guard args.count >= 2 else {
    print("Error: Missing command")
    print("Use --help for usage information")
    exit(1)
}

let command = args[1]

switch command {
case "dump":
    guard args.count >= 5 else {
        print("Error: Missing arguments for dump command")
        print("Usage: blazedb dump <db-path> <dump-path> <password>")
        exit(1)
    }
    dumpDatabase(dbPath: args[2], dumpPath: args[3], password: args[4])
    
case "restore":
    guard args.count >= 5 else {
        print("Error: Missing arguments for restore command")
        print("Usage: blazedb restore <dump-path> <db-path> <password> [--allow-schema-mismatch]")
        exit(1)
    }
    let allowMismatch = args.contains("--allow-schema-mismatch")
    restoreDatabase(dumpPath: args[2], dbPath: args[3], password: args[4], allowSchemaMismatch: allowMismatch)
    
case "verify":
    guard args.count >= 3 else {
        print("Error: Missing dump path")
        print("Usage: blazedb verify <dump-path>")
        exit(1)
    }
    verifyDump(dumpPath: args[2])
    
default:
    print("Error: Unknown command '\(command)'")
    print("Use --help for usage information")
    exit(1)
}
