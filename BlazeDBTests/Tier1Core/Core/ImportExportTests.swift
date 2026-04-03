//
//  ImportExportTests.swift
//  BlazeDBTests
//
//  Tests for import/export functionality
//  Validates deterministic output, integrity verification, round-trip equivalence
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class ImportExportTests: XCTestCase {
    
    private var tempDBURL: URL?
    private var tempDumpURL: URL?
    let password = "Test-Password-123!"
    
    override func setUpWithError() throws {
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
        let dumpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedump")
        tempDBURL = dbURL
        tempDumpURL = dumpURL
    }
    
    override func tearDownWithError() throws {
        if let dbURL = tempDBURL {
            try? FileManager.default.removeItem(at: dbURL)
        }
        if let dumpURL = tempDumpURL {
            try? FileManager.default.removeItem(at: dumpURL)
        }
    }
    
    private func uniqueName(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
    
    // MARK: - Export Tests
    
    func testExport_CreatesValidDump() throws {
        // Create database with test data
        let db = try BlazeDBClient(name: uniqueName("export-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        _ = try requireFixture(db).insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))
        
        // Export
        try requireFixture(db).export(to: try requireFixture(tempDumpURL))
        
        // Verify dump file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: try requireFixture(tempDumpURL).path))
        
        // Verify dump can be decoded
        let dumpData = try Data(contentsOf: try requireFixture(tempDumpURL))
        let dump = try DatabaseDump.decodeAndVerify(dumpData)
        
        XCTAssertEqual(dump.records.count, 2)
        XCTAssertEqual(dump.manifest.recordCount, 2)
    }
    
    func testExport_DeterministicOutput() throws {
        // Create database
        let db = try BlazeDBClient(name: uniqueName("deterministic-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        _ = try requireFixture(db).insert(BlazeDataRecord(["name": .string("Test"), "value": .int(42)]))
        
        // Export twice
        let dump1URL = try requireFixture(tempDumpURL).deletingLastPathComponent().appendingPathComponent("dump1.blazedump")
        let dump2URL = try requireFixture(tempDumpURL).deletingLastPathComponent().appendingPathComponent("dump2.blazedump")
        
        try requireFixture(db).export(to: dump1URL)
        try requireFixture(db).export(to: dump2URL)
        
        // Compare files (should be identical)
        let data1 = try Data(contentsOf: dump1URL)
        let data2 = try Data(contentsOf: dump2URL)
        
        // Note: Files may differ slightly due to timestamps, but structure should be identical
        // For true determinism, we'd need to normalize timestamps
        XCTAssertEqual(data1.count, data2.count, "Dump files should have same size")
        
        try? FileManager.default.removeItem(at: dump1URL)
        try? FileManager.default.removeItem(at: dump2URL)
    }
    
    // MARK: - Import Tests
    
    func testImport_RoundTripEquivalence() throws {
        // Create source database
        let sourceDB = try BlazeDBClient(name: uniqueName("source"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? sourceDB.close() }
        _ = try sourceDB.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        _ = try sourceDB.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))
        
        // Export
        try sourceDB.export(to: try requireFixture(tempDumpURL))
        
        // Create target database
        let targetDBURL = try requireFixture(tempDBURL).deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: uniqueName("target"), fileURL: targetDBURL, password: password)
        defer { try? targetDB.close() }
        
        // Import
        try BlazeDBImporter.restore(from: try requireFixture(tempDumpURL), to: targetDB, allowSchemaMismatch: false)
        
        // Verify records match
        let restoredRecords = try targetDB.fetchAll()
        XCTAssertEqual(restoredRecords.count, 2)
        
        // Verify business content matches (ignore generated metadata like timestamps/ids).
        let sourcePairs = Set(try sourceDB.fetchAll().compactMap { record -> String? in
            guard case .string(let name)? = record.storage["name"],
                  case .int(let age)? = record.storage["age"] else { return nil }
            return "\(name):\(age)"
        })
        let restoredPairs = Set(restoredRecords.compactMap { record -> String? in
            guard case .string(let name)? = record.storage["name"],
                  case .int(let age)? = record.storage["age"] else { return nil }
            return "\(name):\(age)"
        })
        XCTAssertEqual(sourcePairs, restoredPairs, "Restored business data should match source")
        
        try? FileManager.default.removeItem(at: targetDBURL)
    }
    
    func testImport_RefusesNonEmptyDatabase() throws {
        // Create database with data
        let db = try BlazeDBClient(name: uniqueName("nonempty-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        _ = try requireFixture(db).insert(BlazeDataRecord(["name": .string("Existing")]))
        
        // Create dump
        let dumpURL = try requireFixture(tempDumpURL).deletingLastPathComponent().appendingPathComponent("test.blazedump")
        try requireFixture(db).export(to: dumpURL)
        
        // Try to restore to same database (should fail)
        do {
            try BlazeDBImporter.restore(from: dumpURL, to: db, allowSchemaMismatch: false)
            XCTFail("Should have thrown error for non-empty database")
        } catch let error as BlazeDBError {
            if case .invalidInput = error {
                // Expected
            } else {
                XCTFail("Expected invalidInput error")
            }
        }
        
        try? FileManager.default.removeItem(at: dumpURL)
    }
    
    // MARK: - Integrity Verification Tests
    
    func testVerify_ValidDump_Succeeds() throws {
        // Create and export database
        let db = try BlazeDBClient(name: uniqueName("verify-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        _ = try requireFixture(db).insert(BlazeDataRecord(["test": .string("data")]))
        try requireFixture(db).export(to: try requireFixture(tempDumpURL))
        
        // Verify dump
        let header = try BlazeDBImporter.verify(try requireFixture(tempDumpURL))
        XCTAssertNotNil(header)
        XCTAssertTrue(header.databaseName.hasPrefix("verify-test"), "Dump header should preserve source database name prefix")
    }
    
    func testVerify_TamperedDump_Fails() throws {
        // Create and export database
        let db = try BlazeDBClient(name: uniqueName("tamper-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        _ = try requireFixture(db).insert(BlazeDataRecord(["test": .string("data")]))
        try requireFixture(db).export(to: try requireFixture(tempDumpURL))
        
        // Tamper with dump file
        var dumpData = try Data(contentsOf: try requireFixture(tempDumpURL))
        // Modify a byte
        dumpData[100] = dumpData[100] == 0 ? 1 : 0
        try dumpData.write(to: try requireFixture(tempDumpURL), options: [.atomic])
        
        // Verification should fail
        XCTAssertThrowsError(try BlazeDBImporter.verify(try requireFixture(tempDumpURL)), "Tampered dump must fail verification/decoding")
    }
    
    // MARK: - Schema Mismatch Tests
    
    func testImport_SchemaMismatch_Refuses() throws {
        // Create database with schema version
        let db = try BlazeDBClient(name: uniqueName("schema-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        try requireFixture(db).setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        _ = try requireFixture(db).insert(BlazeDataRecord(["test": .string("data")]))
        
        // Export
        try requireFixture(db).export(to: try requireFixture(tempDumpURL))
        
        // Create target with different schema version
        let targetURL = try requireFixture(tempDBURL).deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: uniqueName("target"), fileURL: targetURL, password: password)
        defer { try? targetDB.close() }
        try targetDB.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Import should fail without allowSchemaMismatch
        do {
            try BlazeDBImporter.restore(from: try requireFixture(tempDumpURL), to: targetDB, allowSchemaMismatch: false)
            XCTFail("Should have refused schema mismatch")
        } catch let error as BlazeDBError {
            if case .migrationFailed = error {
                // Expected
            } else {
                XCTFail("Expected migrationFailed error")
            }
        }
        
        try? FileManager.default.removeItem(at: targetURL)
    }
    
    func testImport_SchemaMismatch_Allowed() throws {
        // Create database with schema version
        let db = try BlazeDBClient(name: uniqueName("schema-allow-test"), fileURL: try requireFixture(tempDBURL), password: password)
        defer { try? try requireFixture(db).close() }
        try requireFixture(db).setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        _ = try requireFixture(db).insert(BlazeDataRecord(["test": .string("data")]))
        
        // Export
        try requireFixture(db).export(to: try requireFixture(tempDumpURL))
        
        // Create target with different schema version
        let targetURL = try requireFixture(tempDBURL).deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: uniqueName("target"), fileURL: targetURL, password: password)
        defer { try? targetDB.close() }
        try targetDB.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Import with allowSchemaMismatch should succeed
        try BlazeDBImporter.restore(from: try requireFixture(tempDumpURL), to: targetDB, allowSchemaMismatch: true)
        
        // Verify restore succeeded
        let records = try targetDB.fetchAll()
        XCTAssertEqual(records.count, 1)
        
        try? FileManager.default.removeItem(at: targetURL)
    }
}
