//
//  EventTriggersTests.swift
//  BlazeDBTests
//
//  Tests for event triggers
//
//  Created by Auto on 1/XX/25.
//

import XCTest
@testable import BlazeDB

final class EventTriggersTests: XCTestCase {
    var db: BlazeDBClient!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try! BlazeDBClient(name: "TestDB", fileURL: dbURL, password: "EventTriggersTest123!")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testOnInsertTrigger() throws {
        var triggerFired = false
        
        db.onInsert { record, modified, ctx in
            triggerFired = true
            modified?.storage["triggered"] = .string("yes")
        }
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        XCTAssertTrue(triggerFired, "Trigger should fire on insert")
        
        let fetched = try db.fetch(id: id)
        XCTAssertEqual(fetched?.storage["triggered"]?.stringValue, "yes", "Trigger should modify record")
    }
    
    func testOnUpdateTrigger() throws {
        var triggerFired = false
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "status": .string("old")
        ])
        let id = try db.insert(record)
        
        db.onUpdate { old, new, ctx in
            triggerFired = true
            XCTAssertEqual(old.storage["status"]?.stringValue, "old")
            XCTAssertEqual(new.storage["status"]?.stringValue, "new")
        }
        
        try db.update(id: id, with: BlazeDataRecord(["status": .string("new")]))
        
        XCTAssertTrue(triggerFired, "Trigger should fire on update")
    }
    
    func testOnDeleteTrigger() throws {
        var triggerFired = false
        var deletedId: UUID?
        
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ])
        let id = try db.insert(record)
        
        db.onDelete { record, ctx in
            triggerFired = true
            deletedId = record.storage["id"]?.uuidValue
        }
        
        try db.delete(id: id)
        
        XCTAssertTrue(triggerFired, "Trigger should fire on delete")
        XCTAssertEqual(deletedId, id, "Trigger should receive deleted record")
    }
    
    func testTriggerContext() throws {
        var contextReceived = false
        
        db.onInsert { record, modified, ctx in
            contextReceived = true
            // Context provides database operations
            XCTAssertNotNil(ctx)
        }
        
        _ = try db.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "name": .string("Test")
        ]))
        
        XCTAssertTrue(contextReceived, "Trigger should receive context")
    }
}

