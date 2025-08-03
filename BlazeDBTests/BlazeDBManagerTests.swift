//  BlazeDBManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBManagerTests: XCTestCase {

    func testMountAndUseDatabase() throws {
        let manager = BlazeDBManager.shared
        let dbName = "TestDB"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testDB.blaze")
        let password = "pass123"

        try? FileManager.default.removeItem(at: url)
        try manager.mount(name: dbName, fileURL: url, password: password)
        try manager.use(dbName)

        let current = manager.current
        XCTAssertEqual(current?.name, dbName)
    }

    func testSwitchingDatabases() throws {
        let manager = BlazeDBManager.shared
        let path = FileManager.default.temporaryDirectory

        try manager.mount(name: "DB1", fileURL: path.appendingPathComponent("db1.blaze"), password: "p1")
        try manager.mount(name: "DB2", fileURL: path.appendingPathComponent("db2.blaze"), password: "p2")

        try manager.use("DB1")
        XCTAssertEqual(manager.current?.name, "DB1")

        try manager.use("DB2")
        XCTAssertEqual(manager.current?.name, "DB2")
    }

    func testListMountedDatabases() throws {
        let manager = BlazeDBManager.shared
        let keys = manager.mountedDatabaseNames
        XCTAssertFalse(keys.isEmpty, "Expected at least one mounted DB")
    }

    func testInvalidDatabaseUseFails() throws {
        let manager = BlazeDBManager.shared
        XCTAssertThrowsError(try manager.use("NonExistentDB"))
    }
}
