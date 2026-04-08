//
//  MVCCRegressionTests.swift
//  BlazeDBTests
//
//  Regression tests: Run ALL existing functionality with MVCC enabled
//
//  This ensures enabling MVCC doesn't break existing features.
//  If these pass, MVCC is safe to ship.
//
//  Created: 2025-11-13
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private final class MVCCRegressionLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class MVCCRegressionTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUp() async throws {
        try await super.setUp()
        
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCRegression-\(testID).blazedb")
        tempURL = url
        
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
        
        db = try BlazeDBClient(name: "mvcc_regression", fileURL: url, password: "SecureTestDB-456!")
        try requireFixture(db).setMVCCEnabled(true)
        
        // CRITICAL: Verify MVCC is enabled
        XCTAssertTrue(try requireFixture(db).isMVCCEnabled(), "MVCC must be enabled for these tests!")
    }
    
    override func tearDown() {
        if let url = tempURL {
            cleanupBlazeDB(&db, at: url)
        }
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Operations Regression
    
    func testRegression_InsertFetchRoundTrip() throws {
        let record = BlazeDataRecord([
            "name": .string("Test"),
            "age": .int(30),
            "active": .bool(true),
            "score": .double(95.5)
        ])
        
        let id = try requireFixture(db).insert(record)
        let fetched = try requireFixture(db).fetch(id: id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["name"]?.stringValue, "Test")
        XCTAssertEqual(fetched?["age"]?.intValue, 30)
        XCTAssertEqual(fetched?["active"]?.boolValue, true)
        XCTAssertEqual(fetched?["score"]?.doubleValue, 95.5)
    }
    
    func testRegression_Count() throws {
        // Insert 50 records
        for i in 0..<50 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let count = try requireFixture(db).count()
        XCTAssertEqual(count, 50, "Count must work with MVCC")
    }
    
    func testRegression_Contains() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["test": .string("value")]))
        
        // Check record exists by fetching it
        XCTAssertNotNil(try requireFixture(db).fetch(id: id), "Record should exist")
        
        try requireFixture(db).delete(id: id)
        
        // After delete, should not exist
        XCTAssertNil(try requireFixture(db).fetch(id: id), "Record should not exist after delete")
    }
    
    func testRegression_Update() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord([
            "name": .string("Original"),
            "value": .int(100)
        ]))
        
        try requireFixture(db).update(id: id, with: BlazeDataRecord([
            "name": .string("Updated")
        ]))
        
        let updated = try requireFixture(db).fetch(id: id)
        XCTAssertEqual(updated?["name"]?.stringValue, "Updated")
        XCTAssertEqual(updated?["value"]?.intValue, 100, "Other fields preserved")
    }
    
    func testRegression_Delete() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertEqual(try requireFixture(db).count(), 1)
        
        try requireFixture(db).delete(id: id)
        XCTAssertEqual(try requireFixture(db).count(), 0)
        
        let fetched = try requireFixture(db).fetch(id: id)
        XCTAssertNil(fetched)
    }
    
    func testRegression_FetchAll() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        let all = try requireFixture(db).fetchAll()
        XCTAssertEqual(all.count, 100)
    }
    
    // MARK: - Query Regression
    
    func testRegression_SimpleQuery() throws {
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "status": .string(i % 2 == 0 ? "active" : "inactive"),
                "value": .int(i)
            ]))
        }
        
        let results = try requireFixture(db).query()
            .where("status", equals: .string("active"))
            .execute()
        
        XCTAssertEqual(results.count, 50)
    }
    
    func testRegression_Aggregations() throws {
        for i in 0..<50 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
        }
        
        let queryResult = try requireFixture(db).query()
            .sum("value", as: "total")
            .count(as: "count")
            .execute()
        let result = try queryResult.aggregation
        
        let expectedSum = (0..<50).reduce(0, +)
        XCTAssertEqual(Int(result.sum("total") ?? -1), expectedSum)
        XCTAssertEqual(result.values["count"]?.intValue, 50)
    }
    
    // MARK: - Persistence Regression
    
    func testRegression_PersistAndReopen() throws {
        // Insert records
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try requireFixture(db).insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        // Persist
        try requireFixture(db).persist()
        
        // Reopen
        db = nil
        Thread.sleep(forTimeInterval: 0.1)
        BlazeDBClient.clearCachedKey()
        db = try BlazeDBClient(name: "mvcc_regression", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
        try requireFixture(db).setMVCCEnabled(true)
        
        // Verify MVCC still enabled
        XCTAssertTrue(try requireFixture(db).isMVCCEnabled())
        
        // Verify all records exist
        XCTAssertEqual(try requireFixture(db).count(), 100)
        
        for id in ids {
            let fetched = try requireFixture(db).fetch(id: id)
            XCTAssertNotNil(fetched, "Record \(id) should exist after reopen")
        }
    }
    
    // MARK: - Batch Operations Regression
    
    func testRegression_BatchInsert() throws {
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string("Batch \(i)")
            ])
        }
        
        let ids = try requireFixture(db).insertMany(records)
        
        XCTAssertEqual(ids.count, 1000)
        XCTAssertEqual(try requireFixture(db).count(), 1000)
    }
    
    // MARK: - Concurrency Regression
    
    func testRegression_ConcurrentInserts() throws {
        let group = DispatchGroup()
        let insertedCount = MVCCRegressionLockedCounter()
        let dbRef = try requireFixture(db)
        
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    _ = try dbRef.insert(BlazeDataRecord([
                        "thread": .int(i)
                    ]))
                    insertedCount.increment()
                } catch {
                    print("Insert error: \(error)")
                }
            }
        }
        
        group.wait()
        
        XCTAssertEqual(insertedCount.get(), 100)
        XCTAssertEqual(try requireFixture(db).count(), 100)
    }
    
    func testRegression_ConcurrentMixed() throws {
        // Pre-populate
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try requireFixture(db).insert(BlazeDataRecord(["value": .int(i)]))
            ids.append(id)
        }
        
        let group = DispatchGroup()
        let errors = MVCCRegressionLockedCounter()
        let dbRef = try requireFixture(db)
        let idList = ids
        
        // 200 mixed concurrent operations
        for _ in 0..<200 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                
                do {
                    let op = Int.random(in: 0...3)
                    
                    switch op {
                    case 0:  // Insert
                        _ = try dbRef.insert(BlazeDataRecord([
                            "r": .int(Int.random(in: 0...1000))
                        ]))
                    case 1:  // Fetch
                        if let id = idList.randomElement() {
                            _ = try dbRef.fetch(id: id)
                        }
                    case 2:  // Update
                        if let id = idList.randomElement() {
                            try dbRef.update(id: id, with: BlazeDataRecord([
                                "updated": .bool(true)
                            ]))
                        }
                    case 3:  // Delete
                        if idList.count > 20, let id = idList.randomElement() {
                            try dbRef.delete(id: id)
                        }
                    default:
                        break
                    }
                } catch {
                    errors.increment()
                }
            }
        }
        
        group.wait()
        
        // Some operations might fail (conflicts), but database should be stable
        XCTAssertNoThrow(try requireFixture(db).fetchAll())
        print("Errors: \(errors.get())/200 (conflicts expected)")
    }
    
    // MARK: - Data Types Regression
    
    func testRegression_AllDataTypes() throws {
        let record = BlazeDataRecord([
            "string": .string("Hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "date": .date(Date()),
            "uuid": .uuid(UUID()),
            "data": .data(Data([0x01, 0x02, 0x03])),
            "array": .array([.int(1), .int(2), .int(3)]),
            "dict": .dictionary(["key": .string("value")])
        ])
        
        let id = try requireFixture(db).insert(record)
        let fetched = try requireFixture(db).fetch(id: id)
        
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?["string"]?.stringValue, "Hello")
        XCTAssertEqual(fetched?["int"]?.intValue, 42)
        XCTAssertNotNil(fetched?["date"])
        XCTAssertNotNil(fetched?["uuid"])
        XCTAssertNotNil(fetched?["array"])
        XCTAssertNotNil(fetched?["dict"])
    }
    
    // MARK: - Edge Cases Regression
    
    func testRegression_EmptyRecords() throws {
        let empty = BlazeDataRecord([:])
        let id = try requireFixture(db).insert(empty)
        
        let fetched = try requireFixture(db).fetch(id: id)
        XCTAssertNotNil(fetched)
    }
    
    func testRegression_LargeRecords() throws {
        let largeString = String(repeating: "A", count: 10_000)
        let record = BlazeDataRecord(["large": .string(largeString)])
        
        let id = try requireFixture(db).insert(record)
        let fetched = try requireFixture(db).fetch(id: id)
        
        XCTAssertEqual(fetched?["large"]?.stringValue?.count, 10_000)
    }
    
    func testRegression_ManyFields() throws {
        var fields: [String: BlazeDocumentField] = [:]
        for i in 0..<100 {
            fields["field\(i)"] = .int(i)
        }
        
        let record = BlazeDataRecord(fields)
        let id = try requireFixture(db).insert(record)
        let fetched = try requireFixture(db).fetch(id: id)
        
        XCTAssertEqual(fetched?.storage.count, fields.count + 3) // +3 for id, createdAt, project
    }
    
    // MARK: - GC Regression with Operations
    
    func testRegression_GC_DuringOperations() throws {
        // Insert many records
        for i in 0..<200 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["i": .int(i)]))
        }
        
        // Trigger GC
        try requireFixture(db).runGarbageCollection()
        
        // Operations should still work
        XCTAssertEqual(try requireFixture(db).count(), 200)
        XCTAssertNoThrow(try requireFixture(db).fetchAll())
        XCTAssertNoThrow(try requireFixture(db).insert(BlazeDataRecord(["after_gc": .bool(true)])))
    }
}

