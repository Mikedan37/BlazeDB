//
//  DeleteBatchPageReuseTests.swift
//  BlazeDBTests — batch delete must return pages to the free list
//
//  deleteMany(ids:) on Apple goes through deleteBatch. That path zeroed the
//  pages and dropped the catalog entries, but left cachedDeletedPages unchanged.
//  The next insert then extended the file instead of reusing those pages.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DeleteBatchPageReuseTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeleteBatchPageReuse-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "DeleteBatchPageReuse",
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

    func testReclaimReleasedPagesSkipsLivePagesAndDuplicates() throws {
        let id = try db.insert(BlazeDataRecord(["n": .int(1)]))
        let live = try XCTUnwrap(db.collection.indexMap[id])
        XCTAssertFalse(live.isEmpty)

        db.collection.cachedDeletedPages = [42]
        db.collection.reclaimReleasedPages(live + [42, 77, 77, -1])

        XCTAssertEqual(db.collection.cachedDeletedPages, [42, 77])
        XCTAssertEqual(try db.fetch(id: id)?.storage["n"]?.intValue, 1)
    }

    func testReclaimReleasedPagesAreReusedByTheNextInsert() throws {
        var ids: [UUID] = []
        for n in 0..<3 {
            ids.append(try db.insert(BlazeDataRecord(["n": .int(n)])))
        }
        let removed = ids[1]
        let released = try XCTUnwrap(db.collection.indexMap.removeValue(forKey: removed))
        db.collection.reclaimReleasedPages(released)

        let highWater = db.collection.nextPageIndex
        let newID = try db.insert(BlazeDataRecord(["n": .int(50)]))
        let reused = try XCTUnwrap(db.collection.indexMap[newID]?.first)
        XCTAssertTrue(released.contains(reused))
        XCTAssertLessThanOrEqual(db.collection.nextPageIndex, highWater)
        XCTAssertEqual(try db.fetch(id: ids[0])?.storage["n"]?.intValue, 0)
        XCTAssertEqual(try db.fetch(id: ids[2])?.storage["n"]?.intValue, 2)
        XCTAssertNil(try db.fetch(id: removed))
    }

    func testDeleteManyKeepsDeletedPagesReusable() throws {
        var ids: [UUID] = []
        for n in 0..<4 {
            ids.append(try db.insert(BlazeDataRecord(["n": .int(n)])))
        }
        let deletedPages = Set(ids.flatMap { db.collection.indexMap[$0] ?? [] })
        XCTAssertEqual(deletedPages.count, 4)

        let deleted = try db.deleteMany(ids: ids)
        XCTAssertEqual(deleted, 4)
        XCTAssertTrue(deletedPages.isSubset(of: Set(db.collection.cachedDeletedPages)))

        let highWater = db.collection.nextPageIndex
        let newID = try db.insert(BlazeDataRecord(["n": .int(99)]))
        let reused = try XCTUnwrap(db.collection.indexMap[newID]?.first)
        XCTAssertTrue(deletedPages.contains(reused))
        XCTAssertLessThanOrEqual(db.collection.nextPageIndex, highWater)
        XCTAssertEqual(try db.fetch(id: newID)?.storage["n"]?.intValue, 99)
        XCTAssertEqual(try db.fetchAll().count, 1)
    }
}
