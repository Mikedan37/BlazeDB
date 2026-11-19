//
//  MVCCUpdateReplaceTests.swift
//  BlazeDB_Tier0 — update(id:with:) replaces the record; updateFields and
//  updateMany(ids:set:) change only the fields they are given. Every case runs with
//  MVCC off and on, and both modes must store the same keys.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class MVCCUpdateReplaceTests: XCTestCase {
    private var dir: URL!
    private let password = "MVCCUpdateReplace-Pass_123!"
    private let modes = [false, true]

    override func setUpWithError() throws {
        try super.setUpWithError()
        KeyManager.setTestPBKDF2IterationsOverride(1_000)
        BlazeDBClient.clearCachedKey()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MVCCUpdateReplace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        KeyManager.setTestPBKDF2IterationsOverride(nil)
        try super.tearDownWithError()
    }

    private func openDB(mvcc: Bool) throws -> BlazeDBClient {
        let url = dir.appendingPathComponent("mvcc-\(mvcc ? "on" : "off").blazedb")
        let db = try BlazeDBClient(name: "mvcc_update_replace", fileURL: url, password: password)
        db.setMVCCEnabled(mvcc)
        return db
    }

    private func mode(_ mvcc: Bool) -> String { "MVCC \(mvcc ? "on" : "off")" }

    func testPartialUpdateReplacesTheRecord() throws {
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["name": .string("a"), "value": .int(1)]))
            try db.update(id: id, with: BlazeDataRecord(["name": .string("b")]))

            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            XCTAssertEqual(Set(stored.storage.keys), ["id", "name", "updatedAt"], mode(mvcc))
            XCTAssertEqual(stored.storage["name"]?.stringValue, "b", mode(mvcc))
            try db.close()
        }
    }

    func testUpdateSetsUpdatedAt() throws {
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["name": .string("a")]))
            let before = Date()
            try db.update(id: id, with: BlazeDataRecord(["name": .string("b")]))

            let updatedAt = try XCTUnwrap(db.fetch(id: id)?.storage["updatedAt"]?.dateValue, mode(mvcc))
            // One second of slack for the encoder's date precision.
            XCTAssertGreaterThanOrEqual(updatedAt, before.addingTimeInterval(-1), mode(mvcc))
            try db.close()
        }
    }

    func testRemovedFieldStaysRemovedAfterReopen() throws {
        for mvcc in modes {
            var db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["name": .string("a"), "secret": .string("drop me")]))
            // createdAt is sent so the open-time schema migration, which adds a missing
            // createdAt and re-runs in legacy mode (a legacy insert rewrites the layout
            // without its metaData), leaves the record alone in both modes.
            try db.update(id: id, with: BlazeDataRecord(["name": .string("b"), "createdAt": .date(Date())]))
            try db.persist()
            try db.close()

            BlazeDBClient.clearCachedKey()
            db = try openDB(mvcc: mvcc)
            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            XCTAssertEqual(Set(stored.storage.keys), ["id", "name", "createdAt", "updatedAt"], mode(mvcc))
            try db.close()
        }
    }

    /// Without createdAt in the update, the open-time migration may add fields back; the
    /// dropped field must still not return.
    func testRemovedFieldStaysRemovedAfterReopenWithoutCreatedAt() throws {
        for mvcc in modes {
            var db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["name": .string("a"), "secret": .string("drop me")]))
            try db.update(id: id, with: BlazeDataRecord(["name": .string("b")]))
            try db.persist()
            try db.close()

            BlazeDBClient.clearCachedKey()
            db = try openDB(mvcc: mvcc)
            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            XCTAssertNil(stored.storage["secret"], "\(mode(mvcc)): removed field came back after reopen")
            try db.close()
        }
    }

    func testDroppedFieldRemovesTheOldCompoundIndexKey() throws {
        let fields = ["status", "priority"]
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            try db.createIndex(on: fields)
            let id = try db.insert(BlazeDataRecord(["status": .string("open"), "priority": .int(1)]))
            XCTAssertEqual(try db.collection.fetch(byIndexedFields: fields, values: ["open", 1]).count, 1, mode(mvcc))

            try db.update(id: id, with: BlazeDataRecord(["status": .string("open")]))

            XCTAssertEqual(try db.collection.fetch(byIndexedFields: fields, values: ["open", 1]).count, 0,
                           "\(mode(mvcc)): record still indexed under a field it no longer has")
            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            XCTAssertEqual(Set(stored.storage.keys), ["id", "status", "updatedAt"], mode(mvcc))
            try db.close()
        }
    }

    func testUpdateFieldsKeepsOtherFields() throws {
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["name": .string("a"), "value": .int(1)]))
            let insertedKeys = try Set(XCTUnwrap(db.fetch(id: id), mode(mvcc)).storage.keys)

            try db.updateFields(id: id, fields: ["name": .string("b")])

            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            XCTAssertEqual(Set(stored.storage.keys), insertedKeys.union(["updatedAt"]), mode(mvcc))
            XCTAssertEqual(stored.storage["name"]?.stringValue, "b", mode(mvcc))
            XCTAssertEqual(stored.storage["value"]?.intValue, 1, mode(mvcc))
            try db.close()
        }
    }

    func testUpdateManyByIDsKeepsOtherFields() async throws {
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            var ids: [UUID] = []
            for i in 0..<3 {
                ids.append(try await db.insert(BlazeDataRecord(["value": .int(i), "status": .string("open")])))
            }

            // The unknown id is skipped, not counted.
            let updated = try await db.updateMany(ids: ids + [UUID()], set: ["status": .string("closed")])

            XCTAssertEqual(updated, 3, mode(mvcc))
            for (i, id) in ids.enumerated() {
                let stored = try await db.fetch(id: id)
                XCTAssertEqual(stored?.storage["value"]?.intValue, i, "\(mode(mvcc)): updateMany dropped an unset field")
                XCTAssertEqual(stored?.storage["status"]?.stringValue, "closed", mode(mvcc))
            }
            try db.close()
        }
    }

    /// updateMany(ids:set:) goes through updateFields, whose fetch hides soft-deleted
    /// records: such an id is skipped, not counted, and stays deleted.
    func testUpdateManyByIDsSkipsSoftDeleted() async throws {
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            var ids: [UUID] = []
            for i in 0..<3 {
                ids.append(try await db.insert(BlazeDataRecord(["value": .int(i), "status": .string("open")])))
            }
            try db.softDelete(id: ids[1])

            let updated = try await db.updateMany(ids: ids, set: ["status": .string("closed")])

            XCTAssertEqual(updated, 2, mode(mvcc))
            let fetched = try await db.fetch(id: ids[1])
            XCTAssertNil(fetched, "\(mode(mvcc)): soft-deleted record came back")
            let raw = try XCTUnwrap(db.collection.fetch(id: ids[1]), mode(mvcc))
            XCTAssertEqual(raw.storage["isDeleted"]?.boolValue, true, mode(mvcc))
            XCTAssertEqual(raw.storage["status"]?.stringValue, "open", mode(mvcc))
            try db.close()
        }
    }

    /// update replaces the record, so updateFields must fetch and write under one lock:
    /// otherwise two calls read the same record and the second write drops the first's field.
    func testConcurrentUpdateFieldsKeepEveryField() throws {
        let writers = 40
        for mvcc in modes {
            let db = try openDB(mvcc: mvcc)
            let id = try db.insert(BlazeDataRecord(["seed": .int(0)]))
            let label = mode(mvcc)

            DispatchQueue.concurrentPerform(iterations: writers) { i in
                do {
                    try db.updateFields(id: id, fields: ["f\(i)": .int(i)])
                } catch {
                    XCTFail("\(label): updateFields threw \(error)")
                }
            }

            let stored = try XCTUnwrap(db.fetch(id: id), mode(mvcc))
            let lost = (0..<writers).filter { stored.storage["f\($0)"]?.intValue != $0 }
            XCTAssertEqual(lost, [], "\(mode(mvcc)): concurrent updateFields lost fields")
            try db.close()
        }
    }
}
