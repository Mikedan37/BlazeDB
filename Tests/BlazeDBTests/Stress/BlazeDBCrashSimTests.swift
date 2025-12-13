//  BlazeDBCrashSimTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25
//
import XCTest
@testable import BlazeDB

final class BlazeDBCrashSimTests: XCTestCase {
    
    var dbClient: BlazeDBClient!
    var testFileURL: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        testFileURL = tempDir.appendingPathComponent("test_crash_sim.blazedb")
        
        // CRITICAL: Remove both main file AND metadata file
        if FileManager.default.fileExists(atPath: testFileURL.path) {
            try FileManager.default.removeItem(at: testFileURL)
        }
        let metaURL = testFileURL.deletingPathExtension().appendingPathExtension("meta")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.removeItem(at: metaURL)
        }
        
        dbClient = try BlazeDBClient(
            name: "CrashSimTestDB",
            fileURL: testFileURL,
            password: "BlazeDBCrashSimTest123!"
        )
    }

    override func tearDownWithError() throws {
        // CRITICAL: Remove both main file AND metadata file
        if FileManager.default.fileExists(atPath: testFileURL.path) {
            try FileManager.default.removeItem(at: testFileURL)
        }
        let metaURL = testFileURL.deletingPathExtension().appendingPathExtension("meta")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.removeItem(at: metaURL)
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
        
        // Flush metadata before crash test (only 1 record, < 100 threshold)
        if let collection = dbClient.collection as? DynamicCollection {
            try collection.persist()
        }

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

