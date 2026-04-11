import Foundation
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

print("=== Hello BlazeDB ===\n")

do {
    // 1) Open a database
    let db = try BlazeDB.open(name: "HelloBlazeDB", password: "DemoPass123!")
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

    print("\nSuccess")
    print("Next: Docs/GettingStarted/README.md")
} catch {
    print("Error: \(error)")
    exit(1)
}
