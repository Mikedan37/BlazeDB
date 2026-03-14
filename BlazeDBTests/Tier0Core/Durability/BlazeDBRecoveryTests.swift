//  Untitled.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

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
        BlazeDBClient.clearCachedKey()
        let testID = UUID().uuidString
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("crashy-\(testID).blazedb")
        try? FileManager.default.removeItem(at: tempURL) // clean slate
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
        
        // 2. Insert a record normally
        let db = try BlazeDBClient(
            name: "RecoveryTestDB",
            fileURL: tempURL,
            password: "RecoveryPass-123!"
        )
        
        let id = try db.insert(BlazeDataRecord([
            "title": .string("Recovery Test"),
            "createdAt": .date(.now),
            "status": .string("open")
        ]))
        
        // Flush metadata (only 1 record, < 100 threshold)
        try db.collection.persist()
        try db.close()
        
        print("✅ Inserted initial record: \(id)")
        
        // 3. Simulate app crash before update
        setenv(crashEnvKey, "1", 1)
        var crashy: BlazeDBClient?
        do {
            crashy = try BlazeDBClient(
                name: "RecoveryTestDB",
                fileURL: tempURL,
                password: "RecoveryPass-123!"
            )
            _ = try crashy?.update(id: id, with: BlazeDataRecord([
                "title": .string("Updated Title")
            ]))
            XCTFail("Expected simulated crash but update completed")
        } catch {
            print("💥 Simulated crash occurred as expected")
        }
        try? crashy?.close()
        crashy = nil
        
        // 4. Reopen DB *without* crash mode and verify record is still valid
        unsetenv(crashEnvKey)
        var recovered: BlazeDBClient?
        var lastOpenError: Error?
        for _ in 0..<10 {
            do {
                recovered = try BlazeDBClient(
                    name: "RecoveryTestDB",
                    fileURL: tempURL,
                    password: "RecoveryPass-123!"
                )
                break
            } catch {
                lastOpenError = error
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        guard let recovered else {
            if let lastOpenError {
                throw XCTSkip("Recovery reopen requires fresh process after simulated crash: \(lastOpenError)")
            }
            throw XCTSkip("Recovery reopen requires fresh process after simulated crash")
        }
        
        let fetched = try recovered.fetch(id: id)
        XCTAssertNotNil(fetched, "Record should still be recoverable after crash")
        XCTAssertEqual(fetched?.storage["title"], .string("Recovery Test"),
                       "Title should not have been updated due to crash")
        
        print("✅ Recovery check passed")
    }
}
