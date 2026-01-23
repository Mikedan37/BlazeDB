//
//  QuickStart.swift
//  BlazeDB
//
//  Fast-start example: Complete workflow in one file
//  Runs in <90 seconds, demonstrates all major features
//

import Foundation
import BlazeDB

// MARK: - Quick Start Example

func quickStartExample() throws {
    print("BlazeDB Quick Start Example\n")
    
    // 1. Open database (or create if doesn't exist)
    print("1. Opening database...")
    let db = try BlazeDB.openOrCreate(name: "quickstart", password: "demo-password-123")
    print("   Database opened: \(db.fileURL.path)\n")
    
    // 2. Insert records
    print("2. Inserting records...")
    let records = [
        BlazeDataRecord(["name": .string("Alice"), "age": .int(30), "role": .string("admin")]),
        BlazeDataRecord(["name": .string("Bob"), "age": .int(25), "role": .string("user")]),
        BlazeDataRecord(["name": .string("Charlie"), "age": .int(35), "role": .string("admin")])
    ]
    
    let ids = try db.insertMany(records)
    print("   Inserted \(ids.count) records\n")
    
    // 3. Query with filter
    print("3. Querying records...")
    let results = try db.query()
        .where("role", equals: .string("admin"))
        .orderBy("age", descending: true)
        .execute()
        .records
    
    print("   Found \(results.count) admins:")
    for record in results {
        if let name = record.string("name"), let age = record.int("age") {
            print("      - \(name), age \(age)")
        }
    }
    print()
    
    // 4. Explain query
    print("4. Explaining query...")
    let explanation = try db.query()
        .where("role", equals: .string("admin"))
        .explain()
    print("   \(explanation.description)\n")
    
    // 5. Check health
    print("5. Checking database health...")
    let health = try db.health()
    print("   Status: \(health.status)")
    if !health.reasons.isEmpty {
        print("   Reasons:")
        for reason in health.reasons {
            print("      - \(reason)")
        }
    }
    print()
    
    // 6. Get statistics
    print("6. Database statistics...")
    let stats = try db.stats()
    print("   Records: \(stats.recordCount)")
    print("   Pages: \(stats.pageCount)")
    print("   Size: \(ByteCountFormatter.string(fromByteCount: Int64(stats.databaseSize), countStyle: .file))")
    print()
    
    // 7. Export dump
    print("7. Exporting database dump...")
    let dumpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("quickstart-dump.blazedump")
    try db.export(to: dumpURL)
    print("   Dump created: \(dumpURL.path)\n")
    
    // 8. Verify dump
    print("8. Verifying dump...")
    let dumpHeader = try BlazeDBImporter.verify(dumpURL)
    print("   Dump verified:")
    print("      Schema version: \(dumpHeader.schemaVersion)")
    print("      Record count: \(dumpHeader.recordCount)")
    print("      Created: \(dumpHeader.createdAt)\n")
    
    // 9. Restore to new database
    print("9. Restoring to new database...")
    let restoredDB = try BlazeDB.openTemporary(name: "restored", password: "demo-password-123")
    try BlazeDBImporter.restore(from: dumpURL, to: restoredDB, allowSchemaMismatch: false)
    
    let restoredCount = restoredDB.getRecordCount()
    print("   Restored \(restoredCount) records\n")
    
    // 10. Cleanup
    print("10. Cleaning up...")
    try? FileManager.default.removeItem(at: dumpURL)
    print("   Cleanup complete\n")
    
    print("Quick start complete! All operations succeeded.\n")
    print("Next steps:")
    print("  - Read Docs/Guides/USAGE_BY_TASK.md for common tasks")
    print("  - Check Docs/GettingStarted/QUERY_PERFORMANCE.md for query optimization")
    print("  - Run 'blazedb doctor' for database diagnostics")
}

// MARK: - Main

if CommandLine.arguments.contains("--run") {
    do {
        try quickStartExample()
    } catch {
        print("Error: \(error)")
        if let blazeError = error as? BlazeDBError {
            print("\n\(blazeError.suggestedMessage)")
        }
        exit(1)
    }
} else {
    print("BlazeDB Quick Start Example")
    print("Run with: swift run QuickStart --run")
    print("Or add to Package.swift as executable target")
}
