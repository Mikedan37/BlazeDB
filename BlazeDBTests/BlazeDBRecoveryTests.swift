//  Untitled.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

final class BlazeDBRecoveryTests: XCTestCase {
    
    /// Convenience to isolate crash flag so it doesn’t leak across tests
    private let crashEnvKey = "BLAZEDB_CRASH_BEFORE_UPDATE"
    
    override func tearDown() {
        // Always clear the crash flag after each test
        unsetenv(crashEnvKey)
        super.tearDown()
    }
    
    func testRecoveryAfterCrashSimulation() throws {
        // 1. Setup a temp DB file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("crashy.blazedb")
        try? FileManager.default.removeItem(at: tempURL) // clean slate
        
        // 2. Insert a record normally
        let db = try BlazeDBClient(
            name: "RecoveryTestDB",
            fileURL: tempURL,
            password: "password"
        )
        
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Recovery Test"),
            "createdAt": .date(.now),
            "status": .string("open")
        ]))
        
        print("✅ Inserted initial record: \(id)")
        
        // 3. Simulate app crash before update
        setenv(crashEnvKey, "1", 1)
        do {
            let crashy = try BlazeDBClient(
                name: "RecoveryTestDB",
                fileURL: tempURL,
                password: "password"
            )
            _ = try crashy.update(id: id, with: BlazeDataRecord([
                "title": .string("Updated Title")
            ]))
            XCTFail("Expected simulated crash but update completed")
        } catch {
            print("💥 Simulated crash occurred as expected")
        }
        
        // 4. Reopen DB *without* crash mode and verify record is still valid
        unsetenv(crashEnvKey)
        let recovered = try BlazeDBClient(
            name: "RecoveryTestDB",
            fileURL: tempURL,
            password: "password"
        )
        
        let fetched = try recovered.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should still be recoverable after crash")
        XCTAssertEqual(fetched?.storage["title"], .string("Recovery Test"),
                       "Title should not have been updated due to crash")
        
        print("✅ Recovery check passed")
    }
}
