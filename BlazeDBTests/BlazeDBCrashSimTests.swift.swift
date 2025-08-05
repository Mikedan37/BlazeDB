//  BlazeDBCrashSimTests.swift.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25

import XCTest
@testable import BlazeDB

final class BlazeDBCrashSimTests: XCTestCase {
    
    var dbClient: BlazeDBClient!
    var testFileURL: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        testFileURL = tempDir.appendingPathComponent("test_crash_sim.blazedb")
        if FileManager.default.fileExists(atPath: testFileURL.path) {
            try FileManager.default.removeItem(at: testFileURL)
        }
        dbClient = try BlazeDBClient(fileURL: testFileURL, password: "test123")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: testFileURL.path) {
            try FileManager.default.removeItem(at: testFileURL)
        }
    }

    func testSimulatedCrashDuringWrite_rollsBack() throws {
        // Insert an initial record to create a "safe" state
        let originalRecord = BlazeDataRecord([
            "title": .string("Before crash"),
            "createdAt": .date(Date()),
            "status": .string("open")
        ])
        let originalID = try dbClient.insert(originalRecord)

        // Simulate crashing write
        do {
            try dbClient.performSafeWrite {
                let crashRecord = BlazeDataRecord([
                    "title": .string("Crash incoming"),
                    "createdAt": .date(Date()),
                    "status": .string("inProgress")
                ])
                _ = try dbClient.insert(crashRecord)
                throw NSError(domain: "TestSimulatedCrash", code: 99, userInfo: nil)
            }
            XCTFail("Should have thrown before reaching here")
        } catch {
            // Expected
        }

        // Ensure database state is intact (original only, no partial writes)
        let all = try dbClient.fetchAll()
        XCTAssertEqual(all.count, 1)
        let fetched = try dbClient.fetch(id: originalID)
        XCTAssertEqual(fetched?.storage["title"], .string("Before crash"))
    }

    func testDatabaseIsValidAfterSimulatedCrash() throws {
        XCTAssertNoThrow(try dbClient.validateDatabaseIntegrity())
    }
}

