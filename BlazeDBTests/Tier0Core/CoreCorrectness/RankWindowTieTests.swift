//
//  RankWindowTieTests.swift
//  BlazeDBTests - #376: SQL RANK() must skip after ties
//
//  Regression: values [10, 20, 20, 30] must rank as [1, 2, 2, 4].
//  Window functions are Apple-only (`#if !BLAZEDB_LINUX_CORE`).
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

#if !BLAZEDB_LINUX_CORE
final class RankWindowTieTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RankWindowTie-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "RankWindowTie",
            fileURL: dbURL,
            password: "RankWindowTie-Pass_123!"
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

    /// #376 minimal case from review: ties share rank; next rank skips.
    func testRankSkipsAfterTies() throws {
        let scores = [10, 20, 20, 30]
        for score in scores {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "score": .int(score)
            ]))
        }

        let results = try db.query()
            .orderBy("score", descending: false)
            .rank(partitionBy: nil, orderBy: ["score"], as: "rank")
            .executeWithWindow()

        XCTAssertEqual(results.count, scores.count)

        let expectedRanks = [1, 2, 2, 4]
        for (index, result) in results.enumerated() {
            let rank = result.getWindowValue("rank")?.intValue
            XCTAssertEqual(
                rank,
                expectedRanks[index],
                "score=\(scores[index]) expected rank \(expectedRanks[index]), got \(String(describing: rank))"
            )
        }
    }

    /// Longer peer groups still produce standard SQL RANK gaps ([1,2,2,4,4,4,7]).
    func testRankSkipsAfterLongerTieGroups() throws {
        let scores = [10, 20, 20, 30, 30, 30, 40]
        for score in scores {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "score": .int(score)
            ]))
        }

        let results = try db.query()
            .orderBy("score", descending: false)
            .rank(partitionBy: nil, orderBy: ["score"], as: "rank")
            .executeWithWindow()

        let expectedRanks = [1, 2, 2, 4, 4, 4, 7]
        XCTAssertEqual(results.count, expectedRanks.count)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(
                result.getWindowValue("rank")?.intValue,
                expectedRanks[index],
                "index \(index) score=\(scores[index])"
            )
        }
    }
}
#endif // !BLAZEDB_LINUX_CORE