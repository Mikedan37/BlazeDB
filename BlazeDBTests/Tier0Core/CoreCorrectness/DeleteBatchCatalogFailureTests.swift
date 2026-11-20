//
//  DeleteBatchCatalogFailureTests.swift
//  BlazeDBTests
//
//  deleteMany(ids:) on Apple goes through deleteBatch. A catalog save that fails
//  after the record pages were zeroed used to restore indexMap, so reopen loaded
//  the old catalog and read empty pages.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class DeleteBatchCatalogFailureTests: XCTestCase {
    private let password = "DeleteBatchCatalog-Pass_123!"
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("delete-batch-catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testDeleteManyLayoutSaveFailureKeepsRecordBytes() throws {
        #if BLAZEDB_LINUX_CORE
        throw XCTSkip("deleteMany(ids:) uses deleteBatch only outside BLAZEDB_LINUX_CORE")
        #else
        let url = tempDir.appendingPathComponent("records.blazedb")
        let db = try BlazeDBClient(name: "DeleteBatchCatalog", fileURL: url, password: password)
        let keeper = try db.insert(BlazeDataRecord(["name": .string("keeper")]))
        let first = try db.insert(BlazeDataRecord(["name": .string("first")]))
        let second = try db.insert(BlazeDataRecord(["name": .string("second")]))
        try db.persist()

        setenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE", "1", 1)
        XCTAssertThrowsError(try db.deleteMany(ids: [first, second])) { error in
            XCTAssertEqual((error as NSError).domain, "BlazeDBTestFault")
        }
        unsetenv("BLAZEDB_FORCE_LAYOUT_SAVE_FAILURE")

        XCTAssertEqual(try db.fetch(id: keeper)?.storage["name"]?.stringValue, "keeper")
        XCTAssertEqual(try db.fetch(id: first)?.storage["name"]?.stringValue, "first")
        XCTAssertEqual(try db.fetch(id: second)?.storage["name"]?.stringValue, "second")
        try db.close()

        let reopened = try BlazeDBClient(name: "DeleteBatchCatalog", fileURL: url, password: password)
        defer { try? reopened.close() }
        XCTAssertEqual(try reopened.fetch(id: keeper)?.storage["name"]?.stringValue, "keeper")
        XCTAssertEqual(try reopened.fetch(id: first)?.storage["name"]?.stringValue, "first")
        XCTAssertEqual(try reopened.fetch(id: second)?.storage["name"]?.stringValue, "second")
        #endif
    }
}
