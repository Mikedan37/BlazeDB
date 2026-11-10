//
//  UpdateOverflowCatalogRecoveryTests.swift
//  BlazeDBTests — a crash after update() fsyncs an overflow page must not let
//  the next insert reuse that page when the catalog high-water mark is stale.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class UpdateOverflowCatalogRecoveryTests: XCTestCase {
    private let password = "UpdateOverflowCatalog-Pass_123!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-overflow-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testInsertAfterCrashDoesNotOverwriteUncatalogedOverflowPage() throws {
        let url = tempDir.appendingPathComponent("live.blazedb")
        let db = try BlazeDBClient(name: "overflow_catalog", fileURL: url, password: password)
        let original = try db.insert(BlazeDataRecord(["name": .string("kept"), "payload": .string("small")]))
        let metaURL = url.deletingPathExtension().appendingPathExtension("meta")
        let catalogBeforeGrowth = try Data(contentsOf: metaURL)

        // Keep createdAt. A full-record update that drops it makes Linux open
        // rewrite the row (schema migration) and hides the stale high-water mark.
        let existing = try XCTUnwrap(db.fetch(id: original))
        var grown = existing.storage
        let payload = String(repeating: "Z", count: 6_000)
        grown["payload"] = .string(payload)
        try db.update(id: original, with: BlazeDataRecord(grown))

        let crashURL = tempDir.appendingPathComponent("crash.blazedb")
        try copyDatabase(from: url, to: crashURL)
        try catalogBeforeGrowth.write(to: crashURL.deletingPathExtension().appendingPathExtension("meta"))
        try db.close()

        let recovered = try BlazeDBClient(name: "overflow_catalog_crash", fileURL: crashURL, password: password)
        let beforeInsert = try XCTUnwrap(recovered.fetch(id: original))
        XCTAssertEqual(beforeInsert.storage["payload"]?.stringValue, payload)
        try recovered.close()

        // A second open drops the record cache. The insert must not reuse the
        // overflow page that is already in the data file but absent from the catalog.
        let writer = try BlazeDBClient(name: "overflow_catalog_writer", fileURL: crashURL, password: password)
        _ = try writer.insert(BlazeDataRecord(["name": .string("new")]))
        // Checkpoint publishes the new page onto the data file. That is the
        // moment a stale high-water mark overwrites the previous overflow page.
        try writer.close()

        let reader = try BlazeDBClient(name: "overflow_catalog_reader", fileURL: crashURL, password: password)
        defer { try? reader.close() }
        let afterInsert = try XCTUnwrap(reader.fetch(id: original))
        XCTAssertEqual(
            afterInsert.storage["payload"]?.stringValue,
            payload,
            "The next insert reused the overflow page that update() had already written"
        )
        XCTAssertEqual(try reader.fetchAll().count, 2)
    }

    private func copyDatabase(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let sourceBase = source.deletingPathExtension()
        let destinationBase = destination.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            let from = sourceBase.appendingPathExtension(ext)
            guard manager.fileExists(atPath: from.path) else { continue }
            let to = destinationBase.appendingPathExtension(ext)
            if manager.fileExists(atPath: to.path) {
                try manager.removeItem(at: to)
            }
            try manager.copyItem(at: from, to: to)
        }
    }
}
