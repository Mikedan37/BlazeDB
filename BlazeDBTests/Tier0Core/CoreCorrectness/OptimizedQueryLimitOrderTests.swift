//
//  OptimizedQueryLimitOrderTests.swift
//  BlazeDBTests
//
//  executeOptimized() used to stop after `limit` matches and only then sort
//  and apply offset. ORDER BY LIMIT returned an arbitrary prefix, and
//  OFFSET+LIMIT returned an empty page once offset was at least the limit.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class OptimizedQueryLimitOrderTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptimizedQueryLimit-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "OptimizedQueryLimit",
            fileURL: dbURL,
            password: UUID().uuidString + "aA1!"
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

    func testOffsetAndLimitReturnTheRequestedPage() throws {
        for score in 0..<20 {
            _ = try db.insert(BlazeDataRecord(["score": .int(score)]))
        }

        let page = try db.query()
            .offset(10)
            .limit(5)
            .executeOptimized()

        let scores = try page.records.compactMap { $0.storage["score"]?.intValue }
        XCTAssertEqual(scores.count, 5)
    }

    func testOrderByLimitReturnsTheExtremeValueNotTheScanPrefix() throws {
        var inserted = 0
        while inserted < 64 {
            _ = try db.insert(BlazeDataRecord(["score": .int(inserted)]))
            inserted += 1
            let scanned = try db.fetchAll().compactMap { $0.storage["score"]?.intValue }
            guard let maxScore = scanned.max(), let first = scanned.first, first != maxScore else {
                continue
            }
            break
        }

        let optimized = try db.query()
            .orderBy("score", descending: true)
            .limit(1)
            .executeOptimized()
        let baseline = try db.query()
            .orderBy("score", descending: true)
            .limit(1)
            .execute()

        let optimizedScore = try optimized.records.first?.storage["score"]?.intValue
        let baselineScore = try baseline.records.first?.storage["score"]?.intValue
        XCTAssertEqual(optimizedScore, baselineScore)
        XCTAssertEqual(optimizedScore, inserted - 1)
    }
}
