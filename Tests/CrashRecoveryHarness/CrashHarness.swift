//
//  CrashHarness.swift
//  BlazeDB Crash Recovery Harness
//
//  Tests BlazeDB survival under SIGKILL crashes and power-loss scenarios
//  This executable can be invoked by a shell script that kills it mid-operation
//
//  Usage:
//    swift run CrashHarness <db-path> <operation-count> <crash-point>
//
//  Where crash-point is:
//    - "none" = run to completion
//    - "mid-write" = crash during write operation
//    - "mid-transaction" = crash during transaction
//    - "before-close" = crash before close()
//

import Foundation
import BlazeDBCore

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("Usage: CrashHarness <db-path> <operation-count> <crash-point>")
    print("  crash-point: none | mid-write | mid-transaction | before-close")
    exit(1)
}

let dbPath = URL(fileURLWithPath: args[1])
let operationCount = Int(args[2]) ?? 100
let crashPoint = args[3]

print("=== BlazeDB Crash Harness ===")
print("Database: \(dbPath.path)")
print("Operations: \(operationCount)")
print("Crash point: \(crashPoint)")
print("")

do {
    // Open database
    let db = try BlazeDBClient(name: "crash-test", fileURL: dbPath, password: "test-password")
    print("✓ Database opened")
    
    // Insert records in a loop
    var insertedIDs: [UUID] = []
    
    for i in 0..<operationCount {
        let record = BlazeDataRecord([
            "index": .int(i),
            "data": .string("Record \(i)"),
            "timestamp": .date(Date())
        ])
        
        if crashPoint == "mid-write" && i == operationCount / 2 {
            print("💥 CRASHING at mid-write (operation \(i))")
            // Force immediate exit without cleanup
            exit(1)
        }
        
        let id = try db.insert(record)
        insertedIDs.append(id)
        
        if i % 10 == 0 {
            print("  Inserted \(i) records...")
        }
        
        // Flush periodically to ensure WAL writes
        if i % 50 == 0 {
            try db.persist()
        }
    }
    
    // Transaction test
    if crashPoint == "mid-transaction" {
        print("💥 CRASHING during transaction")
        try db.beginTransaction()
        for i in 0..<10 {
            let record = BlazeDataRecord(["txn": .bool(true), "index": .int(i)])
            _ = try db.insert(record)
        }
        // Crash before commit
        exit(1)
    }
    
    // Final flush
    try db.persist()
    print("✓ All operations completed")
    
    // Verify record count
    let count = db.count()
    print("✓ Record count: \(count)")
    
    if crashPoint == "before-close" {
        print("💥 CRASHING before close()")
        exit(1)
    }
    
    // Normal close
    try db.close()
    print("✓ Database closed normally")
    
    print("\n=== Harness Complete ===")
    exit(0)
    
} catch {
    print("❌ Error: \(error)")
    exit(1)
}
