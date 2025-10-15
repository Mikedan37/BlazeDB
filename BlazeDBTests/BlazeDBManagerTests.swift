//  BlazeDBManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBManagerTests: XCTestCase {

    func testMountAndUseDatabase() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases() // or clear mounted DBs manually if you don’t have this helper

        let dbName = "TestDB"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testDB.blaze")
        let password = "pass123"
        try? FileManager.default.removeItem(at: url)
        try manager.mountDatabase(named: dbName, fileURL: url, password: password)
        
        XCTAssertEqual(manager.mountedDatabaseNames.count, 1)
        XCTAssertTrue(manager.mountedDatabaseNames.contains(dbName))
    }

    func testSwitchingDatabases() throws {
        let manager = BlazeDBManager.shared
        let path = FileManager.default.temporaryDirectory
        
    }

    func testListMountedDatabases() throws {
        let manager = BlazeDBManager.shared
        let dbName = "TestListDB"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testListDB.blaze")
        try? FileManager.default.removeItem(at: url)

        try manager.mountDatabase(named: dbName, fileURL: url, password: "secret")

        let keys = manager.mountedDatabaseNames
        XCTAssertFalse(keys.isEmpty, "Expected at least one mounted DB")
        XCTAssertTrue(keys.contains(dbName), "Expected mounted DB to include \(dbName)")
    }

    func testInvalidDatabaseUseFails() throws {
        let manager = BlazeDBManager.shared
        XCTAssertThrowsError(try manager.use("NonExistentDB"))
    }
}
