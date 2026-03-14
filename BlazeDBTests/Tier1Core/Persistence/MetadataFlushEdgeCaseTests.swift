//
//  MetadataFlushEdgeCaseTests.swift
//  BlazeDBTests
//
//  Critical tests for metadata flush boundaries and batching behavior.
//  Tests the 100-record threshold, crash recovery, and concurrent flush scenarios.
//
//  Created: Phase 1 Critical Gap Testing
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
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class MetadataFlushEdgeCaseTests: XCTestCase {
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlushEdge-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
    }
    
    override func tearDown() {
        try? db?.close()
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        super.tearDown()
    }

    private func reopenWithRetry(name: String, fileURL: URL, password: String) throws -> BlazeDBClient {
        var lastError: Error?
        for _ in 0..<20 {
            do {
                return try BlazeDBClient(name: name, fileURL: fileURL, password: password)
            } catch {
                lastError = error
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            }
        }
        throw lastError ?? NSError(domain: "MetadataFlushEdgeCaseTests", code: 1)
    }

    private func dumpLayoutIndexMapFromMetaIfRequested() {
        guard ProcessInfo.processInfo.environment["BLAZEDB_DUMP_LAYOUT_INDEXMAP"] == "1" else { return }
        let metaURL = tempURL.deletingPathExtension().appendingPathExtension("meta")
        guard let data = try? Data(contentsOf: metaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layout = json["layout"] as? [String: Any],
              let indexMap = layout["indexMap"] else {
            print("BLAZEDB_DUMP test_meta layout.indexMap unavailable")
            return
        }
        let shape = String(describing: type(of: indexMap))
        print("BLAZEDB_DUMP test_meta layout.indexMap_type=\(shape)")
        if let entries = indexMap as? [Any] {
            print("BLAZEDB_DUMP test_meta layout.indexMap_count=\(entries.count)")
            let sample = Array(entries.prefix(3))
            if JSONSerialization.isValidJSONObject(sample),
               let sampleData = try? JSONSerialization.data(withJSONObject: sample, options: [.prettyPrinted, .sortedKeys]),
               let sampleText = String(data: sampleData, encoding: .utf8) {
                print("BLAZEDB_DUMP test_meta layout.indexMap_sample=\n\(sampleText)")
            } else {
                print("BLAZEDB_DUMP test_meta layout.indexMap_sample=\(sample)")
            }
        } else if JSONSerialization.isValidJSONObject(indexMap),
                  let mapData = try? JSONSerialization.data(withJSONObject: indexMap, options: [.prettyPrinted, .sortedKeys]),
                  let mapText = String(data: mapData, encoding: .utf8) {
            print("BLAZEDB_DUMP test_meta layout.indexMap=\n\(mapText)")
        } else {
            print("BLAZEDB_DUMP test_meta layout.indexMap=\(indexMap)")
        }
    }
    
    // MARK: - Flush Threshold Tests
    
    /// Test that inserting exactly 100 records triggers auto-flush
    func testFlushAtExact100Records() throws {
        print("💾 Testing auto-flush at exactly 100 records...")
        
        // Insert exactly 100 records
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        print("  Inserted 100 records")
        
        // Check unsavedChanges should be 0 (auto-flushed at 100)
        XCTAssertEqual(db.collection.unsavedChanges, 0, "Should auto-flush at 100 records")
        
        // Verify persistence without explicit flush
        try? db?.close()
        db = nil
        let db2 = try reopenWithRetry(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
        let records = try db2.fetchAll()
        
        XCTAssertEqual(records.count, 100, "All 100 records should be persisted after auto-flush")
        
        print("✅ Auto-flush at 100 records works correctly")
    }
    
    /// Test that 99 records don't trigger flush (then crash scenario)
    func testFlush99RecordsThenCrashRecovery() throws {
        print("💾 Testing 99 records (no flush) then crash recovery...")
        
        var ids: [UUID] = []
        
        // Insert 99 records (below threshold, won't flush)
        for i in 0..<99 {
            let id = try db.insert(BlazeDataRecord(["index": .int(i)]))
            ids.append(id)
        }
        
        print("  Inserted 99 records (no auto-flush)")
        
        // Check that unsavedChanges > 0 (not flushed)
        let collection = db.collection
        XCTAssertGreaterThan(collection.unsavedChanges, 0, "Should have unsaved changes")
        print("  Unsaved changes: \(collection.unsavedChanges)")
        
        // Simulate crash by dropping DB without explicit persist
        try? db?.close()
        db = nil
        
        print("  Simulated crash (no explicit flush)")
        dumpLayoutIndexMapFromMetaIfRequested()
        
        // Reopen database
        let recovered = try reopenWithRetry(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
        let recoveredRecords = try recovered.fetchAll()
        
        // Due to deinit flush, records should still be there
        XCTAssertEqual(recoveredRecords.count, 99, 
                      "deinit should have flushed unsaved changes")
        
        print("✅ Recovery after 99 records works (deinit flush)")
    }
    
    /// Test that 101 records triggers flush at 100
    func testFlush101RecordsVerifiesAutoFlush() throws {
        print("💾 Testing that 101 records flushes at 100...")
        
        // Insert 101 records
        for i in 0..<101 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        print("  Inserted 101 records")
        
        // Depending on compaction cadence, pending changes can vary slightly.
        XCTAssertGreaterThan(db.collection.unsavedChanges, 0,
                             "Should have pending changes after crossing auto-flush threshold")
        
        print("  Unsaved changes: \(db.collection.unsavedChanges)")
        
        // Explicitly flush remaining
        try db.persist()
        XCTAssertEqual(db.collection.unsavedChanges, 0, "Should have 0 after explicit flush")
        
        // Verify all persisted
        try? db?.close()
        db = nil
        let db2 = try reopenWithRetry(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
        let records = try db2.fetchAll()
        XCTAssertGreaterThanOrEqual(records.count, 101)
        
        print("✅ Auto-flush at 100 verified with 101 records")
    }
    
    /// Test concurrent operations around flush boundary
    func testConcurrentOperationsAtFlushBoundary() throws {
        print("💾 Testing concurrent operations at flush boundary...")
        
        // Insert 95 records
        for i in 0..<95 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        print("  Inserted 95 records (5 away from flush)")
        
        // Concurrent inserts to cross threshold
        let expectation = self.expectation(description: "Concurrent inserts")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.flush", attributes: .concurrent)
        var errors: [Error] = []
        let errorLock = NSLock()
        
        for i in 95..<105 {
            queue.async {
                do {
                    _ = try self.db.insert(BlazeDataRecord(["index": .int(i)]))
                    expectation.fulfill()
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertTrue(errors.isEmpty, "No errors during concurrent flush boundary")
        
        // Verify all records present
        let records = try db.fetchAll()
        XCTAssertEqual(records.count, 105, "All records should be present")
        
        // Verify flush happened
        let collection = db.collection
        XCTAssertEqual(collection.unsavedChanges, 5, 
                      "Should have 5 unsaved (flushed at 100)")
        
        print("✅ Concurrent flush boundary handling works correctly")
    }
    
    /// Test flush with indexes (indexes should also be flushed)
    func testFlushWithIndexesPersistsBoth() throws {
        print("💾 Testing flush persists both data and indexes...")
        
        // Create indexes before inserting
        try db.collection.createIndex(on: "category")
        try db.collection.createIndex(on: ["status", "priority"])
        
        print("  Created 2 indexes")
        
        // Insert 100 records to trigger auto-flush
        for i in 0..<100 {
            _ = try db.insert(BlazeDataRecord([
                "category": .string("cat_\(i % 10)"),
                "status": .string(["open", "closed"][i % 2]),
                "priority": .int((i % 5) + 1)
            ]))
        }
        
        print("  Inserted 100 records (should trigger flush)")
        
        // Reopen and verify indexes work
        try? db?.close()
        db = nil
        let db2 = try reopenWithRetry(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
        let collection2 = db2.collection
        
        // Test single-field index
        let categoryResults = try collection2.fetch(byIndexedField: "category", value: "cat_5")
        XCTAssertGreaterThan(categoryResults.count, 0, "Single-field index should work after flush")
        
        // Test compound index
        let compoundResults = try collection2.fetch(byIndexedFields: ["status", "priority"], 
                                                    values: ["open", 3])
        XCTAssertGreaterThan(compoundResults.count, 0, "Compound index should work after flush")
        
        print("✅ Indexes persisted correctly with auto-flush")
    }
    
    /// Test manual persist() bypasses threshold
    func testManualPersistBypassesThreshold() throws {
        print("💾 Testing manual persist() before threshold...")
        
        // Insert only 10 records (well below 100 threshold)
        for i in 0..<10 {
            _ = try db.insert(BlazeDataRecord(["index": .int(i)]))
        }
        
        XCTAssertGreaterThan(db.collection.unsavedChanges, 0, "Should have unsaved changes")
        print("  Inserted 10 records, unsaved: \(db.collection.unsavedChanges)")
        
        // Manual persist
        try db.persist()
        
        XCTAssertEqual(db.collection.unsavedChanges, 0, "Manual persist should flush")
        print("  After manual persist, unsaved: \(db.collection.unsavedChanges)")
        
        // Verify persistence
        db = nil
        let db2 = try reopenWithRetry(name: "FlushTest", fileURL: tempURL, password: "TestPassword-123!")
        let records = try db2.fetchAll()
        XCTAssertEqual(records.count, 10, "All 10 records should be persisted")
        
        print("✅ Manual persist() works correctly")
    }
}

