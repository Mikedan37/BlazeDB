import Foundation
import BlazeDB

struct Note: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var body: String
}

print("=== Hello BlazeDB ===\n")

do {
    // Use an isolated temp file so each run starts fresh (deterministic counts).
    let demoDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HelloBlazeDB-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: demoDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: demoDir) }

    let dbURL = demoDir.appendingPathComponent("demo.blazedb")

    // 1) Open a database
    let db = try BlazeDB.open(at: dbURL, password: "DemoPass123!")
    print("Opened database")

    // 2) Put documents
    let groceries = Note(title: "Groceries", body: "Milk and eggs")
    try db.put(groceries)
    try db.put(Note(title: "Ideas", body: "Ship notes feature"))
    print("Inserted sample notes")

    // 3) Get one by key
    let loaded: Note? = try db.get("note:\(groceries.id.uuidString)")
    print("Loaded note: \(loaded?.title ?? "nil")")

    // 4) Query by namespace
    let matches: [Note] = try db.query("note")
        .where("title", equals: "Groceries")
        .all()
    print("Notes titled Groceries: \(matches.count)")

    guard matches.count == 1 else {
        print("Error: expected 1 matching note on a fresh database, got \(matches.count)")
        exit(1)
    }

    // 5) Close and reopen to verify persistence on disk
    try db.close()
    let dbAgain = try BlazeDB.open(at: dbURL, password: "DemoPass123!")
    let persisted: [Note] = try dbAgain.query("note").all()
    guard persisted.count == 2 else {
        print("Error: expected 2 notes after reopen, got \(persisted.count)")
        exit(1)
    }
    try dbAgain.close()

    print("\nSuccess (persisted across reopen)")
    print("Next: Docs/GettingStarted/README.md")
} catch {
    print("Error: \(error)")
    exit(1)
}
