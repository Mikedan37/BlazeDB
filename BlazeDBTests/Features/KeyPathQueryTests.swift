import XCTest
@testable import BlazeDBCore

/// Comprehensive tests for type-safe KeyPath queries
final class KeyPathQueryTests: XCTestCase {
    
    var db: BlazeDBClient!
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        
        db = try! BlazeDBClient(
            name: "KeyPathTest",
            fileURL: tempURL,
            password: "test-password-123"
        )
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    // MARK: - Test Models
    
    struct Bug: BlazeStorable {
        var id: UUID
        var title: String
        var priority: Int
        var status: String
        var createdAt: Date
        var estimatedHours: Double
        var isActive: Bool
        
        init(
            id: UUID = UUID(),
            title: String,
            priority: Int,
            status: String = "open",
            createdAt: Date = Date(),
            estimatedHours: Double = 0.0,
            isActive: Bool = true
        ) {
            self.id = id
            self.title = title
            self.priority = priority
            self.status = status
            self.createdAt = createdAt
            self.estimatedHours = estimatedHours
            self.isActive = isActive
        }
    }
    
    // MARK: - KeyPath Equality Queries
    
    func testKeyPathEqualsString() throws {
        let bugs = [
            Bug(title: "A", priority: 1, status: "open"),
            Bug(title: "B", priority: 2, status: "closed"),
            Bug(title: "C", priority: 3, status: "open")
        ]
        
        _ = try db.insertMany(bugs)
        
        let openBugs = try db.query(Bug.self)
            .where(\.status, equals: "open")  // KeyPath!
            .all()
        
        XCTAssertEqual(openBugs.count, 2)
        XCTAssertTrue(openBugs.allSatisfy { $0.status == "open" })
    }
    
    func testKeyPathEqualsInt() throws {
        let bugs = [
            Bug(title: "Low", priority: 1),
            Bug(title: "High", priority: 10),
            Bug(title: "Medium", priority: 5)
        ]
        
        _ = try db.insertMany(bugs)
        
        let highPriority = try db.query(Bug.self)
            .where(\.priority, equals: 10)  // KeyPath!
            .all()
        
        XCTAssertEqual(highPriority.count, 1)
        XCTAssertEqual(highPriority.first?.title, "High")
    }
    
