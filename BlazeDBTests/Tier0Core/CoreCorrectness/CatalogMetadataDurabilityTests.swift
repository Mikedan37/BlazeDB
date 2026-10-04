import Foundation
import XCTest
@testable import BlazeDBCore

/// Legacy insert publishes the catalog on every write. That publish used a fresh
/// layout and erased metadata that lives only in the signed catalog.
final class CatalogMetadataDurabilityTests: XCTestCase {
    private let password = "CatalogMetadata-2026!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertKeepsCatalogMetadataAndIndexDefinitions() throws {
        let url = tempDir.appendingPathComponent("insert-keeps-meta.blazedb")
        let db = try BlazeDBClient(name: "InsertKeepsMeta", fileURL: url, password: password)
        defer { try? db.close() }

        var meta = try db.collection.fetchMeta()
        meta["appVersion"] = .string("9.9.9")
        meta["supportsOrdering"] = .bool(true)
        try db.collection.updateMeta(meta)
        try db.createIndex(on: "status")

        let id = try db.insert(BlazeDataRecord([
            "name": .string("kept"),
            "status": .string("open"),
        ]))

        let afterInsert = try db.collection.fetchMeta()
        XCTAssertEqual(afterInsert["appVersion"], .string("9.9.9"), "insert must not drop app metadata")
        XCTAssertEqual(afterInsert["supportsOrdering"], .bool(true), "insert must not drop ordering flags")

        let onDisk = try loadLayout(db)
        XCTAssertEqual(onDisk.metaData["appVersion"], .string("9.9.9"))
        XCTAssertEqual(onDisk.secondaryIndexDefinitions["status"], ["status"])
        XCTAssertNotNil(onDisk.metaData["formatVersion"], "insert must not drop the on-disk format version")

        try db.close()
        let reopened = try BlazeDBClient(name: "InsertKeepsMeta", fileURL: url, password: password)
        defer { try? reopened.close() }

        let persisted = try reopened.collection.fetchMeta()
        XCTAssertEqual(persisted["appVersion"], .string("9.9.9"))
        XCTAssertEqual(persisted["supportsOrdering"], .bool(true))
        let matches = try reopened.collection.fetch(byIndexedField: "status", value: "open")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.storage["id"]?.uuidValue, id)
    }

    #if !BLAZEDB_LINUX_CORE
    func testMigrationReopenMergesSchemaVersionWithoutWipingAppMetadata() throws {
        let url = tempDir.appendingPathComponent("schema-merge.blazedb")
        let db = try BlazeDBClient(name: "SchemaMerge", fileURL: url, password: password)
        // Full replacement is the public updateMeta contract. Callers that omit
        // schemaVersion used to lose the rest of the catalog on the next open,
        // because migration wrote a one-key dictionary back.
        try db.collection.updateMeta(["appVersion": .string("9.9.9")])
        try db.close()

        let reopened = try BlazeDBClient(name: "SchemaMerge", fileURL: url, password: password)
        defer { try? reopened.close() }

        let meta = try reopened.collection.fetchMeta()
        XCTAssertEqual(meta["appVersion"], .string("9.9.9"))
        XCTAssertEqual(meta["schemaVersion"]?.intValue, 1)
    }
    #endif

    private func loadLayout(_ db: BlazeDBClient) throws -> StorageLayout {
        try StorageLayout.loadSecure(
            from: db.metaURL,
            signingKey: db.collection.encryptionKey,
            password: password,
            salt: db.collection.kdfSalt
        )
    }
}
