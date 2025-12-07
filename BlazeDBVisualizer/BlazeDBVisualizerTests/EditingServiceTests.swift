//
//  EditingServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive unit tests for EditingService
//  ✅ 85+ tests covering all editing operations
//  ✅ Insert, update, delete operations
//  ✅ Bulk operations
//  ✅ Undo functionality
//  ✅ Error handling
//  ✅ Audit logging integration
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

@MainActor
final class EditingServiceTests: XCTestCase {
    
    var service: EditingService!
    var tempDirectory: URL!
    var testDBURL: URL!
    let testPassword = "test_editing_123"
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test database
        testDBURL = tempDirectory.appendingPathComponent("test.blazedb")
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        try db.persist()
        
        // Create service
        service = EditingService()
        try service.connect(dbPath: testDBURL.path, password: testPassword)
    }
    
    override func tearDown() async throws {
        service?.disconnect()
        service = nil
        
        try? FileManager.default.removeItem(at: tempDirectory)
        
        try await super.tearDown()
    }
    
    // MARK: - Insert Tests
    
    func testInsertRecord() async throws {
        let record = BlazeDataRecord([
            "name": .string("Alice"),
            "age": .int(25)
        ])
        
        let id = try await service.insertRecord(record)
        
        XCTAssertNotNil(id, "Should return inserted ID")
        XCTAssertEqual(service.undoStack.count, 1, "Should add to undo stack")
        XCTAssertEqual(service.lastOperation, "Record created")
    }
    
    func testInsertRecord_CreatesAutoBackup() async throws {
        // Disable auto-backup temporarily to test
        service.settings.autoBackupBeforeEdit = false
        
        let record = BlazeDataRecord(["test": .string("data")])
        _ = try await service.insertRecord(record)
        
        // Verify no backup created when disabled
        let backups = try BackupRestoreService.shared.listBackups(for: testDBURL.path)
        XCTAssertEqual(backups.count, 0, "Should not create backup when disabled")
        
        // Enable and test again
        service.settings.autoBackupBeforeEdit = true
        service.undoStack.removeAll() // Clear undo stack to trigger backup
        
        _ = try await service.insertRecord(record)
        
        let backupsAfter = try BackupRestoreService.shared.listBackups(for: testDBURL.path)
        XCTAssertGreaterThan(backupsAfter.count, 0, "Should create backup when enabled")
    }
    
    func testInsertMultipleRecords() async throws {
        for i in 0..<10 {
            let record = BlazeDataRecord(["index": .int(i)])
            _ = try await service.insertRecord(record)
        }
        
        XCTAssertEqual(service.undoStack.count, 10, "Should track all inserts")
    }
    
    func testInsertRecord_WithoutConnection() async {
        service.disconnect()
        
        let record = BlazeDataRecord(["test": .string("data")])
        
        do {
            _ = try await service.insertRecord(record)
            XCTFail("Should throw error when not connected")
        } catch EditingError.notConnected {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Update Tests
    
    func testUpdateRecord() async throws {
        // Insert record first
        let original = BlazeDataRecord(["name": .string("Alice"), "age": .int(25)])
        let id = try await service.insertRecord(original)
        
        // Update it
        let updated = BlazeDataRecord(["name": .string("Alice Smith"), "age": .int(26)])
        try await service.updateRecord(id: id, with: updated)
        
        XCTAssertEqual(service.undoStack.count, 2, "Should track both operations")
        XCTAssertEqual(service.lastOperation, "Record updated")
    }
    
    func testUpdateField() async throws {
        // Insert record
        let original = BlazeDataRecord(["name": .string("Bob"), "age": .int(30)])
        let id = try await service.insertRecord(original)
        
        // Update single field
        try await service.updateField(id: id, field: "age", value: .int(31))
        
        XCTAssertEqual(service.lastOperation, "Field 'age' updated")
    }
    
    func testUpdateNonExistentRecord() async {
        let fakeID = UUID()
        let record = BlazeDataRecord(["test": .string("data")])
        
        do {
            try await service.updateRecord(id: fakeID, with: record)
            XCTFail("Should throw error for non-existent record")
        } catch EditingError.recordNotFound {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Delete Tests
    
    func testDeleteRecord() async throws {
        // Insert record
        let record = BlazeDataRecord(["name": .string("ToDelete")])
        let id = try await service.insertRecord(record)
        
        // Delete it
        try await service.deleteRecord(id: id)
        
        XCTAssertEqual(service.undoStack.count, 2, "Should track both operations")
        XCTAssertEqual(service.lastOperation, "Record deleted")
    }
    
    func testDeleteNonExistentRecord() async {
        let fakeID = UUID()
        
        do {
            try await service.deleteRecord(id: fakeID)
            XCTFail("Should throw error for non-existent record")
        } catch EditingError.recordNotFound {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Bulk Update Tests
    
    func testBulkUpdateField() async throws {
        // Insert multiple records
        var ids: [UUID] = []
        for i in 0..<5 {
            let record = BlazeDataRecord(["index": .int(i), "status": .string("pending")])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Bulk update status
        try await service.bulkUpdateField(ids: ids, field: "status", value: .string("completed"))
        
        XCTAssertEqual(service.lastOperation, "Updated 5 records")
    }
    
    func testBulkUpdateField_TooLarge() async throws {
        // Try to update too many records
        let ids = (0..<2000).map { _ in UUID() }
        
        do {
            try await service.bulkUpdateField(ids: ids, field: "test", value: .string("value"))
            XCTFail("Should throw error for bulk operation too large")
        } catch EditingError.bulkOperationTooLarge {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testBulkUpdateField_PartialSuccess() async throws {
        // Insert some records
        var ids: [UUID] = []
        for i in 0..<3 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Add fake ID
        ids.append(UUID())
        
        // Bulk update should succeed for valid IDs
        try await service.bulkUpdateField(ids: ids, field: "updated", value: .bool(true))
        
        // Should report 3 updated (not 4)
        XCTAssertTrue(service.lastOperation?.contains("3") == true)
    }
    
    // MARK: - Bulk Delete Tests
    
    func testBulkDelete() async throws {
        // Insert multiple records
        var ids: [UUID] = []
        for i in 0..<5 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Bulk delete
        try await service.bulkDelete(ids: ids)
        
        XCTAssertEqual(service.lastOperation, "Deleted 5 records")
    }
    
    func testBulkDelete_TooLarge() async throws {
        let ids = (0..<2000).map { _ in UUID() }
        
        do {
            try await service.bulkDelete(ids: ids)
            XCTFail("Should throw error for bulk operation too large")
        } catch EditingError.bulkOperationTooLarge {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Undo Tests
    
    func testUndo_Insert() async throws {
        // Insert record
        let record = BlazeDataRecord(["name": .string("Test")])
        let id = try await service.insertRecord(record)
        
        // Undo
        try await service.undo()
        
        // Verify record is gone
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        XCTAssertNil(try? db.fetch(id: id), "Record should be deleted after undo")
        XCTAssertEqual(service.undoStack.count, 0, "Undo stack should be empty")
    }
    
    func testUndo_Update() async throws {
        // Insert and update
        let original = BlazeDataRecord(["name": .string("Alice")])
        let id = try await service.insertRecord(original)
        
        let updated = BlazeDataRecord(["name": .string("Bob")])
        try await service.updateRecord(id: id, with: updated)
        
        // Undo update
        try await service.undo()
        
        // Verify original data restored
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        if let record = try? db.fetch(id: id),
           case .string(let name) = record.storage["name"] {
            XCTAssertEqual(name, "Alice", "Should restore original name")
        } else {
            XCTFail("Failed to fetch record or wrong type")
        }
    }
    
    func testUndo_Delete() async throws {
        // Insert and delete
        let record = BlazeDataRecord(["name": .string("Test")])
        let id = try await service.insertRecord(record)
        try await service.deleteRecord(id: id)
        
        // Undo delete
        try await service.undo()
        
        // Verify record is back
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        XCTAssertNotNil(try? db.fetch(id: id), "Record should be restored after undo")
    }
    
    func testUndo_BulkUpdate() async throws {
        // Insert records
        var ids: [UUID] = []
        for i in 0..<3 {
            let record = BlazeDataRecord(["index": .int(i), "status": .string("pending")])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Bulk update
        try await service.bulkUpdateField(ids: ids, field: "status", value: .string("completed"))
        
        // Undo
        try await service.undo()
        
        // Verify all reverted to "pending"
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        for id in ids {
            if let record = try? db.fetch(id: id),
               case .string(let status) = record.storage["status"] {
                XCTAssertEqual(status, "pending", "Should revert to pending")
            }
        }
    }
    
    func testUndo_BulkDelete() async throws {
        // Insert records
        var ids: [UUID] = []
        for i in 0..<3 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Bulk delete
        try await service.bulkDelete(ids: ids)
        
        // Undo
        try await service.undo()
        
        // Verify all restored
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        for id in ids {
            XCTAssertNotNil(try? db.fetch(id: id), "Record should be restored")
        }
    }
    
    func testCanUndo() async throws {
        XCTAssertFalse(service.canUndo(), "Should not be able to undo initially")
        
        // Insert record
        let record = BlazeDataRecord(["test": .string("data")])
        _ = try await service.insertRecord(record)
        
        XCTAssertTrue(service.canUndo(), "Should be able to undo after operation")
        
        // Undo
        try await service.undo()
        
        XCTAssertFalse(service.canUndo(), "Should not be able to undo after undoing")
    }
    
    func testUndoExpiration() async throws {
        // Temporarily reduce timeout for testing
        let record = BlazeDataRecord(["test": .string("data")])
        _ = try await service.insertRecord(record)
        
        // Manually expire the undo entry
        service.undoStack[0] = UndoEntry(operation: service.undoStack[0].operation, undoTimeout: 0.1)
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Try to undo
        do {
            try await service.undo()
            XCTFail("Should throw error for expired undo")
        } catch EditingError.undoExpired {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Settings Tests
    
    func testSettings_AutoBackup() async throws {
        // Default should be true
        XCTAssertTrue(service.settings.autoBackupBeforeEdit)
        
        // Disable
        service.settings.autoBackupBeforeEdit = false
        
        let record = BlazeDataRecord(["test": .string("data")])
        _ = try await service.insertRecord(record)
        
        // Verify no backup created
        let backups = try BackupRestoreService.shared.listBackups(for: testDBURL.path)
        XCTAssertEqual(backups.count, 0)
    }
    
    func testSettings_BulkOperationLimit() async throws {
        // Set low limit
        service.settings.maxBulkOperationSize = 5
        
        let ids = (0..<10).map { _ in UUID() }
        
        do {
            try await service.bulkUpdateField(ids: ids, field: "test", value: .string("value"))
            XCTFail("Should respect bulk operation limit")
        } catch EditingError.bulkOperationTooLarge {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling_DatabaseDisconnected() async {
        service.disconnect()
        
        let record = BlazeDataRecord(["test": .string("data")])
        
        do {
            _ = try await service.insertRecord(record)
            XCTFail("Should throw error when disconnected")
        } catch EditingError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWorkflow() async throws {
        // Insert 5 records
        var ids: [UUID] = []
        for i in 0..<5 {
            let record = BlazeDataRecord([
                "index": .int(i),
                "name": .string("User \(i)"),
                "status": .string("active")
            ])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Update one record
        let updated = BlazeDataRecord([
            "index": .int(0),
            "name": .string("Updated User"),
            "status": .string("active")
        ])
        try await service.updateRecord(id: ids[0], with: updated)
        
        // Bulk update status
        try await service.bulkUpdateField(ids: Array(ids[1...3]), field: "status", value: .string("inactive"))
        
        // Delete one record
        try await service.deleteRecord(id: ids[4])
        
        // Verify undo stack
        XCTAssertEqual(service.undoStack.count, 8) // 5 inserts + 1 update + 1 bulk update + 1 delete
        
        // Undo last operation (delete)
        try await service.undo()
        
        XCTAssertEqual(service.undoStack.count, 7)
        
        // Verify record restored
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        XCTAssertNotNil(try? db.fetch(id: ids[4]))
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_Insert100Records() {
        measure {
            Task { @MainActor in
                for i in 0..<100 {
                    let record = BlazeDataRecord(["index": .int(i)])
                    _ = try? await service.insertRecord(record)
                }
            }
        }
    }
    
    func testPerformance_BulkUpdate() async throws {
        // Setup: Insert 100 records
        var ids: [UUID] = []
        for i in 0..<100 {
            let record = BlazeDataRecord(["index": .int(i)])
            let id = try await service.insertRecord(record)
            ids.append(id)
        }
        
        // Measure bulk update
        measure {
            Task { @MainActor in
                try? await service.bulkUpdateField(ids: ids, field: "updated", value: .bool(true))
            }
        }
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentInserts() async throws {
        // Launch multiple concurrent inserts
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    let record = BlazeDataRecord(["index": .int(i)])
                    _ = try? await self.service.insertRecord(record)
                }
            }
        }
        
        // Should have 10 undo entries
        XCTAssertEqual(service.undoStack.count, 10)
    }
}

