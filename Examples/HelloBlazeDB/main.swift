import Foundation
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
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
    let bug = Bug(title: "Crash on launch", status: "open")
    try db.put(bug)
    try db.put(Bug(title: "Settings UI glitch", status: "open"))
    try db.put(Bug(title: "Old fixed bug", status: "closed"))
    print("Inserted sample bugs")

    // 3) Get one by key
    let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
    print("Loaded bug: \(loaded?.title ?? "nil")")

    // 4) Query by namespace
    let openBugs: [Bug] = try db.query("bug")
        .where("status", equals: "open")
        .all()
    print("Open bugs: \(openBugs.count)")

    guard openBugs.count == 2 else {
        print("Error: expected 2 open bugs on a fresh database, got \(openBugs.count)")
        exit(1)
    }

    // 5) Close and reopen to verify persistence on disk
    try db.close()
    let dbAgain = try BlazeDB.open(at: dbURL, password: "DemoPass123!")
    let persisted: [Bug] = try dbAgain.query("bug").where("status", equals: "open").all()
    guard persisted.count == 2 else {
        print("Error: expected 2 open bugs after reopen, got \(persisted.count)")
        exit(1)
    }
    try dbAgain.close()

    print("\nSuccess (persisted across reopen)")
    print("Next: Docs/GettingStarted/README.md")
} catch {
    print("Error: \(error)")
    exit(1)
}
