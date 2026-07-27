//
//  BatchPredicateMutationTests.swift
//  BlazeDBTests — #278: do not iterate live indexMap.keys while mutating
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BatchPredicateMutationTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchPredMut-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "BatchPredMut",
            fileURL: dbURL,
            password: "BatchPredMut-Pass_123!"
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

    /// #278: deleting every matching row must not trap and must delete the full match set.
    func testDeleteManyWhere_DeletesAllMatchesWithoutIteratingLiveKeys() throws {
        let n = 200
        for i in 0..<n {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "tag": .string("kill"),
                "n": .int(i)
            ]))
        }
        XCTAssertEqual(try db.fetchAll().count, n)

        let deleted = try db.deleteMany(where: { rec in
            rec.storage["tag"]?.stringValue == "kill"
        })

        XCTAssertEqual(deleted, n, "Must delete every match; live Keys iteration can skip IDs")
        XCTAssertEqual(try db.fetchAll().count, 0)
    }

    /// #278: updating every matching row must visit each ID from a stable snapshot.
    func testUpdateManyWhere_UpdatesAllMatchesWithoutIteratingLiveKeys() throws {
        let n = 200
        for i in 0..<n {
            _ = try db.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "tag": .string("touch"),
                "n": .int(i)
            ]))
        }

        let updated = try db.updateMany(
            where: { $0.storage["tag"]?.stringValue == "touch" },
            set: ["tag": .string("touched")]
        )

        XCTAssertEqual(updated, n)
        let remaining = try db.fetchAll()
        XCTAssertEqual(remaining.count, n)
        XCTAssertTrue(remaining.allSatisfy { $0.storage["tag"]?.stringValue == "touched" })
    }
}
