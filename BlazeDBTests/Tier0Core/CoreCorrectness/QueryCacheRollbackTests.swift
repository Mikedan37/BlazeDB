import Foundation
import XCTest
@testable import BlazeDBCore

/// Rollback must drop query-cache entries populated during the transaction.
/// Writes invalidate caches, but a later cached query can refill them with
/// in-transaction rows; those rows must not survive rollback.
final class QueryCacheRollbackTests: XCTestCase {
    private let password = "QueryCacheRollback-Test-2026!"
    private var databaseURL: URL!

    override func setUp() {
        super.setUp()
        QueryCache.shared.clearAll()
        QueryCache.shared.isEnabled = true
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueryCacheRollback-\(UUID().uuidString).blazedb")
    }

    override func tearDown() {
        QueryCache.shared.clearAll()
        if let databaseURL {
            let sidecarBase = databaseURL.deletingPathExtension()
            for ext in ["meta", "wal", "salt"] {
                try? FileManager.default.removeItem(at: sidecarBase.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: databaseURL)
        }
        super.tearDown()
    }

    func testExecuteWithCacheDoesNotReturnRolledBackInsert() throws {
        let db = try BlazeDBClient(name: "query-cache-rollback", fileURL: databaseURL, password: password)
        defer { try? db.close() }

        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "marker": .string("baseline")]))

        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "marker": .string("rolled-back")]))
        let during = try db.query()
            .where("status", equals: .string("open"))
            .execute(withCache: 60)
        XCTAssertEqual(try during.records.count, 2, "Transaction should see the inserted row")

        try db.rollbackTransaction()

        let after = try db.query()
            .where("status", equals: .string("open"))
            .execute(withCache: 60)
        let markers = try after.records.compactMap { record -> String? in
            if case let .string(marker)? = record.storage["marker"] { return marker }
            return nil
        }
        XCTAssertEqual(markers, ["baseline"], "Cached query after rollback must not return discarded rows")
    }

    #if !BLAZEDB_LINUX_CORE
    func testQueryAsyncCacheDoesNotReturnRolledBackInsert() async throws {
        let db = try BlazeDBClient(name: "query-async-cache-rollback", fileURL: databaseURL, password: password)
        defer { try? db.close() }

        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "marker": .string("baseline")]))

        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["status": .string("open"), "marker": .string("rolled-back")]))
        let during = try await db.queryAsync(where: "status", equals: .string("open"), useCache: true)
        XCTAssertEqual(during.count, 2, "Transaction should see the inserted row")

        try db.rollbackTransaction()

        let after = try await db.queryAsync(where: "status", equals: .string("open"), useCache: true)
        let markers = after.compactMap { record -> String? in
            if case let .string(marker)? = record.storage["marker"] { return marker }
            return nil
        }
        XCTAssertEqual(markers, ["baseline"], "queryAsync cache after rollback must not return discarded rows")
    }
    #endif
}
