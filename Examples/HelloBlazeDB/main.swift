//
//  main.swift
//  HelloBlazeDB
//
//  Zero-config example: Open → Insert → Query → Export → Close
//  This example should work immediately without reading docs
//

import Foundation
import BlazeDBCore

print("=== Hello BlazeDB ===\n")

do {
    // STEP 1: Open database (zero config)
    print("1. Opening database...")
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("hello-blazedb.db")
    
    let db = try BlazeDBClient(name: "hello", fileURL: dbPath, password: "Demo-Password-123!")
    print("   ✓ Database opened: \(dbPath.path)\n")
    
    // STEP 2: Insert data
    print("2. Inserting records...")
    let users = [
        ("Alice", 30, true),
        ("Bob", 25, false),
        ("Charlie", 35, true)
    ]
    
    var insertedIDs: [UUID] = []
    for (name, age, active) in users {
        let record = BlazeDataRecord([
            "name": .string(name),
            "age": .int(age),
            "active": .bool(active)
        ])
        let id = try db.insert(record)
        insertedIDs.append(id)
        print("   ✓ Inserted: \(name) (ID: \(id.uuidString.prefix(8))...)")
    }
    print()
    
    // STEP 3: Query data
    print("3. Querying active users...")
    let activeUsers = try db.query()
        .where("active", equals: .bool(true))
        .execute()
        .records
    
    print("   Found \(activeUsers.count) active users:")
    for user in activeUsers {
        if let name = try? user.string("name"),
           let age = try? user.int("age") {
            print("   - \(name), age \(age)")
        }
    }
    print()
    
    // STEP 4: Fetch by ID
    print("4. Fetching record by ID...")
    if let firstID = insertedIDs.first,
       let record = try db.fetch(id: firstID) {
        if let name = try? record.string("name") {
            print("   ✓ Found: \(name)")
        }
    }
    print()
    
    // STEP 5: Export database
    print("5. Exporting database...")
    let exportPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("hello-export.blazedump")
    
    try db.export(to: exportPath)
    print("   ✓ Exported to: \(exportPath.path)")
    
    // Verify export
    let dumpHeader = try BlazeDBImporter.verify(exportPath)
    print("   ✓ Export verified (schema version: \(dumpHeader.schemaVersion))")
    print()
    
    // STEP 6: Get statistics
    print("6. Database statistics...")
    let stats = try db.stats()
    print("   Records: \(stats.recordCount)")
    print("   Size: \(ByteCountFormatter.string(fromByteCount: Int64(stats.databaseSize), countStyle: .file))")
    print()
    
    // STEP 7: Health check
    print("7. Health check...")
    let health = try db.health()
    print("   Status: \(health.status.rawValue)")
    if !health.reasons.isEmpty {
        for reason in health.reasons {
            print("   ⚠️  \(reason)")
        }
    } else {
        print("   ✓ All systems healthy")
    }
    print()
    
    // STEP 8: Close database
    print("8. Closing database...")
    try db.close()
    print("   ✓ Database closed cleanly\n")
    
    print("=== Success! ===")
    print("BlazeDB is working correctly.")
    print("\nNext steps:")
    print("  - Read Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md")
    print("  - Check Docs/Guarantees/SAFETY_MODEL.md for safety details")
    print("  - Run 'blazedb doctor' for diagnostics")
    
} catch {
    print("\n❌ Error: \(error)")
    
    if let blazeError = error as? BlazeDBError {
        print("\n💡 Guidance: \(blazeError.guidance)")
    }
    
    print("\nIf this failed, here's why:")
    print("  - Disk full: Free disk space and retry")
    print("  - Permission error: Check file permissions")
    print("  - Invalid path: Use a valid directory path")
    print("  - Wrong password: Use correct password")
    
    exit(1)
}
