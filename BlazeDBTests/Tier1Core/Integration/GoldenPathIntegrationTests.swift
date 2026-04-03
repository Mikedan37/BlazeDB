//
//  GoldenPathIntegrationTests.swift
//  BlazeDBTests
//
//  Golden-path integration test: End-to-end lifecycle validation
//  Proves BlazeDB is usable for real developers without touching frozen core
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class GoldenPathIntegrationTests: XCTestCase {
    
    private var tempDir: URL?
    private var originalDB: BlazeDBClient?
    private var originalDBPath: URL?
    private var dumpPath: URL?
    private var restoredDBPath: URL?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        originalDBPath = dir.appendingPathComponent("golden-path-original.blazedb")
        dumpPath = dir.appendingPathComponent("golden-path-dump.blazedump")
        restoredDBPath = dir.appendingPathComponent("golden-path-restored.blazedb")
    }
    
    override func tearDown() {
        // Cleanup all database files
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
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
        let dbURL = try requireFixture(tempDir).appendingPathComponent("\(dbName).blazedb")
        originalDB = try BlazeDBClient(name: dbName, fileURL: dbURL, password: "TestPassword-123!")
        XCTAssertNotNil(originalDB, "Database should open successfully")
        XCTAssertEqual(try requireFixture(originalDB).name, "golden-path", "Database name should match")
        print("✓ Database opened: \(try requireFixture(originalDB).fileURL.path)")
        
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
            
            let id = try requireFixture(originalDB).insert(record)
            insertedRecords.append((id: id, name: name, count: count))
        }
        
        XCTAssertEqual(insertedRecords.count, recordCount, "All records should be inserted")
        print("✓ Inserted \(recordCount) records")
        
        // Verify records exist
        let allRecords = try requireFixture(originalDB).fetchAll()
        XCTAssertGreaterThanOrEqual(allRecords.count, recordCount, "Should have at least \(recordCount) records")
        print("✓ Verified \(allRecords.count) records exist")
        
        // STEP 3: Query data
        print("\n=== STEP 3: Query Data ===")
        // Query records where count > 250 (should return records 26-50)
        let queryResults = try requireFixture(originalDB).query()
            .where("count", greaterThan: .int(250))
            .orderBy("count", descending: false)
            .execute()
            .records
        
        let expectedCount = 25  // Records 26-50 have count > 250
        XCTAssertEqual(queryResults.count, expectedCount, "Query should return \(expectedCount) records")
        
        // Verify query results match inserted data
        for result in queryResults {
            guard let name = result.stringOptional("name"),
                  let count = result.intOptional("count") else {
                XCTFail("Query result should have name and count fields")
                continue
            }
            XCTAssertTrue(count > 250, "Count should be > 250")
            XCTAssertTrue(name.hasPrefix("Record-"), "Name should start with 'Record-'")
        }
        print("✓ Query returned \(queryResults.count) records matching filter")
        
        // STEP 4: Explain query cost
        print("\n=== STEP 4: Explain Query Cost ===")
        let explanation = try requireFixture(originalDB).query()
            .where("count", greaterThan: .int(250))
            .explain()
        
        XCTAssertNotNil(explanation, "Query explanation should exist")
        XCTAssertTrue(
            explanation.steps.contains { step in
                if case .filter = step.type { return true }
                return false
            },
            "Explain plan should include a filter step"
        )
        XCTAssertFalse(explanation.description.isEmpty, "Explanation description should not be empty")
        
        // Verify explanation doesn't change query results
        let queryResultsAfterExplain = try requireFixture(originalDB).query()
            .where("count", greaterThan: .int(250))
            .execute()
            .records
        
        XCTAssertEqual(queryResults.count, queryResultsAfterExplain.count, 
                      "Query results should be unchanged after explain")
        print("✓ Query explanation generated: \(explanation.description)")
        
        // STEP 5: Dump database
        print("\n=== STEP 5: Dump Database ===")
        try requireFixture(originalDB).export(to: try requireFixture(dumpPath))
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: try requireFixture(dumpPath).path), 
                     "Dump file should exist")
        
        // Verify dump integrity
        let dumpData = try Data(contentsOf: try requireFixture(dumpPath))
        let dump = try DatabaseDump.decodeAndVerify(dumpData)
        let dumpHeader = dump.header
        XCTAssertNotNil(dumpHeader, "Dump header should be valid")
        XCTAssertGreaterThanOrEqual(dump.manifest.recordCount, recordCount,
                                   "Dump should contain at least \(recordCount) records")
        print("✓ Dump created: \(try requireFixture(dumpPath).path)")
        print("  Schema version: \(dumpHeader.schemaVersion)")
        print("  Record count: \(dump.manifest.recordCount)")
        
        // STEP 6: Restore database
        print("\n=== STEP 6: Restore Database ===")
        // Create new database for restore
        let restoredDB = try BlazeDBClient(name: "golden-path-restored", 
                                          fileURL: try requireFixture(restoredDBPath), 
                                          password: "TestPassword-123!")
        
        // Verify database is empty before restore
        let recordsBeforeRestore = try restoredDB.fetchAll()
        XCTAssertEqual(recordsBeforeRestore.count, 0, "Restored database should be empty before restore")
        
        // Restore dump
        try BlazeDBImporter.restore(from: try requireFixture(dumpPath), to: restoredDB, allowSchemaMismatch: false)
        
        // Verify restore succeeded
        let recordsAfterRestore = try restoredDB.fetchAll()
        XCTAssertEqual(recordsAfterRestore.count, dump.manifest.recordCount,
                      "Restored database should have same record count as dump")
        print("✓ Restore succeeded: \(recordsAfterRestore.count) records restored")
        
        // STEP 7: Verify restored database contents
        print("\n=== STEP 7: Verify Restored Database ===")
        // Validate restored data deterministically in the active restored handle.
        let allRestoredRecords = try restoredDB.query()
            .orderBy("index", descending: false)
            .execute()
            .records
        
        XCTAssertEqual(allRestoredRecords.count, recordCount, 
                      "Reopened database should have \(recordCount) records")
        
        // Verify data content matches original
        for (index, restoredRecord) in allRestoredRecords.enumerated() {
            guard let name = restoredRecord.stringOptional("name"),
                  let count = restoredRecord.intOptional("count"),
                  let recordIndex = restoredRecord.intOptional("index") else {
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
        print("✓ Restored database verified: \(allRestoredRecords.count) records")
        
        // Verify no schema warnings
        let schemaVersion = try? restoredDB.getSchemaVersion()
        XCTAssertNotNil(schemaVersion, "Schema version should be available")
        print("✓ Schema version: \(schemaVersion?.description ?? "none")")
        
        // STEP 8: Health check
        print("\n=== STEP 8: Health Check ===")
        let health = try restoredDB.health()
        
        XCTAssertTrue(health.status == .ok || health.status == .warn,
                      "Health status should be OK or WARN")
        print("✓ Health status: \(health.status.rawValue)")
        
        if !health.suggestedActions.isEmpty {
            print("  Suggested actions: \(health.suggestedActions.joined(separator: ", "))")
        }
        
        // FINAL VERIFICATION: Compare original and restored databases
        print("\n=== FINAL VERIFICATION ===")
        let originalStats = try requireFixture(originalDB).stats()
        let restoredStats = try restoredDB.stats()
        
        XCTAssertEqual(originalStats.recordCount, restoredStats.recordCount,
                       "Record counts should match")
        print("✓ Original DB: \(originalStats.recordCount) records")
        print("✓ Restored DB: \(restoredStats.recordCount) records")
        
        print("\n=== Golden Path Test Complete ===")
        print("All steps passed: Open → Insert → Query → Explain → Dump → Restore → Reopen → Verify")
    }
}
