//
//  DeleteCrashDurabilityTests.swift
//  BlazeDBTests
//
//  A successful delete() must stay deleted across an unclean shutdown.
//  The legacy WAL still holds the pre-delete page image until checkpoint,
//  so a catalog that is only flushed every 100 operations lets replay
//  resurrect the record.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DeleteCrashDurabilityTests: XCTestCase {

    private let password = "TestPassword-123!"

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-delete-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy the on-disk database without closing it. That is the image a
    /// kill -9 would leave behind: pages and WAL already fsynced, catalog
    /// only if delete published it.
    private func copyCrashImage(from source: URL, to destinationDirectory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        let base = source.deletingPathExtension()
        let destBase = destination.deletingPathExtension()
        let sidecars = ["blazedb", "meta", "wal", "salt"]
        for ext in sidecars {
            let from = ext == "blazedb" ? source : base.appendingPathExtension(ext)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = ext == "blazedb" ? destination : destBase.appendingPathExtension(ext)
            try fm.copyItem(at: from, to: to)
        }
        return destination
    }

    func testDeleteDoesNotResurrectAfterCrashBeforeClose() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("delete-crash.blazedb")
        let survivorID = UUID()
        let victimID = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)

        let db = try BlazeDBClient(name: "delete-crash", fileURL: dbURL, password: password)
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(survivorID),
            "role": .string("survivor"),
            "createdAt": .date(created)
        ]))
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(victimID),
            "role": .string("victim"),
            "createdAt": .date(created.addingTimeInterval(1))
        ]))
        try db.delete(id: victimID)
        XCTAssertNil(try db.fetch(id: victimID), "Delete must hide the record before any crash")

        let crashURL = try copyCrashImage(
            from: dbURL,
            to: dir.appendingPathComponent("crash-image", isDirectory: true)
        )
        try db.close()
        BlazeDBClient.clearCachedKey()

        let recovered = try BlazeDBClient(name: "delete-crash-recovered", fileURL: crashURL, password: password)
        defer { try? recovered.close() }

        let survivor = try XCTUnwrap(try recovered.fetch(id: survivorID))
        XCTAssertEqual(survivor.storage["role"]?.stringValue, "survivor")
        XCTAssertNil(
            try recovered.fetch(id: victimID),
            "A delete that already returned must not come back after crash replay"
        )
        XCTAssertEqual(try recovered.count(), 1, "Catalog must not keep a ghost id for the deleted record")

        let reinserted = try recovered.insert(BlazeDataRecord([
            "id": .uuid(victimID),
            "role": .string("reinserted"),
            "createdAt": .date(created.addingTimeInterval(2))
        ]))
        XCTAssertEqual(reinserted, victimID, "The deleted id must be usable again")
        let revived = try XCTUnwrap(try recovered.fetch(id: victimID))
        XCTAssertEqual(revived.storage["role"]?.stringValue, "reinserted")
    }

    func testDeleteInsideTransactionCanRollBack() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("delete-rollback.blazedb")
        let id = UUID()
        let db = try BlazeDBClient(name: "delete-rollback", fileURL: dbURL, password: password)
        defer { try? db.close() }

        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(id),
            "role": .string("keep"),
            "createdAt": .date(Date(timeIntervalSince1970: 1_700_000_000))
        ]))

        try db.beginTransaction()
        try db.delete(id: id)
        XCTAssertNil(try db.fetch(id: id))
        try db.rollbackTransaction()

        let restored = try XCTUnwrap(try db.fetch(id: id))
        XCTAssertEqual(restored.storage["role"]?.stringValue, "keep")
        XCTAssertEqual(try db.count(), 1)
    }
}
