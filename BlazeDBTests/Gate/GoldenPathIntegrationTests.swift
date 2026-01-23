//
//  GoldenPathIntegrationTests.swift
//  BlazeDBTests
//
//  Golden-path integration test: End-to-end lifecycle validation
//  Proves BlazeDB is usable for real developers without touching frozen core
//

import XCTest
@testable import BlazeDBCore

final class GoldenPathIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    var originalDB: BlazeDBClient!
    var originalDBPath: URL!
    var dumpPath: URL!
    var restoredDBPath: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        originalDBPath = tempDir.appendingPathComponent("golden-path-original.blazedb")
        dumpPath = tempDir.appendingPathComponent("golden-path-dump.blazedump")
        restoredDBPath = tempDir.appendingPathComponent("golden-path-restored.blazedb")
    }
    
    override func tearDown() {
        // Cleanup all database files
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    /// Golden-path integration test: Complete end-to-end lifecycle
    ///
    /// Validates:
    /// - Open → Insert → Query → Explain → Dump → Restore → Reopen → Verify
    ///
    /// This test proves BlazeDB is usable end-to-end without touching frozen core.
    func testGoldenPath_EndToEndLifecycle() throws {
        // STEP 1: Open database (happy path)
        print("\n=== STEP 1: Open Database ===")
        // Use openOrCreate with custom path for test isolation
        let dbName = "golden-path"
        let dbURL = tempDir.appendingPathComponent("\(dbName).blazedb")
        originalDB = try BlazeDBClient(name: dbName, fileURL: dbURL, password: "test-password-123")
        XCTAssertNotNil(originalDB, "Database should open successfully")
        XCTAssertEqual(originalDB.name, "golden-path", "Database name should match")
        print("✓ Database opened: \(originalDB.fileURL.path)")
        
        // STEP 2: Insert data (50+ records to force page flush / durability paths)
        print("\n=== STEP 2: Insert Data ===")
        let recordCount = 50
        var insertedRecords: [(id: UUID, name: String, count: Int)] = []
        
        for i in 1...recordCount {
            let name = "Record-\(i)"
            let count = i * 10
            let record = BlazeDataRecord([
                "name": .string(name),
                "count": .int(count),
                "index": .int(i)
            ])
            
            let id = try originalDB.insert(record)
            insertedRecords.append((id: id, name: name, count: count))
        }
        
        XCTAssertEqual(insertedRecords.count, recordCount, "All records should be inserted")
        print("✓ Inserted \(recordCount) records")
        
        // Verify records exist
        let allRecords = try originalDB.fetchAll()
        XCTAssertGreaterThanOrEqual(allRecords.count, recordCount, "Should have at least \(recordCount) records")
        print("✓ Verified \(allRecords.count) records exist")
        
        // STEP 3: Query data
        print("\n=== STEP 3: Query Data ===")
        // Query records where count > 250 (should return records 26-50)
        let queryResults = try originalDB.query()
            .where("count", greaterThan: .int(250))
            .orderBy("count", ascending: true)
            .execute()
            .records
        
        let expectedCount = 25  // Records 26-50 have count > 250
        XCTAssertEqual(queryResults.count, expectedCount, "Query should return \(expectedCount) records")
        
        // Verify query results match inserted data
        for result in queryResults {
            guard let name = result.string("name"),
                  let count = result.int("count") else {
                XCTFail("Query result should have name and count fields")
                continue
            }
            XCTAssertTrue(count > 250, "Count should be > 250")
            XCTAssertTrue(name.hasPrefix("Record-"), "Name should start with 'Record-'")
        }
        print("✓ Query returned \(queryResults.count) records matching filter")
        
        // STEP 4: Explain query cost
        print("\n=== STEP 4: Explain Query Cost ===")
        let explanation = try originalDB.query()
            .where("count", greaterThan: .int(250))
            .explainCost()
        
        XCTAssertNotNil(explanation, "Query explanation should exist")
        XCTAssertGreaterThanOrEqual(explanation.filterCount, 1, "Should have at least 1 filter")
        XCTAssertFalse(explanation.description.isEmpty, "Explanation description should not be empty")
        
        // Verify explanation doesn't change query results
        let queryResultsAfterExplain = try originalDB.query()
            .where("count", greaterThan: .int(250))
            .execute()
            .records
        
        XCTAssertEqual(queryResults.count, queryResultsAfterExplain.count, 
                      "Query results should be unchanged after explain")
        print("✓ Query explanation generated: \(explanation.description)")
        
        // STEP 5: Dump database
        print("\n=== STEP 5: Dump Database ===")
        try originalDB.export(to: dumpPath)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: dumpPath.path), 
                     "Dump file should exist")
        
        // Verify dump integrity
        let dumpHeader = try BlazeDBImporter.verify(dumpPath)
        XCTAssertNotNil(dumpHeader, "Dump header should be valid")
        XCTAssertGreaterThanOrEqual(dumpHeader.recordCount, recordCount, 
                                   "Dump should contain at least \(recordCount) records")
        print("✓ Dump created: \(dumpPath.path)")
        print("  Schema version: \(dumpHeader.schemaVersion)")
        print("  Record count: \(dumpHeader.recordCount)")
        
        // STEP 6: Restore database
        print("\n=== STEP 6: Restore Database ===")
        // Create new database for restore
        let restoredDB = try BlazeDBClient(name: "golden-path-restored", 
                                          fileURL: restoredDBPath, 
                                          password: "test-password-123")
        
        // Verify database is empty before restore
        let recordsBeforeRestore = try restoredDB.fetchAll()
        XCTAssertEqual(recordsBeforeRestore.count, 0, "Restored database should be empty before restore")
        
        // Restore dump
        try BlazeDBImporter.restore(from: dumpPath, to: restoredDB, allowSchemaMismatch: false)
        
        // Verify restore succeeded
        let recordsAfterRestore = try restoredDB.fetchAll()
        XCTAssertEqual(recordsAfterRestore.count, dumpHeader.recordCount, 
                      "Restored database should have same record count as dump")
        print("✓ Restore succeeded: \(recordsAfterRestore.count) records restored")
        
        // STEP 7: Reopen restored database
        print("\n=== STEP 7: Reopen Restored Database ===")
        // Close restored database and reopen via happy path
        let reopenedDB = try BlazeDBClient(name: "golden-path-restored", 
                                           fileURL: restoredDBPath, 
                                           password: "test-password-123")
        
        // Query all records
        let allRestoredRecords = try reopenedDB.query()
            .orderBy("index", ascending: true)
            .execute()
            .records
        
        XCTAssertEqual(allRestoredRecords.count, recordCount, 
                      "Reopened database should have \(recordCount) records")
        
        // Verify data content matches original
        for (index, restoredRecord) in allRestoredRecords.enumerated() {
            guard let name = restoredRecord.string("name"),
                  let count = restoredRecord.int("count"),
                  let recordIndex = restoredRecord.int("index") else {
                XCTFail("Restored record should have name, count, and index fields")
                continue
            }
            
            let originalRecord = insertedRecords[index]
            XCTAssertEqual(name, originalRecord.name, 
                          "Record \(index) name should match original")
            XCTAssertEqual(count, originalRecord.count, 
                          "Record \(index) count should match original")
            XCTAssertEqual(recordIndex, index + 1, 
                          "Record \(index) index should match")
        }
        print("✓ Reopened database: \(allRestoredRecords.count) records verified")
        
        // Verify no schema warnings
        let schemaVersion = try? reopenedDB.getSchemaVersion()
        XCTAssertNotNil(schemaVersion, "Schema version should be available")
        print("✓ Schema version: \(schemaVersion?.description ?? "none")")
        
        // STEP 8: Health check
        print("\n=== STEP 8: Health Check ===")
        let health = try reopenedDB.health()
        
        XCTAssertEqual(health.status, .ok, "Health status should be OK")
        XCTAssertTrue(health.reasons.isEmpty, "Should have no health warnings")
        print("✓ Health status: \(health.status.rawValue)")
        
        if !health.suggestedActions.isEmpty {
            print("  Suggested actions: \(health.suggestedActions.joined(separator: ", "))")
        }
        
        // FINAL VERIFICATION: Compare original and restored databases
        print("\n=== FINAL VERIFICATION ===")
        let originalStats = try originalDB.stats()
        let restoredStats = try reopenedDB.stats()
        
        XCTAssertEqual(originalStats.recordCount, restoredStats.recordCount,
                       "Record counts should match")
        print("✓ Original DB: \(originalStats.recordCount) records")
        print("✓ Restored DB: \(restoredStats.recordCount) records")
        
        print("\n=== Golden Path Test Complete ===")
        print("All steps passed: Open → Insert → Query → Explain → Dump → Restore → Reopen → Verify")
    }
}
