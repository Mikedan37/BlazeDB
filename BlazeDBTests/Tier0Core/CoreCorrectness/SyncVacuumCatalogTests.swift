import Foundation
import XCTest
@testable import BlazeDBCore

/// Synchronous vacuum rewrites the data file through a fresh collection.
/// That collection must not replace the live catalog: secondary-index lookups
/// and app metadata have to survive the swap.
final class SyncVacuumCatalogTests: XCTestCase {
    private let password = "SyncVacuumCatalog-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-vacuum-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSyncVacuumKeepsSecondaryIndexAndMetadata() throws {
        let url = tempDir.appendingPathComponent("vacuum-keeps-catalog.blazedb")
        let db = try BlazeDBClient(name: "SyncVacuumCatalog", fileURL: url, password: password)
        defer { try? db.close() }

        let openID = try db.insert(BlazeDataRecord([
            "name": .string("kept"),
            "status": .string("open"),
        ]))
        let closedID = try db.insert(BlazeDataRecord([
            "name": .string("also-kept"),
            "status": .string("closed"),
        ]))

        var meta = try db.collection.fetchMeta()
        meta["appVersion"] = .string("9.9.9")
        try db.collection.updateMeta(meta)
        try db.createIndex(on: "status")

        let before = try db.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(before.count, 1, "Index lookup should find the open row before vacuum")

        _ = try db.vacuum()

        let after = try db.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(after.count, 1, "Index lookup must still find the open row after vacuum")
        XCTAssertEqual(after.first?.storage["id"]?.uuidValue, openID)
        XCTAssertEqual(try db.fetch(id: closedID)?.storage["status"]?.stringValue, "closed")
        XCTAssertEqual(try db.collection.fetchMeta()["appVersion"], .string("9.9.9"))

        try db.close()
        let reopened = try BlazeDBClient(name: "SyncVacuumCatalog", fileURL: url, password: password)
        defer { try? reopened.close() }

        let persisted = try reopened.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(persisted.count, 1, "Index lookup must survive reopen after vacuum")
        XCTAssertEqual(persisted.first?.storage["id"]?.uuidValue, openID)
        XCTAssertEqual(try reopened.collection.fetchMeta()["appVersion"], .string("9.9.9"))

        let onDisk = try StorageLayout.loadSecure(
            from: reopened.metaURL,
            signingKey: reopened.collection.encryptionKey,
            password: password,
            salt: reopened.collection.kdfSalt
        )
        XCTAssertEqual(onDisk.secondaryIndexDefinitions["status"], ["status"])
        XCTAssertEqual(onDisk.metaData["appVersion"], .string("9.9.9"))
    }
}