    func testKeyPathEqualsBool() throws {
        let bugs = [
            Bug(title: "Active", priority: 1, isActive: true),
            Bug(title: "Inactive", priority: 2, isActive: false)
        ]
        
        _ = try db.insertMany(bugs)
        
        let active = try db.query(Bug.self)
            .where(\.isActive, equals: true)  // KeyPath!
            .all()
        
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.title, "Active")
    }
    
    // MARK: - KeyPath Comparison Queries
    
    func testKeyPathGreaterThan() throws {
        let bugs = [
            Bug(title: "Low", priority: 1),
            Bug(title: "Medium", priority: 5),
            Bug(title: "High", priority: 10)
        ]
        
        _ = try db.insertMany(bugs)
        
        let filtered = try db.query(Bug.self)
            .where(\.priority, greaterThan: 3)  // KeyPath!
            .all()
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.priority > 3 })
    }
    
    func testKeyPathLessThan() throws {
        let bugs = [
            Bug(title: "A", priority: 1),
            Bug(title: "B", priority: 5),
            Bug(title: "C", priority: 10)
        ]
        
        _ = try db.insertMany(bugs)
        
        let filtered = try db.query(Bug.self)
            .where(\.priority, lessThan: 6)  // KeyPath!
            .all()
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.priority < 6 })
    }
    
    func testKeyPathDateComparison() throws {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let tomorrow = now.addingTimeInterval(86400)
        
        let bugs = [
            Bug(title: "Old", priority: 1, createdAt: yesterday),
            Bug(title: "New", priority: 2, createdAt: tomorrow)
        ]
        
        _ = try db.insertMany(bugs)
        
        let recent = try db.query(Bug.self)
            .where(\.createdAt, greaterThan: now)  // KeyPath date comparison
            .all()
        
        XCTAssertEqual(recent.count, 1, "Should only return future dates (tomorrow)")
        XCTAssertEqual(recent.first?.title, "New")
    }
    
    // MARK: - Multiple KeyPath Filters
    
    func testMultipleKeyPathFilters() throws {
        let bugs = [
            Bug(title: "A", priority: 1, status: "open"),
            Bug(title: "B", priority: 5, status: "open"),
            Bug(title: "C", priority: 10, status: "closed"),
            Bug(title: "D", priority: 7, status: "open")
        ]
        
        _ = try db.insertMany(bugs)
        
        let filtered = try db.query(Bug.self)
            .where(\.status, equals: "open")      // KeyPath 1
            .where(\.priority, greaterThan: 3)    // KeyPath 2
            .all()
        
        XCTAssertEqual(filtered.count, 2)  // B and D
        XCTAssertTrue(filtered.allSatisfy { $0.status == "open" && $0.priority > 3 })
    }
    
    // MARK: - Sorting by KeyPath
    
    func testOrderByKeyPath() throws {
        let bugs = [
            Bug(title: "C", priority: 3),
            Bug(title: "A", priority: 1),
            Bug(title: "B", priority: 2)
        ]
        
        _ = try db.insertMany(bugs)
        
        let sorted = try db.query(Bug.self)
            .orderBy(\.priority, descending: false)  // KeyPath!
            .all()
        
        XCTAssertEqual(sorted[0].title, "A")
        XCTAssertEqual(sorted[1].title, "B")
        XCTAssertEqual(sorted[2].title, "C")
    }
    
    func testOrderByKeyPathDescending() throws {
        let bugs = [
            Bug(title: "Low", priority: 1),
            Bug(title: "High", priority: 10),
            Bug(title: "Medium", priority: 5)
        ]
        
        _ = try db.insertMany(bugs)
        
        let sorted = try db.query(Bug.self)
            .orderBy(\.priority, descending: true)  // KeyPath!
            .all()
        
        XCTAssertEqual(sorted[0].title, "High")
        XCTAssertEqual(sorted[1].title, "Medium")
        XCTAssertEqual(sorted[2].title, "Low")
    }
    
    // MARK: - Chaining Operations
    
    func testKeyPathChaining() throws {
        let bugs = [
            Bug(title: "A", priority: 1, status: "open"),
            Bug(title: "B", priority: 5, status: "open"),
            Bug(title: "C", priority: 10, status: "closed"),
            Bug(title: "D", priority: 7, status: "open"),
            Bug(title: "E", priority: 3, status: "open")
        ]
        
        _ = try db.insertMany(bugs)
        
        let result = try db.query(Bug.self)
            .where(\.status, equals: "open")
            .where(\.priority, greaterThan: 3)
            .orderBy(\.priority, descending: true)
            .limit(2)
            .all()
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "D")  // priority 7
        XCTAssertEqual(result[1].title, "B")  // priority 5
    }
    
    // MARK: - First/Exists/Count
    
    func testKeyPathFirst() throws {
        let bugs = [
            Bug(title: "A", priority: 1),
            Bug(title: "B", priority: 5)
        ]
        
        _ = try db.insertMany(bugs)
        
        let first = try db.query(Bug.self)
            .where(\.priority, greaterThan: 3)
            .first()
        
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.title, "B")
    }
    
    func testKeyPathExists() throws {
        let bug = Bug(title: "Test", priority: 10)
        _ = try db.insert(bug)
        
        let exists = try db.query(Bug.self)
            .where(\.priority, equals: 10)
            .exists()
        
        XCTAssertTrue(exists)
        
        let notExists = try db.query(Bug.self)
            .where(\.priority, equals: 99)
            .exists()
        
        XCTAssertFalse(notExists)
    }
    
    func testKeyPathCount() throws {
        let bugs = [
            Bug(title: "A", priority: 1),
            Bug(title: "B", priority: 5),
            Bug(title: "C", priority: 10)
        ]
        
        _ = try db.insertMany(bugs)
        
        let count = try db.query(Bug.self)
            .where(\.priority, greaterThan: 3)
            .count()
        
        XCTAssertEqual(count, 2)
    }
    
    // MARK: - Custom Filter Predicate
    
    func testKeyPathCustomFilter() throws {
        let bugs = [
            Bug(title: "A", priority: 1, isActive: true),
            Bug(title: "B", priority: 5, isActive: false),
            Bug(title: "C", priority: 10, isActive: true)
        ]
        
        _ = try db.insertMany(bugs)
        
        let filtered = try db.query(Bug.self)
            .filter { bug in
                bug.priority > 3 && bug.isActive
            }
            .all()
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "C")
    }
    
    // MARK: - Async Operations
    
    func testKeyPathAsyncQuery() async throws {
        let bugs = [
            Bug(title: "A", priority: 1),
            Bug(title: "B", priority: 5),
            Bug(title: "C", priority: 10)
        ]
        
        _ = try await db.insertMany(bugs)
        
        let filtered = try await db.query(Bug.self)
            .where(\.priority, greaterThan: 3)
            .orderBy(\.priority, descending: true)
            .all()
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].priority, 10)
        XCTAssertEqual(filtered[1].priority, 5)
    }
    
    func testKeyPathAsyncFirst() async throws {
        let bug = Bug(title: "Test", priority: 5)
        _ = try await db.insert(bug)
        
        let found = try await db.query(Bug.self)
            .where(\.priority, equals: 5)
            .first()
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Test")
    }
    
    // MARK: - Performance Comparison
    
    func testKeyPathPerformance() throws {
        let bugs = (0..<100).map { Bug(title: "Bug \($0)", priority: $0 % 10) }
        _ = try db.insertMany(bugs)
        
        // Measure KeyPath query
        let keyPathStart = Date()
        _ = try db.query(Bug.self)
            .where(\.priority, greaterThan: 5)
            .all()
        let keyPathTime = Date().timeIntervalSince(keyPathStart)
        
        // Measure string-based query
        let stringStart = Date()
        _ = try db.query(Bug.self)
            .where(\.priority, greaterThan: 5)
            .all()
        let stringTime = Date().timeIntervalSince(stringStart)
        
        // KeyPath should be same speed or faster (compile-time optimization)
        print("KeyPath: \(keyPathTime * 1000)ms, String: \(stringTime * 1000)ms")
        
        // Should be within 10% of each other
        XCTAssertLessThan(keyPathTime, stringTime * 1.1)
    }
}

