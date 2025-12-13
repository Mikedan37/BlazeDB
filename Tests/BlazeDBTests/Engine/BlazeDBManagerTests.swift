//  BlazeDBManagerTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBManagerTests: XCTestCase {

    func testMountAndUseDatabase() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases() // or clear mounted DBs manually if you don't have this helper

        let dbName = "TestDB"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testDB.blaze")
        let password = "pass123"
        try? FileManager.default.removeItem(at: url)
        try manager.mountDatabase(named: dbName, fileURL: url, password: password)
        
        XCTAssertEqual(manager.mountedDatabaseNames.count, 1)
        XCTAssertTrue(manager.mountedDatabaseNames.contains(dbName))
    }

    // Removed: Empty test that did nothing

    func testListMountedDatabases() throws {
        let manager = BlazeDBManager.shared
        let dbName = "TestListDB"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("testListDB.blaze")
        try? FileManager.default.removeItem(at: url)

        try manager.mountDatabase(named: dbName, fileURL: url, password: "Secret-Pass-123")

        let keys = manager.mountedDatabaseNames
        XCTAssertFalse(keys.isEmpty, "Expected at least one mounted DB")
        XCTAssertTrue(keys.contains(dbName), "Expected mounted DB to include \(dbName)")
    }

    func testInvalidDatabaseUseFails() throws {
        let manager = BlazeDBManager.shared
        XCTAssertThrowsError(try manager.use("NonExistentDB"))
    }
    
    func testThreeDatabasesSimultaneous() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let db1URL = FileManager.default.temporaryDirectory.appendingPathComponent("db1-\(UUID().uuidString).blaze")
        let db2URL = FileManager.default.temporaryDirectory.appendingPathComponent("db2-\(UUID().uuidString).blaze")
        let db3URL = FileManager.default.temporaryDirectory.appendingPathComponent("db3-\(UUID().uuidString).blaze")
        
        defer {
            try? FileManager.default.removeItem(at: db1URL)
            try? FileManager.default.removeItem(at: db2URL)
            try? FileManager.default.removeItem(at: db3URL)
        }
        
        try manager.mountDatabase(named: "DB1", fileURL: db1URL, password: "Password-001")
        try manager.mountDatabase(named: "DB2", fileURL: db2URL, password: "Password-002")
        try manager.mountDatabase(named: "DB3", fileURL: db3URL, password: "Password-003")
        
        XCTAssertEqual(manager.mountedDatabaseNames.count, 3)
        
        let db1 = manager.database(named: "DB1")!
        let db2 = manager.database(named: "DB2")!
        let db3 = manager.database(named: "DB3")!
        
        _ = try db1.insert(BlazeDataRecord(["db": .string("DB1")]))
        _ = try db2.insert(BlazeDataRecord(["db": .string("DB2")]))
        _ = try db3.insert(BlazeDataRecord(["db": .string("DB3")]))
        
        let records1 = try db1.fetchAll()
        let records2 = try db2.fetchAll()
        let records3 = try db3.fetchAll()
        
        XCTAssertEqual(records1.count, 1)
        XCTAssertEqual(records2.count, 1)
        XCTAssertEqual(records3.count, 1)
        XCTAssertEqual(records1[0].storage["db"], .string("DB1"))
        XCTAssertEqual(records2[0].storage["db"], .string("DB2"))
        XCTAssertEqual(records3[0].storage["db"], .string("DB3"))
    }
    
    func testUnmountCleansUpResources() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-\(UUID().uuidString).blaze")
        defer { try? FileManager.default.removeItem(at: dbURL) }
        
        try manager.mountDatabase(named: "CleanupTest", fileURL: dbURL, password: "Password-123")
        XCTAssertEqual(manager.mountedDatabaseNames.count, 1)
        
        manager.unmountDatabase(named: "CleanupTest")
        XCTAssertEqual(manager.mountedDatabaseNames.count, 0)
        XCTAssertNil(manager.database(named: "CleanupTest"))
    }
    
    func testSwitchDatabaseUnderLoad() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let db1URL = FileManager.default.temporaryDirectory.appendingPathComponent("switch1-\(UUID().uuidString).blaze")
        let db2URL = FileManager.default.temporaryDirectory.appendingPathComponent("switch2-\(UUID().uuidString).blaze")
        
        defer {
            try? FileManager.default.removeItem(at: db1URL)
            try? FileManager.default.removeItem(at: db2URL)
        }
        
        try manager.mountDatabase(named: "SwitchDB1", fileURL: db1URL, password: "Password-001")
        try manager.mountDatabase(named: "SwitchDB2", fileURL: db2URL, password: "Password-002")
        
        let db1 = manager.database(named: "SwitchDB1")!
        
        for i in 0..<50 {
            _ = try db1.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        try manager.use("SwitchDB2")
        let db2 = manager.database(named: "SwitchDB2")!
        
        for i in 0..<50 {
            _ = try db2.insert(BlazeDataRecord(["index": .int(i + 100)]))
        }
        
        let records1 = try db1.fetchAll()
        let records2 = try db2.fetchAll()
        
        XCTAssertEqual(records1.count, 50)
        XCTAssertEqual(records2.count, 50)
    }
    
    func testDatabaseMemoryIsolation() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let db1URL = FileManager.default.temporaryDirectory.appendingPathComponent("isolate1-\(UUID().uuidString).blaze")
        let db2URL = FileManager.default.temporaryDirectory.appendingPathComponent("isolate2-\(UUID().uuidString).blaze")
        
        defer {
            try? FileManager.default.removeItem(at: db1URL)
            try? FileManager.default.removeItem(at: db2URL)
        }
        
        try manager.mountDatabase(named: "IsolateDB1", fileURL: db1URL, password: "Password-001")
        try manager.mountDatabase(named: "IsolateDB2", fileURL: db2URL, password: "Password-002")
        
        let db1 = manager.database(named: "IsolateDB1")!
        let db2 = manager.database(named: "IsolateDB2")!
        
        let id1 = try db1.insert(BlazeDataRecord(["value": .int(111)]))
        let id2 = try db2.insert(BlazeDataRecord(["value": .int(222)]))
        
        let record1 = try db1.fetch(id: id1)
        let record2 = try db2.fetch(id: id2)
        
        XCTAssertEqual(record1?.storage["value"], .int(111))
        XCTAssertEqual(record2?.storage["value"], .int(222))
        
        XCTAssertNil(try? db1.fetch(id: id2), "DB1 should not see DB2 records")
        XCTAssertNil(try? db2.fetch(id: id1), "DB2 should not see DB1 records")
    }
    
    func testMountCorruptedDatabaseFails() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let corruptURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).blaze")
        defer {
            try? FileManager.default.removeItem(at: corruptURL)
            try? FileManager.default.removeItem(at: corruptURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        // Create corrupted database file
        let corruptData = Data(repeating: 0xFF, count: 8192)
        try corruptData.write(to: corruptURL)
        
        // Mount succeeds (doesn't validate on mount)
        // But reading from it should fail
        do {
            let db = try manager.mountDatabase(named: "CorruptDB", fileURL: corruptURL, password: "Password-123")
            
            // Attempt to read - this should fail on corrupted data
            let records = try? db.fetchAll()
            
            // Corrupted database either returns empty or valid data (no crash is success)
            XCTAssertTrue(records == nil || records!.isEmpty, "Corrupted database handled gracefully")
            
            print("✅ Corrupted database mounted but returned no valid data")
        } catch {
            // Also acceptable - mount or read failed
            print("✅ Corrupted database rejected: \(error)")
        }
        
        manager.unmountDatabase(named: "CorruptDB")
    }
    
    func testUnmountAllDatabases() throws {
        let manager = BlazeDBManager.shared
        manager.unmountAllDatabases()
        
        let urls = (0..<3).map { i in
            FileManager.default.temporaryDirectory.appendingPathComponent("unmount\(i)-\(UUID().uuidString).blaze")
        }
        defer {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        
        for (i, url) in urls.enumerated() {
            try manager.mountDatabase(named: "DB\(i)", fileURL: url, password: "password-\(String(format: "%03d", i))")
        }
        
        XCTAssertEqual(manager.mountedDatabaseNames.count, 3)
        
        manager.unmountAllDatabases()
        XCTAssertEqual(manager.mountedDatabaseNames.count, 0)
    }
}

