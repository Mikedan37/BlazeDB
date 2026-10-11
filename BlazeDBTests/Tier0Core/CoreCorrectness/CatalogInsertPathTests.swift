import Foundation
import XCTest
@testable import BlazeDBCore

/// MVCC insert must not decode the signed catalog. That file holds indexMap
/// for every record, so a load on the insert path makes latency grow with row count.
final class CatalogInsertPathTests: XCTestCase {
    private let password = "CatalogInsertPath-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-insert-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testMVCCInsertSucceedsWhenCatalogFileIsUnreadable() throws {
        let url = tempDir.appendingPathComponent("catalog.blazedb")
        let db = try BlazeDBClient(name: "CatalogInsert", fileURL: url, password: password)
        defer { try? db.close() }
        db.setMVCCEnabled(true)

        _ = try db.insert(BlazeDataRecord(["title": .string("seed")]))
        try db.persist()

        let meta = url.deletingPathExtension().appendingPathExtension("meta")
        try Data("not-a-catalog".utf8).write(to: meta, options: .atomic)

        let id = try db.insert(BlazeDataRecord(["title": .string("after")]))
        let loaded = try db.fetch(id: id)
        XCTAssertEqual(loaded?.storage["title"]?.stringValue, "after")
    }

    func testMVCCInsertUpdateSurvivesReopen() throws {
        let url = tempDir.appendingPathComponent("reopen.blazedb")
        let db = try BlazeDBClient(name: "CatalogReopen", fileURL: url, password: password)
        db.setMVCCEnabled(true)

        let id = try db.insert(BlazeDataRecord(["title": .string("first")]))
        try db.update(id: id, with: BlazeDataRecord(["title": .string("second")]))
        try db.persist()
        try db.close()

        let reopened = try BlazeDBClient(name: "CatalogReopen", fileURL: url, password: password)
        defer { try? reopened.close() }
        reopened.setMVCCEnabled(true)
        let loaded = try reopened.fetch(id: id)
        XCTAssertEqual(loaded?.storage["title"]?.stringValue, "second")
    }

    #if !BLAZEDB_LINUX_CORE
    /// insertMany saves the catalog from an allocation snapshot. That snapshot
    /// does not carry search indexes, index definitions, or metadata.
    func testInsertManyPreservesCatalogMetadataAndSearchIndex() throws {
        let url = tempDir.appendingPathComponent("batch-catalog.blazedb")
        let db = try BlazeDBClient(name: "BatchCatalog", fileURL: url, password: password)
        _ = try db.insert(BlazeDataRecord([
            "title": .string("seed zephyr"),
            "status": .string("open")
        ]))
        try db.createIndex(on: "status")
        try db.collection.enableSearch(on: ["title"])
        try db.enableOrdering()
        var meta = try db.collection.fetchMeta()
        meta["appToken"] = .string("keep-me")
        try db.collection.updateMeta(meta)

        let ids = try db.insertMany([
            BlazeDataRecord([
                "title": .string("batch zephyr"),
                "status": .string("open")
            ])
        ])
        try db.close()

        let reopened = try BlazeDBClient(name: "BatchCatalog", fileURL: url, password: password)
        defer { try? reopened.close() }

        XCTAssertEqual(try reopened.fetch(id: ids[0])?.storage["title"]?.stringValue, "batch zephyr")
        XCTAssertTrue(reopened.isOrderingEnabled())
        XCTAssertEqual(try reopened.collection.fetchMeta()["appToken"]?.stringValue, "keep-me")

        let layout = try StorageLayout.loadSecure(
            from: reopened.metaURL,
            signingKey: reopened.encryptionKey,
            password: password,
            salt: reopened.kdfSalt
        )
        XCTAssertEqual(layout.searchIndexedFields, ["title"])
        XCTAssertNotNil(layout.searchIndex)
        XCTAssertEqual(layout.secondaryIndexDefinitions["status"], ["status"])
        if case let .string(formatVersion)? = layout.metaData["formatVersion"] {
            XCTAssertEqual(formatVersion, BlazeDBClient.FormatVersion.current.description)
        } else {
            XCTFail("formatVersion was dropped from catalog metadata")
        }
        let indexedHits = layout.searchIndex?.search(query: "zephyr", in: ["title"]) ?? []
        XCTAssertEqual(indexedHits.count, 2, "Batch insert must keep the new record in the search index")

        let byStatus = try reopened.collection.fetch(byIndexedFields: ["status"], values: ["open"])
        XCTAssertEqual(byStatus.count, 2)
    }
    #endif
}
