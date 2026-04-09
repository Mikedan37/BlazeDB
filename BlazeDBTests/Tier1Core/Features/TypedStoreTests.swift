import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Tests for the `TypedStore` ergonomic façade and dual-API coexistence.
final class TypedStoreTests: XCTestCase {

    var db: BlazeDBClient!
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        db = try! BlazeDBClient(
            name: "TypedStoreTest",
            fileURL: tempURL,
            password: "TypedStore-Test-2026A!"
        )
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: - Test Model

    struct Task: BlazeStorable {
        var id: UUID = UUID()
        var title: String
        var priority: Int
        var done: Bool
    }

    // MARK: - TypedStore CRUD

    func testInsertAndFetch() throws {
        let tasks = db.typed(Task.self)
        let t = Task(title: "Ship v3", priority: 9, done: false)
        let id = try tasks.insert(t)

        let fetched = try tasks.fetch(id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Ship v3")
        XCTAssertEqual(fetched?.priority, 9)
        XCTAssertEqual(fetched?.done, false)
    }

    func testInsertManyAndFetchAll() throws {
        let tasks = db.typed(Task.self)
        let items = [
            Task(title: "A", priority: 1, done: false),
            Task(title: "B", priority: 2, done: true),
            Task(title: "C", priority: 3, done: false),
        ]
        let ids = try tasks.insertMany(items)
        XCTAssertEqual(ids.count, 3)

        let all = try tasks.fetchAll()
        XCTAssertEqual(all.count, 3)
    }

    func testUpdate() throws {
        let tasks = db.typed(Task.self)
        var t = Task(title: "Draft", priority: 1, done: false)
        let id = try tasks.insert(t)

        t.title = "Final"
        t.done = true
        try tasks.update(t)

        let fetched = try tasks.fetch(id)
        XCTAssertEqual(fetched?.title, "Final")
        XCTAssertEqual(fetched?.done, true)
    }

    func testUpsert() throws {
        let tasks = db.typed(Task.self)
        let t = Task(title: "New", priority: 5, done: false)
        let wasInsert = try tasks.upsert(t)
        XCTAssertTrue(wasInsert)

        var updated = t
        updated.title = "Updated"
        let wasInsert2 = try tasks.upsert(updated)
        XCTAssertFalse(wasInsert2)

        let fetched = try tasks.fetch(t.id)
        XCTAssertEqual(fetched?.title, "Updated")
    }

    func testDelete() throws {
        let tasks = db.typed(Task.self)
        let t = Task(title: "Temp", priority: 1, done: false)
        let id = try tasks.insert(t)

        try tasks.delete(id)

        let fetched = try tasks.fetch(id)
        XCTAssertNil(fetched)
    }

    // MARK: - TypedStore Query

    func testQueryWithKeyPath() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "Low", priority: 1, done: false),
            Task(title: "Mid", priority: 5, done: false),
            Task(title: "High", priority: 9, done: true),
        ])

        let urgent = try tasks.query()
            .where(\.priority, greaterThan: 4)
            .all()
        XCTAssertEqual(urgent.count, 2)
    }

    func testQueryFirst() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "A", priority: 1, done: false),
            Task(title: "B", priority: 2, done: false),
        ])

        let first = try tasks.query()
            .where(\.done, equals: false)
            .first()
        XCTAssertNotNil(first)
    }

    func testCount() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "A", priority: 1, done: false),
            Task(title: "B", priority: 2, done: true),
        ])

        let count = try tasks.count()
        XCTAssertEqual(count, 2)
    }

    func testCountFiltersByDecodability() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "A", priority: 1, done: false),
            Task(title: "B", priority: 2, done: true),
            Task(title: "C", priority: 3, done: false),
        ])

        let incompatible = BlazeDataRecord([
            "color": .string("red"),
            "weight": .double(3.5),
        ])
        try db.insert(incompatible)
        try db.insert(BlazeDataRecord(["unrelated": .string("data")]))

        let allRaw = try db.fetchAll()
        XCTAssertEqual(allRaw.count, 5, "Raw fetchAll returns every record")

        let count = try tasks.count()
        XCTAssertEqual(count, 3, "TypedStore.count() returns only type-T count")
    }

    // MARK: - Dual-API Coexistence

    func testTypedAndRawCoexist() throws {
        let tasks = db.typed(Task.self)
        let t = Task(title: "Typed", priority: 7, done: false)
        try tasks.insert(t)

        let rawRecord = BlazeDataRecord([
            "title": .string("Raw"),
            "priority": .int(3),
            "done": .bool(true),
        ])
        try db.insert(rawRecord)

        let allRaw = try db.fetchAll()
        XCTAssertEqual(allRaw.count, 2, "Both typed and raw records live in the same collection")

        let typedAll = try tasks.fetchAll()
        XCTAssertEqual(typedAll.count, 2, "TypedStore sees all records that decode to the model")
    }

    func testRawInsertReadableViaTypedFetch() throws {
        let rawID = UUID()
        let rawRecord = BlazeDataRecord([
            "id": .string(rawID.uuidString),
            "title": .string("FromRaw"),
            "priority": .int(5),
            "done": .bool(false),
        ])
        try db.insert(rawRecord, id: rawID)

        let tasks = db.typed(Task.self)
        let fetched = try tasks.fetch(rawID)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "FromRaw")
    }

    // MARK: - Mixed-Type Decodability Filtering (#77)

    func testFetchAllFiltersByDecodability() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "A", priority: 1, done: false),
            Task(title: "B", priority: 2, done: true),
        ])

        let incompatible = BlazeDataRecord([
            "color": .string("red"),
            "weight": .double(3.5),
        ])
        try db.insert(incompatible)

        let allRaw = try db.fetchAll()
        XCTAssertEqual(allRaw.count, 3, "Raw fetchAll returns every record")

        let typedAll = try tasks.fetchAll()
        XCTAssertEqual(typedAll.count, 2, "TypedStore.fetchAll filters out non-decodable records")
        XCTAssertTrue(typedAll.contains { $0.title == "A" })
        XCTAssertTrue(typedAll.contains { $0.title == "B" })
    }

    func testQueryAllFiltersByDecodability() throws {
        let tasks = db.typed(Task.self)
        try tasks.insertMany([
            Task(title: "X", priority: 5, done: false),
            Task(title: "Y", priority: 9, done: true),
        ])

        let incompatible = BlazeDataRecord([
            "unrelated": .string("data"),
        ])
        try db.insert(incompatible)

        let results = try tasks.query()
            .where(\.done, equals: true)
            .all()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Y")
    }

    // MARK: - Sync createIndex

    func testSyncCreateIndex() throws {
        try db.createIndex(on: "priority")
        try db.createIndex(on: ["title", "done"])

        let record = BlazeDataRecord([
            "priority": .int(5),
            "title": .string("Test"),
            "done": .bool(false),
        ])
        let id = try db.insert(record)
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched)
    }
}
