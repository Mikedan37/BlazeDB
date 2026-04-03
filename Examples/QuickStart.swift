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

struct QuickStartUser: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var role: String
}

func quickStartExample() throws {
    print("BlazeDB Quick Start Example\n")
    
    // 1. Open database (or create if doesn't exist)
    print("1. Opening database...")
    let db = try BlazeDBClient.open(named: "quickstart", password: "demo-password-123")
    print("   Database opened: \(db.fileURL.path)\n")
    
    let users = db.typed(QuickStartUser.self)

    // 2. Insert records (typed path)
    print("2. Inserting typed records...")
    try users.insertMany([
        QuickStartUser(name: "Alice", age: 30, role: "admin"),
        QuickStartUser(name: "Bob", age: 25, role: "user"),
        QuickStartUser(name: "Charlie", age: 35, role: "admin"),
    ])
    print("   Inserted 3 records\n")

    // 3. Query with filter (typed path)
    print("3. Querying typed records...")
    let admins = try users.query()
        .where(\.role, equals: "admin")
        .orderBy(\.age, descending: true)
        .all()

    print("   Found \(admins.count) admins:")
    for user in admins {
        print("      - \(user.name), age \(user.age)")
    }
    print()

    // 3b. Raw API remains available
    print("3b. Raw API check...")
    _ = try db.insert(BlazeDataRecord(["name": .string("RawUser"), "age": .int(22), "role": .string("user")]))
    let rawCount = try db.query().where("role", equals: .string("user")).execute().records.count
    print("   Raw query found \(rawCount) user-role records\n")
    
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
    let restoredDB = try BlazeDBClient.openForTesting()
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
