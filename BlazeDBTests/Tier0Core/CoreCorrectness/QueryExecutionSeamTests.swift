//
//  QueryExecutionSeamTests.swift
//  BlazeDBTests — internal QueryExecuting boundary (no public behavior change)
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class QueryExecutionSeamTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!
    private var previousExecutor: (any QueryExecuting)!

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousExecutor = QueryBuilder.standardQueryExecutor
        QueryBuilder.standardQueryExecutor = LegacyQueryExecutor()

        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuerySeam-\(UUID().uuidString).blazedb")
        try? FileManager.default.removeItem(at: dbURL)
        db = try BlazeDBClient(
            name: "query_seam",
            fileURL: dbURL,
            password: "QuerySeam-Pass_123!"
        )
    }

    override func tearDownWithError() throws {
        QueryBuilder.standardQueryExecutor = previousExecutor
        try? db?.close()
        db = nil
        if let dbURL {
            let base = dbURL.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: dbURL)
        }
        try super.tearDownWithError()
    }

    func testLegacyExecutorFilterSortLimitOffset() throws {
        let records = [
            BlazeDataRecord(["id": .int(1), "name": .string("c"), "n": .int(3)]),
            BlazeDataRecord(["id": .int(2), "name": .string("a"), "n": .int(1)]),
            BlazeDataRecord(["id": .int(3), "name": .string("b"), "n": .int(2)]),
            BlazeDataRecord(["id": .int(4), "name": .string("d"), "n": .int(4)]),
        ]

        let request = QueryRequest(
            loadRecords: { records },
            filters: [{ $0.storage["n"]?.intValue.map { $0 >= 2 } ?? false }],
            sortOperations: [SortOperation(field: "name", descending: false)],
            offset: 1,
            limit: 1
        )

        let result = try LegacyQueryExecutor().execute(request)
        let out = try result.records
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.storage["name"]?.stringValue, "c")
    }

    func testStandardQueryPathRoutesThroughInjectedExecutor() throws {
        _ = try db.insert(BlazeDataRecord(["id": .int(1), "status": .string("open")]))
        _ = try db.insert(BlazeDataRecord(["id": .int(2), "status": .string("closed")]))

        let spy = CountingQueryExecutor(wrapping: LegacyQueryExecutor())
        QueryBuilder.standardQueryExecutor = spy

        let result = try db.query()
            .where("status", equals: .string("open"))
            .execute()

        XCTAssertEqual(spy.callCount, 1)
        XCTAssertEqual(try result.records.count, 1)
        XCTAssertEqual(try result.records.first?.storage["status"]?.stringValue, "open")
    }
}

private final class CountingQueryExecutor: QueryExecuting {
    private let wrapping: any QueryExecuting
    private(set) var callCount = 0

    init(wrapping: any QueryExecuting) {
        self.wrapping = wrapping
    }

    func execute(_ request: QueryRequest) throws -> QueryResult {
        callCount += 1
        return try wrapping.execute(request)
    }
}
