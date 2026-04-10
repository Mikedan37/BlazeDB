import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Comprehensive tests for Codable integration
final class CodableIntegrationTests: XCTestCase {
    
    private var db: BlazeDBClient?
    private var tempURL: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        
        db = try BlazeDBClient(
            name: "CodableTest",
            fileURL: try requireFixture(tempURL),
            password: "TestPassword-123!"
        )
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
        super.tearDown()
    }
    
    // MARK: - Test Models
    
    struct SimpleBug: BlazeStorable {
        var id: UUID
        var title: String
        var priority: Int
        
        init(id: UUID = UUID(), title: String, priority: Int) {
            self.id = id
            self.title = title
            self.priority = priority
        }
    }
    
    struct ComplexBug: BlazeStorable {
        var id: UUID
        var title: String
        var description: String
        var priority: Int
        var status: String
        var createdAt: Date
        var tags: [String]
        var isActive: Bool
        var estimatedHours: Double
        
        init(
            id: UUID = UUID(),
            title: String,
            description: String,
            priority: Int,
            status: String = "open",
            createdAt: Date = Date(),
            tags: [String] = [],
            isActive: Bool = true,
            estimatedHours: Double = 0.0
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.priority = priority
            self.status = status
            self.createdAt = createdAt
            self.tags = tags
            self.isActive = isActive
            self.estimatedHours = estimatedHours
        }
    }
    
    struct OptionalFieldsBug: BlazeStorable {
        var id: UUID
        var title: String
        var description: String?
        var assignee: String?
        var dueDate: Date?
        
        init(id: UUID = UUID(), title: String, description: String? = nil, assignee: String? = nil, dueDate: Date? = nil) {
            self.id = id
            self.title = title
            self.description = description
            self.assignee = assignee
            self.dueDate = dueDate
        }
    }
    
    // MARK: - Basic CRUD
    
    func testCodableInsert() throws {
        let bug = SimpleBug(title: "Login broken", priority: 5)
        
        let id = try requireFixture(db).insert(bug)
        XCTAssertEqual(id, bug.id)
    }
    
    func testCodableFetch() throws {
        let bug = SimpleBug(title: "Test Bug", priority: 3)
        _ = try requireFixture(db).insert(bug)
        
        let fetched = try requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, bug.id)
        XCTAssertEqual(fetched?.title, "Test Bug")
        XCTAssertEqual(fetched?.priority, 3)
    }
    
    func testCodableUpdate() throws {
        var bug = SimpleBug(title: "Original", priority: 1)
        _ = try requireFixture(db).insert(bug)
        
        bug.title = "Updated"
        bug.priority = 10
        try requireFixture(db).update(bug)
        
        let fetched = try requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        XCTAssertEqual(fetched?.title, "Updated")
        XCTAssertEqual(fetched?.priority, 10)
    }
    
    func testCodableDelete() throws {
        let bug = SimpleBug(title: "To Delete", priority: 1)
        _ = try requireFixture(db).insert(bug)
        
        try requireFixture(db).delete(id: bug.id)
        
        let fetched = try requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        XCTAssertNil(fetched)
    }
    
    func testTypedDeleteByModel() throws {
        let bug = SimpleBug(title: "Typed Delete", priority: 7)
        _ = try requireFixture(db).insert(bug)
        
        XCTAssertNotNil(try requireFixture(db).fetch(SimpleBug.self, id: bug.id))
        
        try requireFixture(db).delete(bug)
        
        XCTAssertNil(try requireFixture(db).fetch(SimpleBug.self, id: bug.id))
    }
    
    func testTypedDeleteByModelAsync() async throws {
        let client = try requireFixture(db)
        let bug = SimpleBug(title: "Async Typed Delete", priority: 4)
        _ = try await client.insert(bug)
        
        let before = try await client.fetch(SimpleBug.self, id: bug.id)
        XCTAssertNotNil(before)
        
        try await client.delete(bug)
        
        let after = try await client.fetch(SimpleBug.self, id: bug.id)
        XCTAssertNil(after)
    }
    
    // MARK: - Direct CRUD Golden Path
    
    func testDirectCRUDGoldenPath() throws {
        let db = try requireFixture(self.db)
        
        var user = SimpleBug(title: "Alice", priority: 5)
        try db.insert(user)
        
        let fetched = try db.fetch(SimpleBug.self, id: user.id)
        XCTAssertEqual(fetched?.title, "Alice")
        
        let all = try db.fetchAll(SimpleBug.self)
        XCTAssertTrue(all.contains { $0.id == user.id })
        
        user.title = "Alice (updated)"
        user.priority = 9
        try db.update(user)
        XCTAssertEqual(try db.fetch(SimpleBug.self, id: user.id)?.title, "Alice (updated)")
        
        let wasInsert = try db.upsert(user)
        XCTAssertFalse(wasInsert)
        
        try db.delete(user)
        XCTAssertNil(try db.fetch(SimpleBug.self, id: user.id))
    }
    
    // MARK: - Complex Types
    
    func testComplexCodableType() throws {
        let bug = ComplexBug(
            title: "Complex Bug",
            description: "This has many fields",
            priority: 7,
            status: "in_progress",
            createdAt: Date(),
            tags: ["critical", "ui", "frontend"],
            isActive: true,
            estimatedHours: 8.5
        )
        
        // Capture the returned ID
        let id = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(ComplexBug.self, id: id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Complex Bug")
        XCTAssertEqual(fetched?.description, "This has many fields")
        XCTAssertEqual(fetched?.priority, 7)
        XCTAssertEqual(fetched?.status, "in_progress")
        XCTAssertEqual(fetched?.tags.count, 3)
        XCTAssertTrue(fetched?.isActive ?? false)
        XCTAssertEqual(fetched?.estimatedHours ?? 0, 8.5, accuracy: 0.01)
    }
    
    func testOptionalFields() throws {
        // With optional fields nil
        let bug1 = OptionalFieldsBug(title: "Bug 1")
        _ = try requireFixture(db).insert(bug1)
        
        let fetched1 = try requireFixture(db).fetch(OptionalFieldsBug.self, id: bug1.id)
        XCTAssertNil(fetched1?.description)
        XCTAssertNil(fetched1?.assignee)
        XCTAssertNil(fetched1?.dueDate)
        
        // With optional fields set
        let bug2 = OptionalFieldsBug(
            title: "Bug 2",
            description: "Has description",
            assignee: "Alice",
            dueDate: Date()
        )
        _ = try requireFixture(db).insert(bug2)
        
        let fetched2 = try requireFixture(db).fetch(OptionalFieldsBug.self, id: bug2.id)
        XCTAssertEqual(fetched2?.description, "Has description")
        XCTAssertEqual(fetched2?.assignee, "Alice")
        XCTAssertNotNil(fetched2?.dueDate)
    }
    
    // MARK: - Batch Operations
    
    func testCodableInsertMany() throws {
        let bugs = [
            SimpleBug(title: "Bug 1", priority: 1),
            SimpleBug(title: "Bug 2", priority: 2),
            SimpleBug(title: "Bug 3", priority: 3)
        ]
        
        let ids = try requireFixture(db).insertMany(bugs)
        XCTAssertEqual(ids.count, 3)
        
        let all = try requireFixture(db).fetchAll(SimpleBug.self)
        XCTAssertEqual(all.count, 3)
    }
    
    func testCodableFetchAll() throws {
        let bugs = [
            SimpleBug(title: "Bug 1", priority: 1),
            SimpleBug(title: "Bug 2", priority: 2)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        let fetched = try requireFixture(db).fetchAll(SimpleBug.self)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertTrue(fetched.contains { $0.title == "Bug 1" })
        XCTAssertTrue(fetched.contains { $0.title == "Bug 2" })
    }
    
    // MARK: - Queries
    
    func testCodableQuery() throws {
        let bugs = [
            SimpleBug(title: "Open Bug", priority: 5),
            SimpleBug(title: "Closed Bug", priority: 3)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        // Use Codable query builder with KeyPaths
        let highPriority = try requireFixture(db).query(SimpleBug.self)
            .where(\.priority, greaterThan: 4)
            .all()
        
        XCTAssertEqual(highPriority.count, 1)
        XCTAssertEqual(highPriority.first?.title, "Open Bug")
    }
    
    func testCodableQueryFirst() throws {
        let bugs = [
            SimpleBug(title: "A", priority: 1),
            SimpleBug(title: "B", priority: 2)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        let first = try requireFixture(db).query(SimpleBug.self)
            .where(\.priority, equals: 2)
            .first()
        
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.title, "B")
    }
    
    func testCodableQueryExists() throws {
        let bug = SimpleBug(title: "Test", priority: 5)
        _ = try requireFixture(db).insert(bug)
        
        let exists = try requireFixture(db).query(SimpleBug.self)
            .where(\.priority, greaterThan: 4)
            .exists()
        
        XCTAssertTrue(exists)
        
        let notExists = try requireFixture(db).query(SimpleBug.self)
            .where(\.priority, greaterThan: 10)
            .exists()
        
        XCTAssertFalse(notExists)
    }
    
    func testCodableQueryCount() throws {
        let bugs = [
            SimpleBug(title: "A", priority: 1),
            SimpleBug(title: "B", priority: 5),
            SimpleBug(title: "C", priority: 10)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        let count = try requireFixture(db).query(SimpleBug.self)
            .where(\.priority, greaterThan: 3)
            .count()
        
        XCTAssertEqual(count, 2)
    }
    
    // MARK: - Mixed Usage (Codable + Dynamic)
    
    func testMixedCodableAndDynamic() throws {
        // Insert Codable
        let codableBug = SimpleBug(title: "Codable Bug", priority: 5)
        _ = try requireFixture(db).insert(codableBug)
        
        // Insert Dynamic
        let dynamicBug = BlazeDataRecord {
            "title" => "Dynamic Bug"
            "priority" => 3
            "extraField" => "This doesn't exist in SimpleBug"
        }
        let dynamicID = try requireFixture(db).insert(dynamicBug)
        
        // Fetch as Codable (should only get valid SimpleBug)
        let codableFetched = try requireFixture(db).fetch(SimpleBug.self, id: codableBug.id)
        XCTAssertNotNil(codableFetched)
        
        // Fetch dynamic as dynamic
        let dynamicFetched = try requireFixture(db).fetch(id: dynamicID)
        XCTAssertNotNil(dynamicFetched)
        XCTAssertEqual(dynamicFetched?.storage["extraField"]?.stringValue, "This doesn't exist in SimpleBug")
        
        // FetchAll should return valid Codable objects only (or throw on invalid)
        let allDynamic = try requireFixture(db).fetchAll()
        XCTAssertEqual(allDynamic.count, 2)
    }
    
    // MARK: - Date Handling
    
    func testDateRoundTrip() throws {
        let now = Date()
        let bug = ComplexBug(
            title: "Date Test",
            description: "Test",
            priority: 1,
            createdAt: now
        )
        
        _ = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(ComplexBug.self, id: bug.id)
        
        // Dates should match within 1 second (ISO8601 precision)
        XCTAssertNotNil(fetched?.createdAt)
        XCTAssertEqual(
            fetched!.createdAt.timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 1.0
        )
    }
    
    // MARK: - Array Fields
    
    func testArrayFields() throws {
        let bug = ComplexBug(
            title: "Array Test",
            description: "Test",
            priority: 1,
            tags: ["tag1", "tag2", "tag3"]
        )
        
        _ = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(ComplexBug.self, id: bug.id)
        
        XCTAssertEqual(fetched?.tags.count, 3)
        XCTAssertTrue(fetched?.tags.contains("tag1") ?? false)
        XCTAssertTrue(fetched?.tags.contains("tag2") ?? false)
    }
    
    // MARK: - Async Operations
    
    func testCodableAsyncInsert() async throws {
        let bug = SimpleBug(title: "Async Bug", priority: 5)
        
        let id = try await requireFixture(db).insert(bug)
        XCTAssertEqual(id, bug.id)
        
        let fetched = try await requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        XCTAssertEqual(fetched?.title, "Async Bug")
    }
    
    func testCodableAsyncQuery() async throws {
        let bugs = [
            SimpleBug(title: "A", priority: 1),
            SimpleBug(title: "B", priority: 5),
            SimpleBug(title: "C", priority: 10)
        ]
        
        _ = try await requireFixture(db).insertMany(bugs)
        
        let highPriority = try await requireFixture(db).query(SimpleBug.self)
            .where(\.priority, greaterThan: 3)
            .all()
        
        XCTAssertEqual(highPriority.count, 2)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyOptionalFields() throws {
        let bug = OptionalFieldsBug(title: "Minimal")
        _ = try requireFixture(db).insert(bug)
        
        let fetched = try requireFixture(db).fetch(OptionalFieldsBug.self, id: bug.id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Minimal")
        XCTAssertNil(fetched?.description)
        XCTAssertNil(fetched?.assignee)
        XCTAssertNil(fetched?.dueDate)
    }
    
    func testEmptyArrays() throws {
        let bug = ComplexBug(
            title: "No Tags",
            description: "Test",
            priority: 1,
            tags: []  // Empty array
        )
        
        _ = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(ComplexBug.self, id: bug.id)
        
        XCTAssertEqual(fetched?.tags.count, 0)
    }
    
    func testUnicodeInCodable() throws {
        let bug = SimpleBug(title: "🐛 Bug with emoji and 中文", priority: 1)
        
        _ = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        
        XCTAssertEqual(fetched?.title, "🐛 Bug with emoji and 中文")
    }
    
    // MARK: - Batch Operations
    
    func testCodableBatchInsert() throws {
        let bugs = (0..<100).map { i in
            SimpleBug(title: "Bug \(i)", priority: i % 10)
        }
        
        let ids = try requireFixture(db).insertMany(bugs)
        XCTAssertEqual(ids.count, 100)
        
        let all = try requireFixture(db).fetchAll(SimpleBug.self)
        XCTAssertEqual(all.count, 100)
    }
    
    func testCodableBatchUpdate() throws {
        var bugs = [
            SimpleBug(title: "A", priority: 1),
            SimpleBug(title: "B", priority: 2),
            SimpleBug(title: "C", priority: 3)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        // Update all priorities
        for i in 0..<bugs.count {
            bugs[i].priority = 10
        }
        
        try requireFixture(db).updateMany(bugs)
        
        let fetched = try requireFixture(db).fetchAll(SimpleBug.self)
        XCTAssertTrue(fetched.allSatisfy { $0.priority == 10 })
    }
    
    // MARK: - Query Filtering
    
    func testCodableQueryMultipleFilters() throws {
        let bugs = [
            ComplexBug(title: "A", description: "Test", priority: 1, status: "open"),
            ComplexBug(title: "B", description: "Test", priority: 5, status: "open"),
            ComplexBug(title: "C", description: "Test", priority: 10, status: "closed"),
            ComplexBug(title: "D", description: "Test", priority: 7, status: "open")
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        let filtered = try requireFixture(db).query(ComplexBug.self)
            .where(\.status, equals: "open")
            .where(\.priority, greaterThan: 3)
            .all()
        
        XCTAssertEqual(filtered.count, 2)  // B and D
        XCTAssertTrue(filtered.allSatisfy { $0.status == "open" })
        XCTAssertTrue(filtered.allSatisfy { $0.priority > 3 })
    }
    
    func testCodableQuerySorting() throws {
        let bugs = [
            SimpleBug(title: "Low", priority: 1),
            SimpleBug(title: "High", priority: 10),
            SimpleBug(title: "Medium", priority: 5)
        ]
        
        _ = try requireFixture(db).insertMany(bugs)
        
        let sorted = try requireFixture(db).query(SimpleBug.self)
            .orderBy(\.priority, descending: true)
            .all()
        
        XCTAssertEqual(sorted[0].title, "High")
        XCTAssertEqual(sorted[1].title, "Medium")
        XCTAssertEqual(sorted[2].title, "Low")
    }
    
    func testCodableQueryLimitOffset() throws {
        let bugs = (0..<10).map { SimpleBug(title: "Bug \($0)", priority: $0) }
        _ = try requireFixture(db).insertMany(bugs)
        
        let page1 = try requireFixture(db).query(SimpleBug.self)
            .limit(3)
            .all()
        
        XCTAssertEqual(page1.count, 3)
        
        let page2 = try requireFixture(db).query(SimpleBug.self)
            .offset(3)
            .limit(3)
            .all()
        
        XCTAssertEqual(page2.count, 3)
        XCTAssertNotEqual(page1.first?.id, page2.first?.id)
    }
    
    // MARK: - Conversion Edge Cases
    
    func testLargeNumbers() throws {
        struct NumberTest: BlazeStorable {
            var id: UUID
            var bigInt: Int
            var bigDouble: Double
            
            init(id: UUID = UUID(), bigInt: Int, bigDouble: Double) {
                self.id = id
                self.bigInt = bigInt
                self.bigDouble = bigDouble
            }
        }
        
        let test = NumberTest(
            bigInt: Int.max - 1000,
            bigDouble: Double.pi * 1_000_000
        )
        
        _ = try requireFixture(db).insert(test)
        let fetched = try requireFixture(db).fetch(NumberTest.self, id: test.id)
        
        XCTAssertEqual(fetched?.bigInt, Int.max - 1000)
        XCTAssertEqual(fetched?.bigDouble ?? 0, Double.pi * 1_000_000, accuracy: 0.001)
    }
    
    func testSpecialCharacters() throws {
        let bug = SimpleBug(
            title: "Special: \n\t\"quotes\" 'apostrophe' \\backslash",
            priority: 1
        )
        
        _ = try requireFixture(db).insert(bug)
        let fetched = try requireFixture(db).fetch(SimpleBug.self, id: bug.id)
        
        XCTAssertEqual(fetched?.title, bug.title)
    }
    
    // MARK: - Performance
    
    func testCodablePerformance() throws {
        // Measure Codable insert
        measure {
            do {
                let bugs = (0..<100).map { SimpleBug(title: "Bug \($0)", priority: $0 % 10) }
                _ = try requireFixture(db).insertMany(bugs)
                _ = try requireFixture(db).deleteMany { _ in true }
            } catch {
                XCTFail("measure block failed: \(error)")
            }
        }
    }
    
    func testCodableVsDynamicPerformance() throws {
        // Codable approach
        let codableStart = Date()
        let codableBugs = (0..<100).map { SimpleBug(title: "Bug \($0)", priority: $0) }
        _ = try requireFixture(db).insertMany(codableBugs)
        let codableTime = Date().timeIntervalSince(codableStart)
        
        _ = try requireFixture(db).deleteMany { _ in true }
        
        // Dynamic approach
        let dynamicStart = Date()
        let dynamicBugs = (0..<100).map { i in
            BlazeDataRecord {
                "title" => "Bug \(i)"
                "priority" => i
            }
        }
        _ = try requireFixture(db).insertMany(dynamicBugs)
        let dynamicTime = Date().timeIntervalSince(dynamicStart)
        
        // CI timing can fluctuate heavily; guard against pathological regressions
        // rather than requiring near-identical micro-benchmark timings.
        XCTAssertLessThan(codableTime, dynamicTime * 8.0)
        
        print("Codable: \(codableTime * 1000)ms, Dynamic: \(dynamicTime * 1000)ms")
    }
    
    // MARK: - Error Handling
    
    func testInvalidConversion() throws {
        // Insert a dynamic record that can't convert to SimpleBug
        let invalidRecord = BlazeDataRecord {
            "title" => "Missing priority field"
            // Missing 'priority' required field
        }
        
        let id = try requireFixture(db).insert(invalidRecord)
        
        // Fetching as SimpleBug should throw or return nil
        XCTAssertThrowsError(try requireFixture(db).fetch(SimpleBug.self, id: id))
    }
}

