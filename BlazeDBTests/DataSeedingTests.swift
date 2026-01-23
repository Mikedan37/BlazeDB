import XCTest
@testable import BlazeDBCore

/// Comprehensive tests for data seeding and fixtures
final class DataSeedingTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        
        db = try! BlazeDBClient(
            name: "SeedTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
        
        // Clear factory registry before each test
        FactoryRegistry.shared.clear()
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        FactoryRegistry.shared.clear()
        super.tearDown()
    }
    
    // MARK: - Test Models
    
    struct Bug: BlazeStorable {
        var id: UUID
        var title: String
        var priority: Int
        var status: String
        
        init(id: UUID = UUID(), title: String, priority: Int, status: String = "open") {
            self.id = id
            self.title = title
            self.priority = priority
            self.status = status
        }
    }
    
    // MARK: - Basic Seeding
    
    func testSeedBasic() throws {
        let bugs = try db.seed(Bug.self, count: 10) { i in
            Bug(title: "Bug \(i)", priority: i % 5)
        }
        
        XCTAssertEqual(bugs.count, 10)
        
        let all = try db.fetchAll(Bug.self)
        XCTAssertEqual(all.count, 10)
    }
    
    func testSeedWithRandomData() throws {
        let bugs = try db.seed(Bug.self, count: 20) { i in
            Bug(
                title: "Bug \(i)",
                priority: Int.random(in: 1...10),
                status: ["open", "closed", "in_progress"].randomElement()!
            )
        }
        
        XCTAssertEqual(bugs.count, 20)
        
        // Verify variety
        let priorities = Set(bugs.map { $0.priority })
        XCTAssertGreaterThan(priorities.count, 3)  // Should have variety
        
        let statuses = Set(bugs.map { $0.status })
        XCTAssertGreaterThan(statuses.count, 1)  // Should have variety
    }
    
    func testSeedDynamicRecords() throws {
        let ids = try db.seed(count: 15) { i in
            BlazeDataRecord {
                "index" => i
                "title" => "Record \(i)"
                "randomValue" => Int.random(in: 1...100)
            }
        }
        
        XCTAssertEqual(ids.count, 15)
        
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 15)
    }
    
    // MARK: - Factories
    
    func testFactoryRegistration() throws {
        // Register factory
        db.factory(Bug.self) { i in
            Bug(title: "Factory Bug \(i)", priority: 5, status: "open")
        }
        
        // Create using factory
        let bugs = try db.create(Bug.self, count: 10)
        
        XCTAssertEqual(bugs.count, 10)
        XCTAssertTrue(bugs.allSatisfy { $0.priority == 5 })
        XCTAssertTrue(bugs.allSatisfy { $0.status == "open" })
    }
    
    func testFactorySingleCreate() throws {
        db.factory(Bug.self) { i in
            Bug(title: "Single Bug", priority: 1)
        }
        
        let bug = try db.create(Bug.self)  // Create just one
        
        XCTAssertEqual(bug.title, "Single Bug")
        
        let all = try db.fetchAll(Bug.self)
        XCTAssertEqual(all.count, 1)
    }
    
    func testFactoryWithoutRegistration() throws {
        // Should throw if no factory registered
        XCTAssertThrowsError(try db.create(Bug.self))
    }
    
    func testFactoryOverride() throws {
        // Register first factory
        db.factory(Bug.self) { i in
            Bug(title: "First", priority: 1)
        }
        
        // Override with new factory
        db.factory(Bug.self) { i in
            Bug(title: "Second", priority: 2)
        }
        
        let bug = try db.create(Bug.self)
        XCTAssertEqual(bug.title, "Second")
        XCTAssertEqual(bug.priority, 2)
    }
    
    // MARK: - Fixtures from JSON
    
    func testLoadFixturesFromJSON() throws {
        // Create temporary JSON file
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixtures.json")
        
        let json = """
        [
            {"id": "\(UUID().uuidString)", "title": "Bug 1", "priority": 5, "status": "open"},
            {"id": "\(UUID().uuidString)", "title": "Bug 2", "priority": 3, "status": "closed"}
        ]
        """
        
        try json.data(using: .utf8)?.write(to: jsonURL)
        
        let bugs = try db.loadFixtures(Bug.self, from: jsonURL)
        
        XCTAssertEqual(bugs.count, 2)
        XCTAssertEqual(bugs[0].title, "Bug 1")
        XCTAssertEqual(bugs[1].title, "Bug 2")
        
        // Cleanup
        try? FileManager.default.removeItem(at: jsonURL)
    }
    
    func testLoadDynamicFixtures() throws {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynamic-fixtures.json")
        
        let json = """
        [
            {"title": "Dynamic 1", "customField": "value1"},
            {"title": "Dynamic 2", "customField": "value2"}
        ]
        """
        
        try json.data(using: .utf8)?.write(to: jsonURL)
        
        let ids = try db.loadFixtures(from: jsonURL)
        
        XCTAssertEqual(ids.count, 2)
        
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 2)
        
        try? FileManager.default.removeItem(at: jsonURL)
    }
    
    // MARK: - Snapshots
    
    func testSnapshot() throws {
        // Insert initial data
        _ = try db.seed(Bug.self, count: 5) { i in
            Bug(title: "Bug \(i)", priority: i)
        }
        
        // Create snapshot
        let snapshot = try db.snapshot()
        
        XCTAssertEqual(snapshot.records.count, 5)
    }
    
    func testSnapshotRestore() throws {
        // Insert initial data
        _ = try db.seed(Bug.self, count: 3) { i in
            Bug(title: "Original \(i)", priority: i)
        }
        
        // Create snapshot
        let snapshot = try db.snapshot()
        
        // Modify database
        _ = try db.seed(Bug.self, count: 5) { i in
            Bug(title: "New \(i)", priority: i)
        }
        
        let beforeRestore = try db.fetchAll()
        XCTAssertEqual(beforeRestore.count, 8)  // 3 + 5
        
        // Restore snapshot
        try db.restore(snapshot)
        
        let afterRestore = try db.fetchAll(Bug.self)
        XCTAssertEqual(afterRestore.count, 3)  // Back to original
        XCTAssertTrue(afterRestore.allSatisfy { $0.title.starts(with: "Original") })
    }
    
    // MARK: - Random Data Generators
    
    func testRandomDataGenerators() throws {
        let ids = try db.seedRandom(count: 20, fields: [
            "title": { .string(RandomData.bugTitle()) },
            "priority": { .int(RandomData.priority()) },
            "status": { .string(RandomData.status()) },
            "assignee": { .string(RandomData.name()) },
            "tags": { .array(RandomData.tags().map { .string($0) }) },
            "createdAt": { .date(RandomData.pastDate(days: 30)) }
        ])
        
        XCTAssertEqual(ids.count, 20)
        
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 20)
        
        // Verify randomness (should have variety)
        let priorities = Set(all.map { $0.storage["priority"]?.intValue ?? 0 })
        XCTAssertGreaterThan(priorities.count, 3)
        
        let statuses = Set(all.map { $0.storage["status"]?.stringValue ?? "" })
        XCTAssertGreaterThan(statuses.count, 1)
    }
    
    // MARK: - Async Operations
    
    func testAsyncSeed() async throws {
        let bugs = try await db.seed(Bug.self, count: 10) { i in
            Bug(title: "Async Bug \(i)", priority: i)
        }
        
        XCTAssertEqual(bugs.count, 10)
        
        let all = try await db.fetchAll(Bug.self)
        XCTAssertEqual(all.count, 10)
    }
    
    func testAsyncFactory() async throws {
        db.factory(Bug.self) { i in
            Bug(title: "Async Factory \(i)", priority: 3)
        }
        
        let bugs = try await db.create(Bug.self, count: 5)
        XCTAssertEqual(bugs.count, 5)
    }
    
    func testAsyncSnapshot() async throws {
        _ = try await db.seed(Bug.self, count: 3) { i in
            Bug(title: "Test \(i)", priority: i)
        }
        
        let snapshot = try await db.snapshot()
        XCTAssertEqual(snapshot.records.count, 3)
        
        _ = try await db.seed(Bug.self, count: 5) { i in
            Bug(title: "More \(i)", priority: i)
        }
        
        try await db.restore(snapshot)
        
        let restored = try await db.fetchAll(Bug.self)
        XCTAssertEqual(restored.count, 3)
    }
    
    // MARK: - Large Data Seeding
    
    func testSeedLargeDataset() throws {
        let bugs = try db.seed(Bug.self, count: 1000) { i in
            Bug(
                title: "Bug \(i)",
                priority: i % 10,
                status: ["open", "closed"][i % 2]
            )
        }
        
        XCTAssertEqual(bugs.count, 1000)
        
        let openCount = try db.query(Bug.self)
            .where(\.status, equals: "open")
            .count()
        
        XCTAssertEqual(openCount, 500)
    }
    
    func testSeedPerformance() throws {
        measure {
            _ = try! db.seed(Bug.self, count: 100) { i in
                Bug(title: "Perf Bug \(i)", priority: i % 10)
            }
            
            // Cleanup
            _ = try! db.deleteMany { _ in true }
        }
    }
    
    // MARK: - Edge Cases
    
    func testSeedZeroCount() throws {
        let bugs = try db.seed(Bug.self, count: 0) { i in
            Bug(title: "Should not create", priority: 1)
        }
        
        XCTAssertEqual(bugs.count, 0)
        
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 0)
    }
    
    func testSeedWithThrowingGenerator() throws {
        XCTAssertThrowsError(
            try db.seed(Bug.self, count: 10) { i in
                if i == 5 {
                    throw NSError(domain: "test", code: 1)
                }
                return Bug(title: "Bug \(i)", priority: i)
            }
        )
    }
    
    func testSnapshotEmptyDatabase() throws {
        let snapshot = try db.snapshot()
        XCTAssertEqual(snapshot.records.count, 0)
        
        // Restore empty snapshot
        _ = try db.insert(BlazeDataRecord { "title" => "Test" })
        
        try db.restore(snapshot)
        
        let all = try db.fetchAll()
        XCTAssertEqual(all.count, 0)
    }
}

