//
//  DeleteCatalogDurabilityTests.swift
//  BlazeDBTests
//
//  Legacy delete used to zero record pages before the catalog dropped the id.
//  A crash after that left the last persisted record unreadable, and the leftover
//  id rejected a later insert of the same key. A catalog save failure did the
//  same when it restored indexMap onto pages that were already empty.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DeleteCatalogDurabilityTests: XCTestCase {
    private let password = "DeleteCatalog-Pass_123!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testDeleteCrashImageAllowsReinsertOfSameId() throws {
        let url = tempDir.appendingPathComponent("records.blazedb")
        let db = try BlazeDBClient(name: "DeleteCatalog", fileURL: url, password: password)
        let keeper = try db.insert(BlazeDataRecord(["name": .string("keeper")]))
        let victim = UUID()
        try db.insert(BlazeDataRecord(["name": .string("victim")]), id: victim)
        try db.persist()

        try db.delete(id: victim)
        let crashDir = tempDir.appendingPathComponent("crash")
        try copyDatabaseArtifacts(from: url, to: crashDir)

        let crashedURL = crashDir.appendingPathComponent(url.lastPathComponent)
        let crashed = try BlazeDBClient(name: "DeleteCatalogCrash", fileURL: crashedURL, password: password)
        defer { try? crashed.close() }

        XCTAssertEqual(try crashed.fetch(id: keeper)?.storage["name"]?.stringValue, "keeper")
        XCTAssertNil(try crashed.fetch(id: victim))
        XCTAssertNoThrow(try crashed.insert(BlazeDataRecord(["name": .string("again")]), id: victim))
        XCTAssertEqual(try crashed.fetch(id: victim)?.storage["name"]?.stringValue, "again")
        try db.close()
    }

    func testDeleteLayoutSaveFailureKeepsRecordBytes() throws {
        let url = tempDir.appendingPathComponent("records.blazedb")
        let db = try BlazeDBClient(name: "DeleteCatalogFailure", fileURL: url, password: password)
        let keeper = try db.insert(BlazeDataRecord(["name": .string("keeper")]))
        let victim = UUID()
        try db.insert(BlazeDataRecord(["name": .string("victim")]), id: victim)
        try db.persist()

        setenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE", "1", 1)
        XCTAssertThrowsError(try db.delete(id: victim)) { error in
            XCTAssertEqual((error as NSError).domain, "BlazeDBTestFault")
        }
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")

        XCTAssertEqual(try db.fetch(id: keeper)?.storage["name"]?.stringValue, "keeper")
        XCTAssertEqual(try db.fetch(id: victim)?.storage["name"]?.stringValue, "victim")
        try db.close()

        let reopened = try BlazeDBClient(name: "DeleteCatalogFailureReopen", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: keeper)?.storage["name"]?.stringValue, "keeper")
        XCTAssertEqual(try reopened.fetch(id: victim)?.storage["name"]?.stringValue, "victim")
    }

    private func copyDatabaseArtifacts(from databaseURL: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = databaseURL.deletingPathExtension()
        let sources = [
            databaseURL,
            base.appendingPathExtension("meta"),
            base.appendingPathExtension("salt"),
            base.appendingPathExtension("wal")
        ]
        for source in sources where FileManager.default.fileExists(atPath: source.path) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
}
