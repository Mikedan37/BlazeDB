//
//  ReadmeSamples
//  BlazeDB
//
//  Executes README code patterns so documentation drift fails CI.
//  Keep in sync with README.md and Examples/ReadmeSamples/README.md (coverage table).
//

import Foundation
import BlazeDB

private let demoPassword = "DemoPass123!"

private func freshDB(_ label: String) throws -> (BlazeDBClient, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ReadmeSamples-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(label).blazedb")
    let db = try BlazeDB.open(at: url, password: demoPassword)
    return (db, dir)
}

private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}

private struct SampleError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func sampleError(_ context: String) -> SampleError {
    SampleError(message: "README sample failed: \(context)")
}

// MARK: - Start Here (struct names match README → namespace keys match get/query)

private func verifyStartHere() throws {
    struct Bug: BlazeStorable {
        var id: UUID = UUID()
        var title: String
        var status: String
    }

    let (db, dir) = try freshDB("start-here")
    defer {
        try? db.close()
        cleanup(dir)
    }

    let bug = Bug(title: "Crash on launch", status: "open")
    try db.put(bug)

    let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
    guard loaded?.title == bug.title else {
        throw sampleError("Start Here get()")
    }

    let openBugs: [Bug] = try db.query("bug")
        .where("status", equals: "open")
        .all()
    guard openBugs.count == 1 else {
        throw sampleError("Start Here query() expected 1 open bug, got \(openBugs.count)")
    }
    print("PASS: Start Here (open → put → get → query)")
}

// MARK: - Minimal Note

private func verifyMinimalNote() throws {
    struct Note: BlazeStorable {
        var id: UUID = UUID()
        var text: String
    }

    let (db, dir) = try freshDB("minimal-note")
    defer {
        try? db.close()
        cleanup(dir)
    }

    try db.put(Note(text: "Ship first BlazeDB build"))
    let notes: [Note] = try db.query("note").all()
    guard notes.count == 1, notes[0].text == "Ship first BlazeDB build" else {
        throw sampleError("Minimal Note sample")
    }
    print("PASS: Minimal Note sample")
}

// MARK: - List + ListItem (typed query)

private func verifyListItems() throws {
    struct List: BlazeStorable {
        var id: UUID = UUID()
        var name: String
    }

    struct ListItem: BlazeStorable {
        var id: UUID = UUID()
        var listID: UUID
        var name: String
        var isDone: Bool = false
    }

    let (db, dir) = try freshDB("list-items")
    defer {
        try? db.close()
        cleanup(dir)
    }

    let groceries = List(name: "Groceries")
    try db.put(groceries)
    try db.put(ListItem(listID: groceries.id, name: "Milk"))
    try db.put(ListItem(listID: groceries.id, name: "Eggs"))

    let lists: [List] = try db.query("list").all()
    guard lists.count == 1 else {
        throw sampleError("List query expected 1 list")
    }

    let groceryItems: [ListItem] = try db.query(ListItem.self)
        .where(\.listID, equals: groceries.id)
        .all()
    guard groceryItems.count == 2 else {
        throw sampleError("ListItem typed query expected 2 items, got \(groceryItems.count)")
    }
    print("PASS: List + ListItem (typed query)")
}

// MARK: - Direct CRUD

private func verifyDirectCRUD() throws {
    struct User: BlazeStorable {
        var id: UUID = UUID()
        var name: String
        var age: Int
    }

    let (db, dir) = try freshDB("direct-crud")
    defer {
        try? db.close()
        cleanup(dir)
    }

    var user1 = User(name: "Alice", age: 30)
    let user2 = User(name: "Bob", age: 17)
    let userId = try db.insert(user1)
    _ = try db.insertMany([user2, User(name: "Carol", age: 25)])

    guard try db.fetch(User.self, id: userId)?.name == "Alice" else {
        throw sampleError("fetch(User.self, id:)")
    }

    let all = try db.fetchAll(User.self)
    guard all.count == 3 else {
        throw sampleError("fetchAll expected 3 users")
    }

    user1.name = "Alicia"
    try db.update(user1)

    let upsertUser = User(id: UUID(), name: "Dan", age: 40)
    _ = try db.upsert(upsertUser)

    let adults = try db.query(User.self)
        .where(\.age, greaterThanOrEqual: 21)
        .orderBy(\.name, descending: false)
        .all()
    guard adults.count >= 2 else {
        throw sampleError("typed KeyPath query")
    }

    try db.delete(user2)
    guard try db.fetch(User.self, id: user2.id) == nil else {
        throw sampleError("delete(user)")
    }
    print("PASS: Direct CRUD + typed query")
}

// MARK: - TypedStore

private func verifyTypedStore() throws {
    struct User: BlazeStorable {
        var id: UUID = UUID()
        var name: String
        var age: Int
    }

    let (db, dir) = try freshDB("typed-store")
    defer {
        try? db.close()
        cleanup(dir)
    }

    let users = db.typed(User.self)
    let user = User(name: "StoreUser", age: 33)
    _ = try users.insert(user)
    let all = try users.fetchAll()
    guard all.count == 1, all[0].name == "StoreUser" else {
        throw sampleError("TypedStore")
    }
    print("PASS: TypedStore")
}

