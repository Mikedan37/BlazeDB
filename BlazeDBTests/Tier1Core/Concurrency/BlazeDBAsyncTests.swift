//
//  BlazeDBAsyncTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for async operations, query caching, and operation pooling
//
//  Created by Michael Danylchuk on 1/15/25.
//

#if !BLAZEDB_LINUX_CORE

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeDBAsyncTests: XCTestCase {
    private var db: BlazeDBClient?
    private var tempURL: URL?

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_async_\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "TestAsync", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
    }

    func testAsyncCRUDFlow() async throws {
        let id = try await requireFixture(db).insertAsync(BlazeDataRecord(["status": .string("todo"), "title": .string("A")]))
        let fetched = try await requireFixture(db).fetchAsync(id: id)
        XCTAssertEqual(try fetched?.string("title"), "A")

        try await requireFixture(db).updateAsync(id: id, with: BlazeDataRecord(["status": .string("done"), "title": .string("A")]))
        let updated = try await requireFixture(db).fetchAsync(id: id)
        XCTAssertEqual(try updated?.string("status"), "done")

        try await requireFixture(db).deleteAsync(id: id)
        let afterDelete = try await requireFixture(db).fetchAsync(id: id)
        XCTAssertNil(afterDelete)
    }

    func testAsyncInsertManyAndFetchAll() async throws {
        let records = (0..<50).map { i in BlazeDataRecord(["index": .int(i)]) }
        let ids = try await requireFixture(db).insertManyAsync(records)
        XCTAssertEqual(ids.count, 50)

        let all = try await requireFixture(db).fetchAllAsync()
        XCTAssertEqual(all.count, 50)
    }

    func testAsyncConcurrentInsert() async throws {
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await self.db.insertAsync(BlazeDataRecord(["index": .int(i)]))
                }
            }
            var out: [UUID] = []
            for try await id in group { out.append(id) }
            return out
        }
        XCTAssertEqual(ids.count, 20)
    }

    func testQueryCacheInvalidation() async throws {
        let id = try await requireFixture(db).insertAsync(BlazeDataRecord(["status": .string("open")]))
        let first = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)
        XCTAssertEqual(first.count, 1)

        try await requireFixture(db).updateAsync(id: id, with: BlazeDataRecord(["status": .string("closed")]))
        let second = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)
        XCTAssertEqual(second.count, 0)
    }

    func testOperationPoolLoadReturnsToZero() async throws {
        let initial = await try requireFixture(db).getOperationPoolLoad()
        XCTAssertEqual(initial, 0)

        _ = try await withThrowingTaskGroup(of: UUID.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await self.db.insertAsync(BlazeDataRecord(["index": .int(i)]))
                }
            }
            var out: [UUID] = []
            for try await id in group { out.append(id) }
            return out
        }

        let final = await try requireFixture(db).getOperationPoolLoad()
        XCTAssertEqual(final, 0)
    }

    func testAsyncFetchAllAfterConcurrentWrites() async throws {
        _ = try await withThrowingTaskGroup(of: UUID.self) { group in
            for i in 0..<30 {
                group.addTask {
                    try await self.db.insertAsync(BlazeDataRecord(["group": .string("g"), "index": .int(i)]))
                }
            }
            var ids: [UUID] = []
            for try await id in group { ids.append(id) }
            return ids
        }

        let all = try await requireFixture(db).fetchAllAsync()
        XCTAssertEqual(all.count, 30)
    }

    func testAsyncDeleteManyViaConcurrentDeletes() async throws {
        let ids = try await requireFixture(db).insertManyAsync((0..<25).map { BlazeDataRecord(["index": .int($0)]) })
        XCTAssertEqual(ids.count, 25)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try await self.db.deleteAsync(id: id)
                }
            }
            for try await _ in group {}
        }

        let remaining = try await requireFixture(db).fetchAllAsync()
        XCTAssertEqual(remaining.count, 0)
    }

    func testAsyncQueryCacheWarmPath() async throws {
        for i in 0..<15 {
            _ = try await requireFixture(db).insertAsync(BlazeDataRecord(["status": .string("open"), "index": .int(i)]))
        }

        let cold = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)
        let warm = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)

        XCTAssertEqual(cold.count, 15)
        XCTAssertEqual(warm.count, 15)
    }

    func testManualQueryCacheInvalidationFlow() async throws {
        _ = try await requireFixture(db).insertAsync(BlazeDataRecord(["status": .string("open")]))
        let before = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)
        XCTAssertEqual(before.count, 1)

        await try requireFixture(db).invalidateQueryCache()
        _ = try await requireFixture(db).insertAsync(BlazeDataRecord(["status": .string("open")]))
        let after = try await requireFixture(db).queryAsync(where: "status", equals: .string("open"), useCache: true)
        XCTAssertEqual(after.count, 2)
    }
}

#endif

