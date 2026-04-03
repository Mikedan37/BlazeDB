//
//  main.swift
//  HelloBlazeDB
//
//  Open → Insert → Query → Fetch → Export → Health → Close
//  Showcases the typed BlazeStorable API (recommended) and the raw BlazeDataRecord API.
//

import Foundation
import BlazeDB

// MARK: - Model (BlazeStorable — recommended)

struct User: BlazeStorable {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var active: Bool
}

print("=== Hello BlazeDB ===\n")

do {
    // STEP 1: Open database
    print("1. Opening database...")
    let runID = UUID().uuidString
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("hello-blazedb-\(runID).blaze")
    let db = try BlazeDBClient.open(at: dbPath, password: "Hello-BlazeDB-Demo-2026A!")
    print("   Database opened\n")

    // ──────────────────────────────────────────────
    // Typed API (BlazeStorable + TypedStore)
    // ──────────────────────────────────────────────

    print("── Typed API (recommended) ──\n")

    let users = db.typed(User.self)

    // STEP 2: Insert typed models
    print("2. Inserting typed models...")
    let seedUsers = [
        User(name: "Alice",   age: 30, active: true),
        User(name: "Bob",     age: 25, active: false),
        User(name: "Charlie", age: 35, active: true),
    ]
    var insertedIDs: [UUID] = []
    for user in seedUsers {
        let id = try users.insert(user)
        insertedIDs.append(id)
        print("   Inserted: \(user.name) (ID: \(id.uuidString.prefix(8))...)")
    }
    print()

    // STEP 3: Query with KeyPaths
    print("3. Querying active users (KeyPath filter)...")
    let activeUsers = try users.query()
        .where(\.active, equals: true)
        .all()

    print("   Found \(activeUsers.count) active users:")
    for u in activeUsers {
        print("   - \(u.name), age \(u.age)")
    }
    print()

    // STEP 4: Fetch by ID
    print("4. Fetching by ID...")
    if let firstID = insertedIDs.first,
       let fetched = try users.fetch(firstID) {
        print("   Found: \(fetched.name)")
    }
    print()

    // ──────────────────────────────────────────────
    // Raw API (BlazeDataRecord)
    // ──────────────────────────────────────────────

    print("── Raw API (BlazeDataRecord) ──\n")

    print("5. Inserting a raw record...")
    let rawRecord = BlazeDataRecord([
        "name": .string("Diana"),
        "age": .int(28),
        "active": .bool(true),
    ])
    let rawID = try db.insert(rawRecord)
    print("   Inserted raw record (ID: \(rawID.uuidString.prefix(8))...)")
    print()

    print("6. Querying with string-based filter...")
    let rawResults = try db.query()
        .where("active", equals: .bool(true))
        .execute()
        .records
    print("   Found \(rawResults.count) active records (typed + raw combined)")
    print()

    // ──────────────────────────────────────────────
    // Database utilities
    // ──────────────────────────────────────────────

    // STEP 7: Export
    print("7. Exporting database...")
    let exportPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("hello-export.blazedump")
    try db.export(to: exportPath)
    let dumpHeader = try BlazeDBImporter.verify(exportPath)
    print("   Exported and verified (schema version: \(dumpHeader.schemaVersion))")
    print()

    // STEP 8: Statistics
    print("8. Database statistics...")
    let stats = try db.stats()
    print("   Records: \(stats.recordCount)")
    print("   Size: \(ByteCountFormatter.string(fromByteCount: Int64(stats.databaseSize), countStyle: .file))")
    print()

    // STEP 9: Health check
    print("9. Health check...")
    let health = try db.health()
    print("   Status: \(health.status.rawValue)")
    if health.reasons.isEmpty {
        print("   All systems healthy")
    } else {
        for reason in health.reasons {
            print("   Warning: \(reason)")
        }
    }
    print()

    // STEP 10: Close
    print("10. Closing database...")
    try db.close()
    print("   Database closed cleanly\n")

    print("=== Success! ===")
    print("BlazeDB is working correctly.")
    print("\nNext steps:")
    print("  - Read Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md")
    print("  - Check Docs/Guarantees/SAFETY_MODEL.md for safety details")
    print("  - Run 'blazedb doctor' for diagnostics")

} catch {
    print("\nError: \(error)")
    if let blazeError = error as? BlazeDBError {
        print("\nGuidance: \(blazeError.guidance)")
    }
    print("\nIf this failed, here's why:")
    print("  - Disk full: Free disk space and retry")
    print("  - Permission error: Check file permissions")
    print("  - Invalid path: Use a valid directory path")
    print("  - Wrong password: Use correct password")
    exit(1)
}
