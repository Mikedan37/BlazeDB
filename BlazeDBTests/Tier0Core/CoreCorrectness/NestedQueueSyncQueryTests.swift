//
//  NestedQueueSyncQueryTests.swift
//  BlazeDBTests — #279: runQuery* must not nest queue.sync via fetchAll
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class NestedQueueSyncQueryTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedSyncQ-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "NestedSyncQ",
            fileURL: dbURL,
            password: "NestedSyncQ-Pass_123!"
        )
    }

    override func tearDown() {
        try? db.close()
        let base = dbURL.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
        try? FileManager.default.removeItem(at: dbURL)
        db = nil
        dbURL = nil
        super.tearDown()
    }

    /// #279: nested queue.sync(fetchAll) deadlocks — must return promptly.
    func testRunQuery_OnNonEmptyCollection_DoesNotDeadlock() throws {
        for i in 0..<20 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "n": .int(i),
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ]))
        }

        let collection = db.collection
        let query = BlazeQueryLegacy<[String: BlazeDocumentField]>()

        let exp = expectation(description: "runQuery completes")
        DispatchQueue.global().async {
            do {
                let results = try collection.runQuery(query)
                XCTAssertEqual(results.count, 20)
                exp.fulfill()
            } catch {
                XCTFail("runQuery threw: \(error)")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 10.0)
    }

    func testFetchAllSorted_DoesNotDeadlock() throws {
        for i in 0..<15 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "name": .string(String(format: "%02d", i))
            ]))
        }
        let collection = db.collection
        let exp = expectation(description: "fetchAllSorted completes")
        DispatchQueue.global().async {
            do {
                let sorted = try collection.fetchAllSorted(by: "name")
                XCTAssertEqual(sorted.count, 15)
                exp.fulfill()
            } catch {
                XCTFail("fetchAllSorted threw: \(error)")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 10.0)
    }

    func testFilter_DoesNotDeadlock() throws {
        for i in 0..<15 {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "keep": .bool(i % 2 == 0)
            ]))
        }
        let collection = db.collection
        let exp = expectation(description: "filter completes")
        DispatchQueue.global().async {
            do {
                let kept = try collection.filter { $0.storage["keep"]?.boolValue == true }
                XCTAssertEqual(kept.count, 8)
                exp.fulfill()
            } catch {
                XCTFail("filter threw: \(error)")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 10.0)
    }
}
