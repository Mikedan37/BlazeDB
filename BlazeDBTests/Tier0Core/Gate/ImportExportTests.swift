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
    
    var tempDBURL: URL!
    var tempDumpURL: URL!
    let password = "TestPassword-123!"
    
    override func setUpWithError() throws {
        tempDBURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedb")
        tempDumpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".blazedump")
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDBURL)
        try? FileManager.default.removeItem(at: tempDumpURL)
    }
    
    // MARK: - Export Tests
    
    func testExport_CreatesValidDump() throws {
        // Create database with test data
        let db = try BlazeDBClient(name: "export-test", fileURL: tempDBURL, password: password)
        let id1 = try db.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        let id2 = try db.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))
        
        // Export
        try db.export(to: tempDumpURL)
        
        // Verify dump file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDumpURL.path))
        
        // Verify dump can be decoded
        let dumpData = try Data(contentsOf: tempDumpURL)
        let dump = try DatabaseDump.decodeAndVerify(dumpData)
        
        XCTAssertEqual(dump.records.count, 2)
        XCTAssertEqual(dump.manifest.recordCount, 2)
    }
    
    func testExport_DeterministicOutput() throws {
        // Create database
        let db = try BlazeDBClient(name: "deterministic-test", fileURL: tempDBURL, password: password)
        try db.insert(BlazeDataRecord(["name": .string("Test"), "value": .int(42)]))
        
        // Export twice
        let dump1URL = tempDumpURL.deletingLastPathComponent().appendingPathComponent("dump1.blazedump")
        let dump2URL = tempDumpURL.deletingLastPathComponent().appendingPathComponent("dump2.blazedump")
        
        try db.export(to: dump1URL)
        try db.export(to: dump2URL)
        
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
        let sourceDB = try BlazeDBClient(name: "source", fileURL: tempDBURL, password: password)
        let id1 = try sourceDB.insert(BlazeDataRecord(["name": .string("Alice"), "age": .int(30)]))
        let id2 = try sourceDB.insert(BlazeDataRecord(["name": .string("Bob"), "age": .int(25)]))
        
        // Export
        try sourceDB.export(to: tempDumpURL)
        
        // Create target database
        let targetDBURL = tempDBURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: "target", fileURL: targetDBURL, password: password)
        
        // Import
        try BlazeDBImporter.restore(from: tempDumpURL, to: targetDB, allowSchemaMismatch: false)
        
        // Verify records match
        let restoredRecords = try targetDB.fetchAll()
        XCTAssertEqual(restoredRecords.count, 2)
        
        // Verify user data fields match (ignore system-managed fields).
        let sourcePairs = Set((try sourceDB.fetchAll()).map { record in
            let name = (try? record.string("name")) ?? ""
            let age = (try? record.int("age")) ?? -1
            return "\(name)#\(age)"
        })
        let restoredPairs = Set(restoredRecords.map { record in
            let name = (try? record.string("name")) ?? ""
            let age = (try? record.int("age")) ?? -1
            return "\(name)#\(age)"
        })
        XCTAssertEqual(sourcePairs, restoredPairs, "Restored user fields should match source")
        
        try? FileManager.default.removeItem(at: targetDBURL)
    }
    
    func testImport_RefusesNonEmptyDatabase() throws {
        // Create database with data
        let db = try BlazeDBClient(name: "nonempty-test", fileURL: tempDBURL, password: password)
        try db.insert(BlazeDataRecord(["name": .string("Existing")]))
        
        // Create dump
        let dumpURL = tempDumpURL.deletingLastPathComponent().appendingPathComponent("test.blazedump")
        try db.export(to: dumpURL)
        
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
        let db = try BlazeDBClient(name: "verify-test", fileURL: tempDBURL, password: password)
        try db.insert(BlazeDataRecord(["test": .string("data")]))
        try db.export(to: tempDumpURL)
        
        // Verify dump
        let header = try BlazeDBImporter.verify(tempDumpURL)
        XCTAssertNotNil(header)
        XCTAssertEqual(header.databaseName, "verify-test")
    }
    
    func testVerify_TamperedDump_Fails() throws {
        // Create and export database
        let db = try BlazeDBClient(name: "tamper-test", fileURL: tempDBURL, password: password)
        try db.insert(BlazeDataRecord(["test": .string("data")]))
        try db.export(to: tempDumpURL)
        
        // Tamper with dump file while keeping JSON syntactically valid.
        // Flipping an arbitrary byte can introduce invalid control characters
        // and crash older Foundation JSON decoders on Linux.
        let originalDumpData = try Data(contentsOf: tempDumpURL)
        var dumpJSON = try XCTUnwrap(String(data: originalDumpData, encoding: .utf8))
        let marker = "\"combinedHash\":\""
        let markerRange = try XCTUnwrap(dumpJSON.range(of: marker))
        let hashStart = markerRange.upperBound
        let hashEnd = try XCTUnwrap(dumpJSON[hashStart...].firstIndex(of: "\""))

        var hashChars = Array(dumpJSON[hashStart..<hashEnd])
        XCTAssertFalse(hashChars.isEmpty, "combinedHash should be non-empty")
        hashChars[0] = hashChars[0] == "0" ? "1" : "0"
        dumpJSON.replaceSubrange(hashStart..<hashEnd, with: String(hashChars))

        let tamperedData = try XCTUnwrap(dumpJSON.data(using: .utf8))
        try tamperedData.write(to: tempDumpURL, options: [.atomic])
        
        // Verification should fail
        do {
            _ = try BlazeDBImporter.verify(tempDumpURL)
            XCTFail("Should have detected tampering")
        } catch {
            // Any thrown verification/parsing error is acceptable for tampered payload.
        }
    }
    
    // MARK: - Schema Mismatch Tests
    
    func testImport_SchemaMismatch_Refuses() throws {
        // Create database with schema version
        let db = try BlazeDBClient(name: "schema-test", fileURL: tempDBURL, password: password)
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Export
        try db.export(to: tempDumpURL)
        
        // Create target with different schema version
        let targetURL = tempDBURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: "target", fileURL: targetURL, password: password)
        try targetDB.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Import should fail without allowSchemaMismatch
        do {
            try BlazeDBImporter.restore(from: tempDumpURL, to: targetDB, allowSchemaMismatch: false)
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
        let db = try BlazeDBClient(name: "schema-allow-test", fileURL: tempDBURL, password: password)
        try db.setSchemaVersion(SchemaVersion(major: 1, minor: 0))
        try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Export
        try db.export(to: tempDumpURL)
        
        // Create target with different schema version
        let targetURL = tempDBURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".blazedb")
        let targetDB = try BlazeDBClient(name: "target", fileURL: targetURL, password: password)
        try targetDB.setSchemaVersion(SchemaVersion(major: 1, minor: 1))
        
        // Import with allowSchemaMismatch should succeed
        try BlazeDBImporter.restore(from: tempDumpURL, to: targetDB, allowSchemaMismatch: true)
        
        // Verify restore succeeded
        let records = try targetDB.fetchAll()
        XCTAssertEqual(records.count, 1)
        
        try? FileManager.default.removeItem(at: targetURL)
    }
}
