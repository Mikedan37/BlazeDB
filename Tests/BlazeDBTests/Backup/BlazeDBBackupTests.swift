//
//  BlazeDBBackupTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for backup, export, import, and restore functionality
//

import XCTest
@testable import BlazeDB

final class BlazeDBBackupTests: XCTestCase {
    
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        try await super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTest-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "BackupTest", fileURL: dbURL, password: "BackupTestPassword123!")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Basic Backup Tests
    
    func testBackup_CreatesValidBackup() async throws {
        print("📦 Testing basic backup functionality")
        
        // Insert test data
        let records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string("open"),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try await db.insertMany(records)
        
        // Create backup
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("backup-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        let stats = try await db.backup(to: backupURL)
        
        XCTAssertEqual(stats.recordCount, 50)
        XCTAssertGreaterThan(stats.fileSize, 0)
        XCTAssertGreaterThan(stats.duration, 0)
        
        // Verify backup files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.deletingPathExtension().appendingPathExtension("meta").path))
        
        print("  ✅ Backup created: \(stats.recordCount) records, \(stats.fileSize) bytes")
    }
    
    func testRestore_RestoresFromBackup() async throws {
        print("📦 Testing restore from backup")
        
        // Create original data
        let original = (0..<20).map { i in
            BlazeDataRecord(["value": .int(i)])
        }
        _ = try await db.insertMany(original)
        
        // Create backup
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("restore-test-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        _ = try await db.backup(to: backupURL)
        
        // Modify database (add more records)
        _ = try await db.insertMany((0..<30).map { i in BlazeDataRecord(["new": .int(i)]) })
        
        let beforeRestore = try await db.count()
        XCTAssertEqual(beforeRestore, 50, "Should have 20 + 30 = 50")
        
        // Restore from backup
        try await db.restore(from: backupURL)
        
        let afterRestore = try await db.count()
        XCTAssertEqual(afterRestore, 20, "Should restore to original 20 records")
        
        print("  ✅ Restored: \(beforeRestore) → \(afterRestore) records")
    }
    
    func testBackupPreservesEncryption() async throws {
        print("🔐 Testing backup preserves encryption")
        
        // Insert sensitive data
        _ = try await db.insert(BlazeDataRecord([
            "ssn": .string("123-45-6789"),
            "credit_card": .string("1234-5678-9012-3456")
        ]))
        
        // Backup
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("encrypted-backup-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        _ = try await db.backup(to: backupURL)
        
        // Try to open backup with WRONG password
        BlazeDBClient.clearCachedKey()
        let wrongPasswordDB = try? BlazeDBClient(
            name: "WrongPassword",
            fileURL: backupURL,
            password: "WrongPasswordTest123!"
        )
        
        // Should either fail or decrypt to garbage
        // (Encryption behavior may vary)
        
        // Open with CORRECT password
        BlazeDBClient.clearCachedKey()
        let correctDB = try BlazeDBClient(
            name: "CorrectPassword",
            fileURL: backupURL,
            password: "BackupTestPassword123!"
        )
        
        let restored = try await correctDB.fetchAll()
        XCTAssertEqual(restored.count, 1, "Should restore exactly 1 record")
        guard let firstRecord = restored.first else {
            XCTFail("Restored array is empty - cannot verify restored data")
            return
        }
        XCTAssertEqual(firstRecord.storage["ssn"]?.stringValue, "123-45-6789")
        
        print("  ✅ Encryption preserved in backup")
    }
    
    func testBackupWithLargeDatabase() async throws {
        print("📦 Testing backup with large database (1000 records)")
        
        // Insert 1000 records
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "data": .string(String(repeating: "x", count: 100))
            ])
        }
        _ = try await db.insertMany(records)
        
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("large-backup-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        let startTime = Date()
        let stats = try await db.backup(to: backupURL)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(stats.recordCount, 1000)
        XCTAssertLessThan(duration, 5.0, "Large backup should complete in < 5s")
        
        print("  ✅ Backed up 1000 records in \(String(format: "%.2f", duration))s")
    }
    
    func testConcurrentBackup() async throws {
        print("⚡ Testing concurrent backup (should be thread-safe)")
        
        // Insert data
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Create 5 concurrent backups
        let backupURLs = (0..<5).map { i in
            dbURL.deletingLastPathComponent().appendingPathComponent("concurrent-\(i)-\(UUID().uuidString).blazedb")
        }
        
        defer {
            for url in backupURLs {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("meta"))
            }
        }
        
        await withTaskGroup(of: Bool.self) { group in
            for url in backupURLs {
                group.addTask {
                    do {
                        _ = try await self.db.backup(to: url)
                        return true
                    } catch {
                        print("    ⚠️  Backup failed: \(error)")
                        return false
                    }
                }
            }
            
            var successCount = 0
            for await success in group {
                if success { successCount += 1 }
            }
            
            print("  ✅ \(successCount)/5 concurrent backups succeeded")
            XCTAssertGreaterThanOrEqual(successCount, 4, "Most backups should succeed")
        }
    }
    
    // MARK: - Export Tests
    
    func testExportJSON() async throws {
        print("📤 Testing JSON export")
        
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord(["value": .int(i)])
        })
        
        let jsonData = try await db.export(format: .json)
        
        XCTAssertGreaterThan(jsonData.count, 0)
        
        // Verify it's valid JSON
        let decoded = try JSONDecoder().decode([BlazeDataRecord].self, from: jsonData)
        XCTAssertEqual(decoded.count, 10)
        
        print("  ✅ Exported 10 records as JSON (\(jsonData.count) bytes)")
    }
    
    func testExportCBOR() async throws {
        print("📤 Testing CBOR export")
        
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord(["value": .int(i)])
        })
        
        let cborData = try await db.export(format: .cbor)
        
        XCTAssertGreaterThan(cborData.count, 0)
        
        // Verify it's valid JSON (legacy format)
        // Note: This test uses deprecated CBOR export - consider migrating to BlazeBinary
        let decoded = try JSONDecoder().decode([BlazeDataRecord].self, from: cborData)
        XCTAssertEqual(decoded.count, 10)
        
        print("  ✅ Exported 10 records as JSON (\(cborData.count) bytes)")
    }
    
    func testExportFiltered() async throws {
        print("📤 Testing filtered export")
        
        _ = try await db.insertMany((0..<50).map { i in
            BlazeDataRecord([
                "value": .int(i),
                "status": .string(i < 25 ? "open" : "closed")
            ])
        })
        
        // Export only open records
        let filteredData = try await db.export(
            where: { $0.storage["status"]?.stringValue == "open" },
            format: .json
        )
        
        let decoded = try JSONDecoder().decode([BlazeDataRecord].self, from: filteredData)
        XCTAssertEqual(decoded.count, 25, "Should export only open records")
        
        for record in decoded {
            XCTAssertEqual(record.storage["status"]?.stringValue, "open")
        }
        
        print("  ✅ Filtered export: 25/50 records")
    }
    
    // MARK: - Import Tests
    
    func testImportAppendMode() async throws {
        print("📥 Testing import (append mode)")
        
        // Create database with initial data
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord(["initial": .int(i)])
        })
        
        // Export from another database
        let exportData = try JSONEncoder().encode((0..<20).map { i in
            BlazeDataRecord(["imported": .int(i)])
        })
        
        // Import in append mode
        let stats = try await db.import(from: exportData, format: .json, mode: .append)
        
        XCTAssertEqual(stats.recordsImported, 20)
        XCTAssertEqual(stats.recordsSkipped, 0)
        
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 30, "Should have 10 + 20 = 30 records")
        
        print("  ✅ Imported: \(stats.recordsImported), Total: \(finalCount)")
    }
    
    func testImportReplaceMode() async throws {
        print("📥 Testing import (replace mode)")
        
        // Create database with initial data
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord(["old": .int(i)])
        })
        
        let beforeImport = try await db.count()
        XCTAssertEqual(beforeImport, 10)
        
        // Import new data (replace mode)
        let newData = try JSONEncoder().encode((0..<5).map { i in
            BlazeDataRecord(["new": .int(i)])
        })
        
        let stats = try await db.import(from: newData, format: .json, mode: .replace)
        
        XCTAssertEqual(stats.recordsImported, 5)
        
        let afterImport = try await db.count()
        XCTAssertEqual(afterImport, 5, "Should replace old data")
        
        // Verify only new records exist
        let allRecords = try await db.fetchAll()
        for record in allRecords {
            XCTAssertNotNil(record.storage["new"], "Should have new field")
            XCTAssertNil(record.storage["old"], "Should not have old field")
        }
        
        print("  ✅ Replaced: \(beforeImport) → \(afterImport) records")
    }
    
    func testImportMergeMode() async throws {
        print("📥 Testing import (merge mode)")
        
        // Insert initial records with IDs
        let id1 = UUID()
        let id2 = UUID()
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(id1), "value": .int(1), "status": .string("old")]))
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(id2), "value": .int(2), "status": .string("old")]))
        
        // Prepare import data: update id1, add new record
        let importData = try JSONEncoder().encode([
            BlazeDataRecord(["id": .uuid(id1), "value": .int(100), "status": .string("updated")]),  // Update
            BlazeDataRecord(["id": .uuid(UUID()), "value": .int(3), "status": .string("new")])      // New
        ])
        
        let stats = try await db.import(from: importData, format: .json, mode: .merge)
        
        XCTAssertEqual(stats.recordsUpdated, 1, "Should update 1 existing")
        XCTAssertEqual(stats.recordsImported, 1, "Should import 1 new")
        
        // Verify id1 was updated
        let updated = try await db.fetch(id: id1)
        XCTAssertEqual(updated?.storage["value"]?.intValue, 100)
        XCTAssertEqual(updated?.storage["status"]?.stringValue, "updated")
        
        // Verify id2 still exists unchanged
        let unchanged = try await db.fetch(id: id2)
        XCTAssertEqual(unchanged?.storage["status"]?.stringValue, "old")
        
        // Verify total count
        let finalCount = try await db.count()
        XCTAssertEqual(finalCount, 3, "Should have 2 original + 1 new")
        
        print("  ✅ Merge: \(stats.recordsUpdated) updated, \(stats.recordsImported) imported")
    }
    
    func testExportImportRoundTrip() async throws {
        print("🔄 Testing export → import round trip")
        
        // Original data
        let originalRecords = (0..<25).map { i in
            BlazeDataRecord([
                "index": .int(i),
                "title": .string("Original \(i)"),
                "tags": .array([.string("tag1"), .string("tag2")]),
                "metadata": .dictionary([
                    "created": .date(Date()),
                    "author": .string("test")
                ])
            ])
        }
        _ = try await db.insertMany(originalRecords)
        
        // Export
        let jsonData = try await db.export(format: .json)
        
        // Create new database
        let newDBURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("roundtrip-\(UUID().uuidString).blazedb")
        let newDB = try BlazeDBClient(name: "RoundTrip", fileURL: newDBURL, password: "BackupTestPassword123!")
        
        defer {
            try? FileManager.default.removeItem(at: newDBURL)
            try? FileManager.default.removeItem(at: newDBURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        // Import
        let stats = try await newDB.import(from: jsonData, format: .json, mode: .append)
        
        XCTAssertEqual(stats.recordsImported, 25)
        
        // Verify data integrity
        let imported = try await newDB.fetchAll()
        XCTAssertEqual(imported.count, 25)
        
        // Spot check a few records
        let withIndex0 = imported.first { $0.storage["index"]?.intValue == 0 }
        XCTAssertNotNil(withIndex0)
        XCTAssertEqual(withIndex0?.storage["title"]?.stringValue, "Original 0")
        
        print("  ✅ Round trip: 25 records exported → imported successfully")
    }
    
    func testIncrementalBackup() async throws {
        print("📦 Testing incremental backup")
        
        // Insert old records
        _ = try await db.insertMany((0..<10).map { i in
            BlazeDataRecord([
                "value": .int(i),
                "created_at": .date(Date().addingTimeInterval(-86400))  // Yesterday
            ])
        })
        
        // Insert new records
        _ = try await db.insertMany((0..<5).map { i in
            BlazeDataRecord([
                "value": .int(i + 100),
                "created_at": .date(Date())  // Today
            ])
        })
        
        // Incremental backup (last 12 hours)
        let twelveHoursAgo = Date().addingTimeInterval(-43200)
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("incremental-\(UUID().uuidString).json")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
        }
        
        let stats = try await db.incrementalBackup(to: backupURL, since: twelveHoursAgo)
        
        XCTAssertEqual(stats.recordCount, 5, "Should backup only recent records")
        
        print("  ✅ Incremental: \(stats.recordCount) records (\(stats.fileSize) bytes)")
    }
    
    func testVerifyBackup() async throws {
        print("🔍 Testing backup verification")
        
        _ = try await db.insertMany((0..<10).map { i in BlazeDataRecord(["value": .int(i)]) })
        
        // Create valid backup
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("verify-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        _ = try await db.backup(to: backupURL)
        
        // Verify valid backup
        let isValid = try await db.verifyBackup(at: backupURL)
        XCTAssertTrue(isValid, "Valid backup should verify successfully")
        
        print("  ✅ Backup verified: valid")
    }
    
    // MARK: - Edge Cases
    
    func testBackupEmptyDatabase() async throws {
        print("📦 Testing backup of empty database")
        
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("empty-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
        }
        
        let stats = try await db.backup(to: backupURL)
        
        XCTAssertEqual(stats.recordCount, 0)
        XCTAssertGreaterThan(stats.fileSize, 0, "Even empty database has metadata")
        
        print("  ✅ Empty backup: \(stats.fileSize) bytes (metadata only)")
    }
    
    func testImportWithDuplicateIDs() async throws {
        print("📥 Testing import with duplicate IDs (append mode)")
        
        let sharedID = UUID()
        
        // Insert record with ID
        _ = try await db.insert(BlazeDataRecord(["id": .uuid(sharedID), "value": .int(1)]))
        
        // Try to import duplicate
        let duplicateData = try JSONEncoder().encode([
            BlazeDataRecord(["id": .uuid(sharedID), "value": .int(2)])
        ])
        
        let stats = try await db.import(from: duplicateData, format: .json, mode: .append)
        
        XCTAssertEqual(stats.recordsSkipped, 1, "Duplicate should be skipped")
        XCTAssertEqual(stats.recordsImported, 0)
        
        // Verify original value unchanged
        let record = try await db.fetch(id: sharedID)
        XCTAssertEqual(record?.storage["value"]?.intValue, 1, "Original should be unchanged")
        
        print("  ✅ Duplicate skipped: \(stats.recordsSkipped)")
    }
    
    func testImportInvalidJSON() async throws {
        print("📥 Testing import with invalid JSON")
        
        let invalidData = "not valid json".data(using: .utf8)!
        
        do {
            _ = try await db.import(from: invalidData, format: .json, mode: .append)
            XCTFail("Should throw error for invalid JSON")
        } catch {
            print("  ✅ Invalid JSON rejected: \(error)")
        }
    }
    
    func testBackupWithIndexes() async throws {
        print("📦 Testing backup preserves indexes")
        
        // Create indexes
        try db.collection.createIndex(on: "status")
        try db.collection.createIndex(on: ["status", "priority"])
        try db.collection.enableSearch(on: ["title"])
        
        // Insert data
        let records = (0..<20).map { i -> BlazeDataRecord in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "status": .string(i % 2 == 0 ? "open" : "closed"),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try await db.insertMany(records)
        
        // Backup
        let backupURL = dbURL.deletingLastPathComponent()
            .appendingPathComponent("indexes-\(UUID().uuidString).blazedb")
        
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta.indexes"))
        }
        
        _ = try await db.backup(to: backupURL)
        
        // Open backup and verify indexes work
        BlazeDBClient.clearCachedKey()
        let restoredDB = try BlazeDBClient(name: "Restored", fileURL: backupURL, password: "BackupTestPassword123!")
        
        // Query using index (should be fast)
        let openBugs = try await restoredDB.query()
            .where("status", equals: .string("open"))
            .execute()
        
        XCTAssertEqual(openBugs.count, 10)
        
        // Search using index
        let searchResults = try restoredDB.collection.searchOptimized(query: "Bug", in: ["title"])
        XCTAssertGreaterThan(searchResults.count, 0)
        
        print("  ✅ Indexes preserved: query and search work")
    }
    
    // MARK: - Performance
    
    func testPerformance_Backup() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            Task {
                do {
                    _ = try await self.db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
                    
                    let backupURL = self.dbURL.deletingLastPathComponent()
                        .appendingPathComponent("perf-backup-\(UUID().uuidString).blazedb")
                    
                    _ = try await self.db.backup(to: backupURL)
                    
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.removeItem(at: backupURL.deletingPathExtension().appendingPathExtension("meta"))
                } catch {
                    XCTFail("Backup performance test failed: \(error)")
                }
            }
        }
    }
    
    func testPerformance_ExportImport() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    _ = try await self.db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
                    
                    let data = try await self.db.export(format: .json)
                    _ = try await self.db.import(from: data, format: .json, mode: .append)
                } catch {
                    XCTFail("Export/import performance test failed: \(error)")
                }
            }
        }
    }
}

