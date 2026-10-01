import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Page index 0 is the overflow end-of-chain sentinel. Reusing it as a real
/// overflow page used to store a null pointer, so the insert succeeded and the
/// record could not be read back.
final class OverflowPageZeroSentinelTests: XCTestCase {
    private let password = "OverflowPageZero-Sentinel-2026!"
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overflow-page-zero-\(UUID().uuidString).blazedb")
    }

    override func tearDownWithError() throws {
        if let databaseURL {
            let base = databaseURL.deletingPathExtension()
            for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
                try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
            }
            try? FileManager.default.removeItem(at: databaseURL)
        }
        try super.tearDownWithError()
    }

    func testReusedPageZeroAsOverflowRoundTrips() throws {
        var db = try openDB()

        let first = try db.insert(BlazeDataRecord(["marker": .string("first")]))
        let second = try db.insert(BlazeDataRecord(["marker": .string("second")]))
        XCTAssertEqual(db.collection.indexMap[first], [0])
        XCTAssertEqual(db.collection.indexMap[second], [1])

        // Delete the higher page first so the freelist is [1, 0]. The next
        // insert takes page 1 as its main page and would otherwise take page 0
        // as its first overflow page.
        try db.delete(id: second)
        try db.delete(id: first)
        XCTAssertEqual(db.collection.cachedDeletedPages, [1, 0])

        let payload = String(repeating: "z", count: 8_000)
        let inserted = try db.insert(BlazeDataRecord([
            "marker": .string("large"),
            "payload": .string(payload),
        ]))
        let pages = try XCTUnwrap(db.collection.indexMap[inserted])
        XCTAssertFalse(pages.dropFirst().contains(0), "overflow chain must not use page 0: \(pages)")

        let fetched = try XCTUnwrap(db.fetch(id: inserted))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue, payload)

        try db.persist()
        try db.close()

        db = try openDB()
        defer { try? db.close() }
        let reopened = try XCTUnwrap(db.fetch(id: inserted))
        XCTAssertEqual(reopened.storage["payload"]?.stringValue, payload)
        XCTAssertEqual(reopened.storage["marker"]?.stringValue, "large")
    }

    func testPageZeroRemainsUsableAsMainPage() throws {
        let db = try openDB()
        defer { try? db.close() }

        let first = try db.insert(BlazeDataRecord(["marker": .string("first")]))
        XCTAssertEqual(db.collection.indexMap[first], [0])
        try db.delete(id: first)
        XCTAssertEqual(db.collection.cachedDeletedPages, [0])

        let payload = String(repeating: "m", count: 8_000)
        let inserted = try db.insert(BlazeDataRecord([
            "marker": .string("large-main-zero"),
            "payload": .string(payload),
        ]))
        let pages = try XCTUnwrap(db.collection.indexMap[inserted])
        XCTAssertEqual(pages.first, 0, "page 0 is still a valid main page: \(pages)")
        XCTAssertFalse(pages.dropFirst().contains(0))

        let fetched = try XCTUnwrap(db.fetch(id: inserted))
        XCTAssertEqual(fetched.storage["payload"]?.stringValue, payload)
    }

    private func openDB() throws -> BlazeDBClient {
        try BlazeDBClient(name: "overflow-page-zero", fileURL: databaseURL, password: password)
    }
}
