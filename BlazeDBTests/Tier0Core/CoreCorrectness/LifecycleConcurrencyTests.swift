//
//  LifecycleConcurrencyTests.swift
//  BlazeDBTests — #295 vacuum exclusivity, #296 close vs writers
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class LifecycleConcurrencyTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeConc-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "LifeConc",
            fileURL: dbURL,
            password: "LifeConc-Pass_123!"
        )
    }

    override func tearDown() {
        try? db.close()
        let base = dbURL.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
        // Vacuum may leave backup sidecars
        let parent = dbURL.deletingLastPathComponent()
        if let items = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            for url in items where url.lastPathComponent.contains("LifeConc") || url.path.contains(dbURL.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        db = nil
        dbURL = nil
        super.tearDown()
    }

    /// #295: VACUUM must reject an open client transaction.
    func testVacuum_WhileTransactionOpen_Throws() throws {
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "n": .int(i)]))
        }
        try db.beginTransaction()
        XCTAssertThrowsError(try db.vacuum()) { error in
            guard case BlazeDBError.transactionFailed = error else {
                return XCTFail("Expected transactionFailed, got \(error)")
            }
        }
        try db.rollbackTransaction()
    }

    /// #295: concurrent inserts during vacuum must not crash; DB remains usable.
    func testVacuum_WithConcurrentInserts_DoesNotCrash() throws {
        for i in 0..<30 {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "n": .int(i)]))
        }

        let client = db!
        let group = DispatchGroup()

        for i in 0..<40 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? client.insert(BlazeDataRecord([
                    "id": .uuid(UUID()),
                    "n": .int(1000 + i)
                ]))
            }
        }

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            _ = try? client.vacuum()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        _ = try client.insert(BlazeDataRecord(["id": .uuid(UUID()), "n": .int(9999)]))
        XCTAssertGreaterThan(try client.fetchAll().count, 0)
    }

    /// #296: close concurrent with writers must not trap; post-close ops fail cleanly.
    func testClose_WithConcurrentInserts_DoesNotCrash() throws {
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["id": .uuid(UUID()), "n": .int(i)]))
        }

        let client = db!
        let group = DispatchGroup()
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                _ = try? client.insert(BlazeDataRecord([
                    "id": .uuid(UUID()),
                    "n": .int(5000 + i)
                ]))
            }
        }

        group.enter()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            defer { group.leave() }
            try? client.close()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        XCTAssertTrue(client.isClosed)
        XCTAssertThrowsError(try client.insert(BlazeDataRecord(["id": .uuid(UUID()), "n": .int(1)])))
    }
}