// MARK: - Raw API

private func verifyRawAPI() throws {
    let (db, dir) = try freshDB("raw-api")
    defer {
        try? db.close()
        cleanup(dir)
    }

    let record = BlazeDataRecord([
        "name": .string("Alice"),
        "age": .int(30),
        "active": .bool(true),
    ])
    _ = try db.insert(record)

    let results = try db.query()
        .where("active", equals: .bool(true))
        .execute()
        .records
    guard results.count == 1 else {
        throw sampleError("Raw query")
    }
    print("PASS: Raw API")
}

// MARK: - Opening variants

private func verifyOpening() throws {
    let named = try BlazeDB.open(name: "ReadmeSamplesNamed-\(UUID().uuidString)", password: demoPassword)

    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ReadmeSamples-open-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { cleanup(dir) }
    let atURL = dir.appendingPathComponent("at.blazedb")
    let atDB = try BlazeDB.open(at: atURL, password: demoPassword)

    let testingDB = try BlazeDBClient.openForTesting(password: demoPassword)
    defer {
        try? testingDB.close()
        try? named.close()
        try? atDB.close()
    }

    _ = try named.insert(BlazeDataRecord(["probe": .string("named")]))
    _ = try atDB.insert(BlazeDataRecord(["probe": .string("at")]))
    _ = try testingDB.insert(BlazeDataRecord(["probe": .string("testing")]))

    print("PASS: Opening (name / at / openForTesting)")
}

// MARK: - Transactions

private func verifyTransactions() throws {
    struct User: BlazeStorable {
        var id: UUID = UUID()
        var name: String
        var age: Int
    }

    let (db, dir) = try freshDB("transactions")
    defer {
        try? db.close()
        cleanup(dir)
    }

    let users = db.typed(User.self)
    let user1 = User(name: "Tx1", age: 20)
    let user2 = User(name: "Tx2", age: 22)

    try db.beginTransaction()
    try users.insert(user1)
    try users.insert(user2)
    try db.commitTransaction()

    guard try users.fetchAll().count == 2 else {
        throw sampleError("transaction commit")
    }

    let beforeRollback = try users.fetchAll().count
    try db.beginTransaction()
    _ = try users.insert(User(name: "Tx3", age: 19))
    try db.rollbackTransaction()
    guard try users.fetchAll().count == beforeRollback else {
        throw sampleError("transaction rollback")
    }

    print("PASS: Transactions")
}

// MARK: - Utilities

private func verifyUtilities() throws {
    let (db, dir) = try freshDB("utilities")
    defer {
        try? db.close()
        cleanup(dir)
    }

    _ = try db.insert(BlazeDataRecord(["x": .int(1)]))
    try db.persist()

    let stats = try db.stats()
    guard stats.recordCount >= 1 else {
        throw sampleError("stats()")
    }

    _ = try db.health()

    let exportURL = dir.appendingPathComponent("export.blazedump")
    try db.export(to: exportURL)
    _ = try BlazeDBImporter.verify(exportURL)

    print("PASS: Utilities (stats / health / export / verify)")
}

@main
enum ReadmeSamples {
    private enum Section: String, CaseIterable {
        case startHere = "start-here"
        case minimalNote = "minimal-note"
        case listItems = "list-items"
        case directCRUD = "direct-crud"
        case typedStore = "typed-store"
        case rawAPI = "raw-api"
        case opening = "opening"
        case transactions = "transactions"
        case utilities = "utilities"

        func run() throws {
            switch self {
            case .startHere: try verifyStartHere()
            case .minimalNote: try verifyMinimalNote()
            case .listItems: try verifyListItems()
            case .directCRUD: try verifyDirectCRUD()
            case .typedStore: try verifyTypedStore()
            case .rawAPI: try verifyRawAPI()
            case .opening: try verifyOpening()
            case .transactions: try verifyTransactions()
            case .utilities: try verifyUtilities()
            }
        }
    }

    private static func printUsage() {
        let keys = Section.allCases.map(\.rawValue).joined(separator: ", ")
        fputs(
            """
            Usage: swift run ReadmeSamples [--only <section>]

            Sections: \(keys)

            Example: swift run ReadmeSamples --only transactions

            """,
            stderr
        )
    }

    static func main() throws {
        let args = CommandLine.arguments
        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }

        let sections: [Section]
        if let onlyIndex = args.firstIndex(of: "--only") {
            guard onlyIndex + 1 < args.count else {
                printUsage()
                throw sampleError("missing value for --only")
            }
            let key = args[onlyIndex + 1]
            guard let section = Section(rawValue: key) else {
                printUsage()
                throw sampleError("unknown section '\(key)'")
            }
            sections = [section]
        } else {
            sections = Array(Section.allCases)
        }

        print("=== README sample verification ===")
        for section in sections {
            try section.run()
        }
        if sections.count == 1 {
            print("=== PASS: README sample '\(sections[0].rawValue)' verified ===")
        } else {
            print("=== PASS: all README samples verified ===")
        }
    }
}
