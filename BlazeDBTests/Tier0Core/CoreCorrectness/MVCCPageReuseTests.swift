//
//  MVCCPageReuseTests.swift
//  BlazeDB_Tier0 — with MVCC on, a page may be handed out again only after
//  nothing live points at it. Every surviving record must still read back as itself.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class MVCCPageReuseTests: XCTestCase {
    private var dbURL: URL!
    private let password = "MVCCPageReuse-Pass_123!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        BlazeDBClient.clearCachedKey()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCPageReuse-\(UUID().uuidString).blazedb")
    }

    override func tearDownWithError() throws {
        if let dbURL {
            let base = dbURL.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
        }
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        try super.tearDownWithError()
    }

    private func openDB() throws -> BlazeDBClient {
        let db = try BlazeDBClient(name: "mvcc_page_reuse", fileURL: dbURL, password: password)
        db.setMVCCEnabled(true)
        return db
    }

    /// Inserts records tagged with their own index and remembers what each id must read back as.
    private func insert(_ db: BlazeDBClient, _ range: Range<Int>, into expected: inout [UUID: Int]) throws {
        for i in range {
            let id = try db.insert(BlazeDataRecord(["index": .int(i), "tag": .string("record-\(i)")]))
            expected[id] = i
        }
    }

    private func assertEveryRecordReadsBackAsItself(_ db: BlazeDBClient, _ expected: [UUID: Int],
                                                    file: StaticString = #filePath, line: UInt = #line) throws {
        var wrong: [String] = []
        for (id, index) in expected {
            guard let record = try db.fetch(id: id) else {
                wrong.append("\(id.uuidString.prefix(8)) missing")
                continue
            }
            if record.storage["id"]?.uuidValue != id || record.storage["index"]?.intValue != index {
                let got = record.storage["id"]?.uuidValue?.uuidString.prefix(8) ?? "nil"
                wrong.append("\(id.uuidString.prefix(8)) -> \(got) index \(record.storage["index"]?.intValue ?? -1) (want \(index))")
            }
        }
        XCTAssertTrue(wrong.isEmpty, "\(wrong.count) of \(expected.count) records read back wrong: \(wrong.prefix(5))",
                      file: file, line: line)
        XCTAssertEqual(try db.count(), expected.count, file: file, line: line)
    }

    // Sizes cross the 100-operation marks where MVCC runs automatic GC and the
    // catalog flush, which is where the second owner of a freed page appeared.
    func testUpdateThenInsert_doesNotOverwriteLiveRecords() throws {
        let db = try openDB()
        var expected: [UUID: Int] = [:]
        try insert(db, 0..<150, into: &expected)

        for id in Array(expected.keys.prefix(10)) {
            let index = try XCTUnwrap(expected[id])
            try db.update(id: id, with: BlazeDataRecord(["index": .int(index), "tag": .string("updated-\(index)")]))
        }
        try insert(db, 150..<300, into: &expected)

        try assertEveryRecordReadsBackAsItself(db, expected)
        try db.close()
    }

    func testDeleteThenInsert_doesNotOverwriteLiveRecords() throws {
        let db = try openDB()
        var expected: [UUID: Int] = [:]
        try insert(db, 0..<150, into: &expected)

        for id in Array(expected.keys.prefix(10)) {
            try db.delete(id: id)
            expected.removeValue(forKey: id)
        }
        try insert(db, 150..<300, into: &expected)

        try assertEveryRecordReadsBackAsItself(db, expected)
        // The fix must not stop reuse: the deleted pages still go to new records.
        XCTAssertGreaterThan(db.collection.versionManager.pageGC.getStats().totalPagesReused, 0)
        try db.close()
    }

    func testUpdateCannotChangeRecordIdentity() throws {
        let db = try openDB()
        let id = try db.insert(BlazeDataRecord(["index": .int(1), "tag": .string("original")]))
        let otherID = UUID()
        try db.update(id: id, with: BlazeDataRecord(["id": .uuid(otherID), "index": .int(1), "tag": .string("updated")]))

        let fetched = try XCTUnwrap(db.fetch(id: id))
        XCTAssertEqual(fetched.storage["id"]?.uuidValue, id)
        XCTAssertEqual(fetched.storage["tag"]?.stringValue, "updated")
        XCTAssertNil(try db.fetch(id: otherID))
        try db.close()
    }

    func testUpdatedThenDeletedRecordIsGoneAndItsPagesDoNotAliasNewRecords() throws {
        let db = try openDB()
        var expected: [UUID: Int] = [:]
        try insert(db, 0..<150, into: &expected)
        let victims = Array(expected.keys.prefix(10))
        for id in victims {
            let index = try XCTUnwrap(expected[id])
            try db.update(id: id, with: BlazeDataRecord(["index": .int(index), "tag": .string("updated-\(index)")]))
            try db.delete(id: id)
            expected.removeValue(forKey: id)
        }
        try insert(db, 150..<300, into: &expected)

        for id in victims {
            XCTAssertNil(try db.fetch(id: id), "deleted record \(id) is still readable")
        }
        try assertEveryRecordReadsBackAsItself(db, expected)
        try db.close()
    }

    /// MVCC update takes fresh pages from the page store; insertMany allocates from
    /// the catalog's nextPageIndex. The two must agree or the batch overwrites the
    /// updated records.
    func testInsertManyAfterUpdateDoesNotOverwriteUpdatedRecords() throws {
        let db = try openDB()
        var expected: [UUID: Int] = [:]
        let seeded = try db.insertMany((0..<40).map { BlazeDataRecord(["index": .int($0), "tag": .string("record-\($0)")]) })
        for (offset, id) in seeded.enumerated() { expected[id] = offset }
        for id in seeded.prefix(5) {
            let index = try XCTUnwrap(expected[id])
            try db.update(id: id, with: BlazeDataRecord(["index": .int(index), "tag": .string("updated-\(index)")]))
        }
        let added = try db.insertMany((40..<60).map { BlazeDataRecord(["index": .int($0), "tag": .string("record-\($0)")]) })
        for (offset, id) in added.enumerated() { expected[id] = 40 + offset }

        try assertEveryRecordReadsBackAsItself(db, expected)
        try db.close()
    }

    func testReuseSurvivesReopen() throws {
        var db = try openDB()
        var expected: [UUID: Int] = [:]
        try insert(db, 0..<150, into: &expected)
        for id in Array(expected.keys.prefix(10)) {
            let index = try XCTUnwrap(expected[id])
            try db.update(id: id, with: BlazeDataRecord(["index": .int(index), "tag": .string("updated-\(index)")]))
        }
        for id in Array(expected.keys.suffix(10)) {
            try db.delete(id: id)
            expected.removeValue(forKey: id)
        }
        try insert(db, 150..<300, into: &expected)
        try db.persist()
        try db.close()

        BlazeDBClient.clearCachedKey()
        db = try openDB()
        try assertEveryRecordReadsBackAsItself(db, expected)
        try db.close()
    }
}
