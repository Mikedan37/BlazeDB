//  Untitled.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBRecoveryTests: XCTestCase {
    
    func testRecoveryAfterCrashSimulation() throws {
        // 1. Setup a temp DB file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("crashy.blazedb")
        try? FileManager.default.removeItem(at: tempURL) // Clean slate

        // 2. Insert a record normally
        let db = try BlazeDBClient(fileURL: tempURL, password: "password")
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Recovery Test"),
            "createdAt": .date(.now),
            "status": .string("open")
        ]))

        print("✅ Inserted initial record: \(id)")

        // 3. Simulate app crash before update
        setenv("BLAZEDB_CRASH_BEFORE_UPDATE", "1", 1)
        do {
            _ = try BlazeDBClient(fileURL: tempURL, password: "password").update(id: id, with: BlazeDataRecord([
                "title": .string("Updated Title")
            ]))
            XCTFail("Expected crash but didn’t get one")
        } catch {
            print("💥 Expected crash simulated")
        }

        // 4. Reopen DB *without* crash mode and verify record is still valid
        unsetenv("BLAZEDB_CRASH_BEFORE_UPDATE")
        let recovered = try BlazeDBClient(fileURL: tempURL, password: "password")
        let fetched = try recovered.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should still be recoverable after crash")
        print("✅ Recovery check passed")
    }
}
