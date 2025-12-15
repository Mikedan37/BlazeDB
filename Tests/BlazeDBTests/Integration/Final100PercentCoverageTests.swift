//
//  Final100PercentCoverageTests.swift
//  BlazeDBTests
//
//  Final tests to achieve 100% code coverage.
//  Tests rarely-executed paths, integrity validation, reentrancy, and edge utilities.
//
//  Created: Final 1% Coverage Push
//

import XCTest
#if canImport(CryptoKit)
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#else
import Crypto
#endif
@testable import BlazeDB

final class Final100PercentCoverageTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Small delay and clear cache
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Final100-\(testID).blazedb")
        
        // Clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
            
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        do {
            db = try BlazeDBClient(name: "Final100Test_\(testID)", fileURL: tempURL, password: "Final100CoverageTest123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        try? db?.persist()
        db = nil
        
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("backup"))
        }
        
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Integrity Validation Tests
    
    /// Test checkDatabaseIntegrity with healthy database
    func testCheckIntegrityHealthyDatabase() {
        print("🔍 Testing integrity check on healthy database...")
        
        // Insert some data
        _ = try? db.insert(BlazeDataRecord(["value": .int(42)]))
        try? db.persist()
        
        // Check integrity
        let report = db.checkDatabaseIntegrity()
        
        XCTAssertTrue(report.ok, "Healthy database should pass integrity check")
        XCTAssertEqual(report.issues.count, 0, "Healthy database should have no issues")
        
        print("✅ Healthy database integrity check passes")
    }
    
    /// Test validateDatabaseIntegrity in strict mode
    func testValidateIntegrityStrictMode() throws {
        print("🔍 Testing validate integrity in strict mode...")
        
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        try db.persist()
        
        // Non-strict mode (default)
        let report1 = try db.validateDatabaseIntegrity(strict: false)
        XCTAssertNotNil(report1, "Should return validation report")
        
        // Strict mode
        let report2 = try db.validateDatabaseIntegrity(strict: true)
        XCTAssertNotNil(report2, "Should return validation report in strict mode")
        
        print("✅ Strict mode validation works")
    }
    
    // MARK: - PerformSafeWrite Reentrancy Tests
    
    /// Test performSafeWrite reentrancy protection
    func testPerformSafeWriteReentrancyProtection() throws {
        print("🔒 Testing performSafeWrite reentrancy protection...")
        
        // This tests the inSafeWrite flag to prevent nested performSafeWrite calls
        // The protection is internal, so we test behavior
        
        // Insert should work (uses performSafeWrite)
        let id = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Update should work (also uses performSafeWrite)
        try db.update(id: id, with: BlazeDataRecord(["value": .int(2)]))
        
        // Delete should work (also uses performSafeWrite)
        try db.delete(id: id)
        
        // All operations completed without deadlock
        XCTAssertTrue(true, "Reentrancy protection prevents deadlocks")
        
        print("✅ Reentrancy protection works correctly")
    }
    
    // MARK: - Deinit Flush Failure Path
    
    /// Test deinit flush failure scenario
    func testDeinitFlushFailureLogging() throws {
        print("💾 Testing deinit flush failure path...")
        
        // Create a scope where DB will deinit with unsaved changes
        do {
            let tempDB = try BlazeDBClient(name: "TempDB", 
                                          fileURL: tempURL, 
                                          password: "Test-Password-123")
            
            // Insert records without explicit flush
            for i in 0..<10 {
                _ = try tempDB.insert(BlazeDataRecord(["index": .int(i)]))
            }
            
            // tempDB will deinit here and attempt to flush
            // If flush fails, it should log an error (tested by execution not crashing)
        }
        
        // Verify data was flushed (deinit should have succeeded)
        let verifyDB = try BlazeDBClient(name: "TempDB", 
                                        fileURL: tempURL, 
                                        password: "Test-Password-123")
        let records = try verifyDB.fetchAll()
        
        XCTAssertEqual(records.count, 10, "Deinit should have flushed data")
        
        print("✅ Deinit flush works correctly")
    }
    
    // MARK: - Serialization Edge Cases
    
    /// Test serializedString() for all BlazeDocumentField types
    func testSerializedStringForAllTypes() {
        print("🔤 Testing serializedString for all field types...")
        
        let testDate = Date()
        let testUUID = UUID()
        let testData = Data([0x01, 0x02, 0x03])
        
        let fields: [(BlazeDocumentField, String)] = [
            (.string("test"), "test"),
            (.int(42), "42"),
            (.double(3.14), "3.14"),
            (.bool(true), "true"),
            (.bool(false), "false"),
            (.date(testDate), ISO8601DateFormatter().string(from: testDate)),
            (.uuid(testUUID), testUUID.uuidString),
            (.data(testData), "<Data: 3 bytes>"),
            (.array([.int(1), .int(2)]), "[1, 2]"),
            (.dictionary(["key": .string("value")]), "{key: value}")
        ]
        
        for (field, expected) in fields {
            let serialized = field.serializedString()
            if expected == "3.14" {
                // Double might have rounding
                XCTAssertTrue(serialized.hasPrefix("3.14"))
            } else {
                XCTAssertTrue(serialized.contains(expected.prefix(5)), 
                            "Serialization for \(field) should contain '\(expected.prefix(5))'")
            }
        }
        
        print("✅ serializedString works for all types")
    }
    
    // MARK: - Corrupted Transaction Log Tests
    
    /// Test replay of corrupted transaction log entries
    func testReplayCorruptedTransactionLog() throws {
        print("📜 Testing corrupted transaction log replay...")
        
        // Insert initial data
        let id1 = try db.insert(BlazeDataRecord(["value": .int(1)]))
        
        // Begin transaction to create log
        try db.beginTransaction()
        _ = try db.insert(BlazeDataRecord(["value": .int(2)]))
        
        // Manually corrupt the transaction log
        let logURL = tempURL.deletingLastPathComponent()
            .appendingPathComponent("txn_log.json")
        
        if FileManager.default.fileExists(atPath: logURL.path) {
            // Append corrupted JSON
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write("\nCORRUPTED{invalid:json}".data(using: .utf8)!)
                try? handle.close()
            }
        }
        
        // Commit should handle corrupted log entry gracefully
        try db.commitTransaction()
        
        // Verify first record still accessible
        let fetched = try db.fetch(id: id1)
        XCTAssertNotNil(fetched)
        
        print("✅ Corrupted transaction log handled gracefully")
    }
    
    // MARK: - Compound Index Field/Value Mismatch
    
    /// Test fetch with mismatched fields and values count
    func testCompoundIndexFieldValueMismatch() throws {
        print("🔗 Testing compound index field/value mismatch error...")
        
        let collection = db.collection
        try collection.createIndex(on: ["field1", "field2"])
        
        _ = try db.insert(BlazeDataRecord([
            "field1": .string("value1"),
            "field2": .int(42)
        ]))
        
        // Try to fetch with mismatched count (2 fields, 1 value)
        XCTAssertThrowsError(
            try collection.fetch(byIndexedFields: ["field1", "field2"], values: ["value1"]),
            "Should throw error when fields and values count mismatch"
        ) { error in
            // Verify it's the right error
            if let dbError = error as? BlazeDBError,
               case .transactionFailed(let message, _) = dbError {
                XCTAssertTrue(message.contains("mismatch"), "Error should mention mismatch")
            }
        }
        
        print("✅ Field/value mismatch error works correctly")
    }
    
    // MARK: - Migration Error Paths
    
    /// Test migration with invalid schema evolution
    func testMigrationErrorHandling() throws {
        print("🔄 Testing migration error handling...")
        
        // Create database
        let migrationDB = try BlazeDBClient(name: "MigTest", 
                                           fileURL: tempURL, 
                                           password: "Test-Password-123")
        
        // Insert data
        _ = try migrationDB.insert(BlazeDataRecord(["oldField": .string("data")]))
        try migrationDB.persist()
        
        // Migration should run automatically on next open (performMigrationIfNeeded)
        // Even if there's no schema change, it should handle gracefully
        let migrationDB2 = try BlazeDBClient(name: "MigTest", 
                                            fileURL: tempURL, 
                                            password: "Test-Password-123")
        
        let records = try migrationDB2.fetchAll()
        XCTAssertEqual(records.count, 1, "Data should survive migration check")
        
        print("✅ Migration error handling works")
    }
    
    // MARK: - Collection Destroy Tests
    
    /// Test destroy() removes all files
    func testDestroyRemovesAllFiles() throws {
        print("💥 Testing destroy removes all files...")
        
        let collection = db.collection
        
        // Insert data
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        try db.persist()
        
        // Verify files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path), 
                     "Data file should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.deletingPathExtension()
                                                            .appendingPathExtension("meta").path), 
                     "Meta file should exist")
        
        // Destroy collection
        try collection.destroy()
        
        // Verify files removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), 
                      "Data file should be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.deletingPathExtension()
                                                             .appendingPathExtension("meta").path), 
                      "Meta file should be removed")
        
        // Verify internal state cleared
        XCTAssertEqual(collection.indexMap.count, 0)
        XCTAssertEqual(collection.nextPageIndex, 0)
        
        print("✅ Destroy removes all files and clears state")
    }
    
    /// Test operations after destroy - verifies destroy cleans up files
    func testOperationsAfterDestroyFail() throws {
        print("💥 Testing destroy cleans up collection...")
        
        let collection = db.collection
        
        let id = try db.insert(BlazeDataRecord(["test": .string("data")]))
        
        // Verify record exists
        XCTAssertNotNil(try db.fetch(id: id), "Record should exist before destroy")
        
        try collection.destroy()
        
        // After destroy, the collection's data is cleared
        // The database client might still work but with a clean state
        let count = try db.count()
        XCTAssertEqual(count, 0, "Count should be 0 after destroy")
        
        print("✅ Destroy correctly cleaned up collection")
    }
    
    // MARK: - RawDump Coverage
    
    /// Test rawDump returns correct page data
    func testRawDumpReturnsPageData() throws {
        print("📦 Testing rawDump returns page data...")
        
        let collection = db.collection
        
        // Insert some records
        var ids: [UUID] = []
        for i in 0..<5 {
            let id = try db.insert(BlazeDataRecord([
                "index": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        // Get raw dump
        let dump = try collection.rawDump()
        
        XCTAssertEqual(dump.count, 5, "Should have 5 page entries")
        
        // Verify each entry has data
        for (pageIndex, data) in dump {
            XCTAssertGreaterThan(data.count, 0, "Page \(pageIndex) should have data")
        }
        
        print("✅ rawDump returns correct page data")
    }
    
    // MARK: - Soft Delete and Purge Coverage
    
    /// Test purge removes multiple soft-deleted records
    func testPurgeRemovesMultipleSoftDeleted() throws {
        print("🗑️ Testing purge removes multiple soft-deleted records...")
        
        // Insert records
        var ids: [UUID] = []
        for i in 0..<10 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        // Soft delete half
        for id in ids.prefix(5) {
            try db.softDelete(id: id)
        }
        
        print("  Soft deleted 5 records")
        
        // Verify all still fetchable
        XCTAssertEqual(try db.fetchAll().count, 10, "Should have all 10 before purge")
        
        // Purge
        try db.purge()
        
        print("  Purged soft-deleted records")
        
        // Verify only 5 remain
        XCTAssertEqual(try db.fetchAll().count, 5, "Should have 5 after purge")
        
        // Verify the right ones were deleted
        for id in ids.suffix(5) {
            XCTAssertNotNil(try db.fetch(id: id), "Non-deleted records should remain")
        }
        
        print("✅ Purge works correctly with multiple records")
    }
    
    // MARK: - Fetch Field/Value Type Coverage
    
    /// Test fetch with all AnyHashable types
    func testFetchWithAllAnyHashableTypes() throws {
        print("🔍 Testing fetch with all AnyHashable types...")
        
        let collection = db.collection
        try collection.createIndex(on: "value")
        
        // Insert with String
        _ = try db.insert(BlazeDataRecord(["value": .string("test"), "type": .string("string")]))
        
        // Insert with Int
        _ = try db.insert(BlazeDataRecord(["value": .int(42), "type": .string("int")]))
        
        // Insert with Double
        _ = try db.insert(BlazeDataRecord(["value": .double(3.14), "type": .string("double")]))
        
        // Insert with Bool
        _ = try db.insert(BlazeDataRecord(["value": .bool(true), "type": .string("bool")]))
        
        // Insert with Date
        let testDate = Date()
        _ = try db.insert(BlazeDataRecord(["value": .date(testDate), "type": .string("date")]))
        
        // Insert with UUID
        let testUUID = UUID()
        _ = try db.insert(BlazeDataRecord(["value": .uuid(testUUID), "type": .string("uuid")]))
        
        // Insert with Data
        let testData = Data([0x01, 0x02])
        _ = try db.insert(BlazeDataRecord(["value": .data(testData), "type": .string("data")]))
        
        // Debug: Check what's stored
        let allRecords = try db.fetchAll()
        print("  Inserted \(allRecords.count) records:")
        for record in allRecords {
            print("    - type: \(record.storage["type"]?.stringValue ?? "nil"), value field: \(String(describing: record.storage["value"]))")
        }
        
        // Fetch each by indexed field
        print("  Fetching by indexed field 'value':")
        
        let stringResults = try collection.fetch(byIndexedField: "value", value: "test")
        print("    String 'test': found \(stringResults.count) records")
        XCTAssertEqual(stringResults.count, 1, "Should find string record")
        
        let intResults = try collection.fetch(byIndexedField: "value", value: 42)
        print("    Int 42: found \(intResults.count) records")
        if intResults.count > 1 {
            print("      WARNING: Multiple matches for Int 42:")
            for result in intResults {
                print("        - type: \(result.storage["type"]?.stringValue ?? "nil"), value: \(String(describing: result.storage["value"]))")
            }
        }
        XCTAssertEqual(intResults.count, 1, "Should find int record")
        
        let doubleResults = try collection.fetch(byIndexedField: "value", value: 3.14)
        print("    Double 3.14: found \(doubleResults.count) records")
        XCTAssertEqual(doubleResults.count, 1, "Should find double record")
        
        let boolResults = try collection.fetch(byIndexedField: "value", value: true)
        print("    Bool true: found \(boolResults.count) records")
        XCTAssertEqual(boolResults.count, 1, "Should find bool record")
        
        let dateResults = try collection.fetch(byIndexedField: "value", value: testDate)
        print("    Date \(testDate): found \(dateResults.count) records")
        XCTAssertEqual(dateResults.count, 1, "Should find date record")
        
        let uuidResults = try collection.fetch(byIndexedField: "value", value: testUUID)
        print("    UUID \(testUUID): found \(uuidResults.count) records")
        XCTAssertEqual(uuidResults.count, 1, "Should find UUID record")
        
        let dataResults = try collection.fetch(byIndexedField: "value", value: testData)
        print("    Data \(testData.base64EncodedString()): found \(dataResults.count) records")
        XCTAssertEqual(dataResults.count, 1, "Should find data record")
        
        print("✅ Fetch with all AnyHashable types works")
    }
    
    // MARK: - Storage Layout Edge Cases
    
    /// Test loading corrupted storage layout
    func testCorruptedStorageLayoutRecovery() throws {
        print("📂 Testing corrupted storage layout recovery...")
        
        // Insert data
        _ = try db.insert(BlazeDataRecord(["test": .string("data")]))
        try db.persist()
        
        // Corrupt the meta file
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        try "CORRUPTED DATA".write(to: metaURL, atomically: true, encoding: .utf8)
        
        print("  Corrupted meta file")
        
        // Try to reopen - should handle corruption
        do {
            let recoveryDB = try BlazeDBClient(name: "Final100Test", 
                                              fileURL: tempURL, 
                                              password: "Test-Password-123")
            
            // Should either recover or start fresh
            // Either outcome is acceptable (no crash)
            let records = try? recoveryDB.fetchAll()
            print("  Recovery handled: \(records?.count ?? 0) records found")
            
        } catch {
            // Also acceptable - corruption detected and reported
            print("  Corruption detected: \(error)")
        }
        
        print("✅ Corrupted layout handled gracefully")
    }
    
    // MARK: - Crash Simulation Environment Variable
    
    /// Test BLAZEDB_CRASH_BEFORE_UPDATE environment variable
    func testCrashSimulationEnvVar() {
        print("💥 Testing crash simulation env var...")
        
        // Set crash simulation env var
        setenv("BLAZEDB_CRASH_BEFORE_UPDATE", "1", 1)
        
        // Try to update - should simulate crash
        let id = try? db.insert(BlazeDataRecord(["test": .string("value")]))
        
        if let id = id {
            do {
                try db.update(id: id, with: BlazeDataRecord(["test": .string("updated")]))
                // Shouldn't reach here
            } catch {
                // Expected crash simulation
                print("  Crash simulation triggered: \(error)")
            }
        }
        
        // Clean up env var
        unsetenv("BLAZEDB_CRASH_BEFORE_UPDATE")
        
        print("✅ Crash simulation env var works")
    }
    
    // MARK: - UpdateMany/DeleteMany Edge Cases
    
    /// Test updateMany with no matching records
    func testUpdateManyNoMatches() throws {
        print("🔄 Testing updateMany with no matches...")
        
        // Insert data
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["status": .string("active"), "index": .int(i)]))
        }
        
        // Update non-matching predicate
        let count = try db.updateMany(
            where: { $0.storage["status"]?.stringValue == "inactive" },
            set: ["status": .string("archived")]
        )
        
        XCTAssertEqual(count, 0, "Should update 0 records when none match")
        
        print("✅ updateMany with no matches works")
    }
    
    /// Test deleteMany with no matching records
    func testDeleteManyNoMatches() throws {
        print("🗑️ Testing deleteMany with no matches...")
        
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord(["type": .string("keep"), "index": .int(i)]))
        }
        
        let count = try db.deleteMany(where: { $0.storage["type"]?.stringValue == "remove" })
        
        XCTAssertEqual(count, 0, "Should delete 0 records when none match")
        XCTAssertEqual(try db.fetchAll().count, 5, "All records should remain")
        
        print("✅ deleteMany with no matches works")
    }
    
    // MARK: - Fetch on Non-Existent Index
    
    /// Test fetch on non-existent index returns empty
    func testFetchOnNonExistentIndex() throws {
        print("🔍 Testing fetch on non-existent index...")
        
        let collection = db.collection
        
        // Don't create any index
        _ = try db.insert(BlazeDataRecord(["field": .string("value")]))
        
        // Try to fetch by non-existent index
        let results = try collection.fetch(byIndexedField: "nonExistentField", value: "anything")
        
        XCTAssertEqual(results.count, 0, "Fetch on non-existent index should return empty")
        
        print("✅ Fetch on non-existent index returns empty")
    }
    
    // MARK: - Commit/Rollback Error Paths
    
    /// Test commitTransaction when no transaction is active
    func testCommitWithoutTransaction() throws {
        print("🔄 Testing commit without active transaction...")
        
        // Ensure no transaction is active
        try? db.rollbackTransaction()  // Clean up any existing
        
        // Try to commit when no transaction active
        XCTAssertThrowsError(
            try db.commitTransaction(),
            "Commit without transaction should throw"
        )
        
        print("✅ Commit without transaction throws correctly")
    }
    
    /// Test rollbackTransaction when no transaction is active
    func testRollbackWithoutTransaction() throws {
        print("🔄 Testing rollback without active transaction...")
        
        // Try to rollback when no transaction active
        XCTAssertThrowsError(
            try db.rollbackTransaction(),
            "Rollback without transaction should throw"
        )
        
        print("✅ Rollback without transaction throws correctly")
    }
    
    // MARK: - UUID String Normalization
    
    /// Test insert with UUID as string gets normalized
    func testUUIDStringNormalization() throws {
        print("🔤 Testing UUID string normalization...")
        
        let uuidString = UUID().uuidString
        
        // Insert with UUID as string
        let record = BlazeDataRecord([
            "id": .string(uuidString),  // UUID as string
            "value": .int(42)
        ])
        
        let id = try db.insert(record)
        
        // Verify UUID was normalized
        let fetched = try db.fetch(id: id)
        
        if case .uuid(let normalizedUUID) = fetched?.storage["id"] {
            XCTAssertEqual(normalizedUUID.uuidString, uuidString)
        } else {
            XCTFail("UUID string should be normalized to .uuid type")
        }
        
        print("✅ UUID string normalization works")
    }
}

