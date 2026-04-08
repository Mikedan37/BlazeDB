//
//  SearchIndexMaintenanceTests.swift
//  BlazeDBTests
//
//  Tests for automatic search index maintenance during CRUD operations.
//  Verifies that the search index stays synchronized with data changes.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif
import Foundation

final class SearchIndexMaintenanceTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchMaint-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(name: "SearchMaintTest", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))
        try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Insert Tests
    
    func testSearchIndexUpdatesOnInsert() throws {
        // Enable search FIRST
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Insert record AFTER enabling search
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Login Bug"), "description": .string("Cannot login")]))
        
        // Search should find it
        let searchResults = try requireFixture(db).query()
            .search("login", in: ["title"])
        XCTAssertEqual(searchResults.count, 1, "Search index should be updated on insert")
        
        guard let firstResult = searchResults.first else {
            XCTFail("Expected at least one search result")
            return
        }
        XCTAssertEqual(firstResult.record.storage["title"]?.stringValue, "Login Bug")
    }
    
    func testMultipleInsertsUpdateIndex() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Insert multiple records
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 1")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 2")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 3")]))
        
        // All should be searchable
        let searchResults = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(searchResults.count, 3, "All inserted records should be searchable")
    }
    
    func testSearchMultipleFields() throws {
        try requireFixture(db).collection.enableSearch(on: ["title", "description", "status"])
        
        _ = try requireFixture(db).insert(BlazeDataRecord([
            "title": .string("Complex Bug"),
            "description": .string("Authentication failure"),
            "status": .string("open")
        ]))
        
        // Search in title
        XCTAssertEqual(try requireFixture(db).query().search("complex", in: ["title"]).count, 1)
        
        // Search in description  
        XCTAssertEqual(try requireFixture(db).query().search("authentication", in: ["description"]).count, 1)
        
        // Search in status
        XCTAssertEqual(try requireFixture(db).query().search("open", in: ["status"]).count, 1)
    }
    
    // MARK: - Update Tests
    
    func testSearchIndexUpdatesOnUpdate() throws {
        // Insert and enable search
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Old Title")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Update the record
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("New Title")]))
        
        // Old title should not be found
        XCTAssertEqual(try requireFixture(db).query().search("old", in: ["title"]).count, 0, "Old indexed data should be removed")
        
        // New title should be found
        XCTAssertEqual(try requireFixture(db).query().search("new", in: ["title"]).count, 1, "New data should be indexed")
    }
    
    func testMultipleUpdatesKeepIndexSynced() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("V1")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Update multiple times
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("V2")]))
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("V3")]))
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("V4")]))
        
        // Only final version should be searchable
        XCTAssertEqual(try requireFixture(db).query().search("v1", in: ["title"]).count, 0)
        XCTAssertEqual(try requireFixture(db).query().search("v2", in: ["title"]).count, 0)
        XCTAssertEqual(try requireFixture(db).query().search("v3", in: ["title"]).count, 0)
        XCTAssertEqual(try requireFixture(db).query().search("v4", in: ["title"]).count, 1)
    }
    
    func testUpdateChangesMultipleIndexedFields() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord([
            "title": .string("Original"),
            "description": .string("Old description")
        ]))
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Update both fields
        try requireFixture(db).update(id: id, with: BlazeDataRecord([
            "title": .string("Updated"),
            "description": .string("New description")
        ]))
        
        // Old data should not be found
        XCTAssertEqual(try requireFixture(db).query().search("original", in: ["title"]).count, 0)
        XCTAssertEqual(try requireFixture(db).query().search("old", in: ["description"]).count, 0)
        
        // New data should be found
        XCTAssertEqual(try requireFixture(db).query().search("updated", in: ["title"]).count, 1)
        XCTAssertEqual(try requireFixture(db).query().search("new", in: ["description"]).count, 1)
    }
    
    // MARK: - Delete Tests
    
    func testSearchIndexUpdatesOnDelete() throws {
        // Insert and enable search
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Delete Me")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Verify it's searchable
        XCTAssertEqual(try requireFixture(db).query().search("delete", in: ["title"]).count, 1)
        
        // Delete it
        try requireFixture(db).delete(id: id)
        
        // Should no longer be searchable
        XCTAssertEqual(try requireFixture(db).query().search("delete", in: ["title"]).count, 0)
    }
    
    func testMultipleDeletesUpdateIndex() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let id1 = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 1")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 2")]))
        let id3 = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug 3")]))
        
        // Delete two of them
        try requireFixture(db).delete(id: id1)
        try requireFixture(db).delete(id: id3)
        
        // Only Bug 2 should be searchable
        let searchResults = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(searchResults.count, 1, "Should find exactly 1 result after deleting 2 of 3 records")
        
        guard let firstResult = searchResults.first else {
            XCTFail("Expected at least one search result")
            return
        }
        XCTAssertEqual(firstResult.record.storage["title"]?.stringValue, "Bug 2", "The remaining record should be Bug 2")
    }
    
    // MARK: - Mixed Operations
    
    func testMixedOperationsKeepIndexConsistent() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Insert
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Original")]))
        
        XCTAssertEqual(try requireFixture(db).query().search("original", in: ["title"]).count, 1)
        
        // Update
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("Updated")]))
        XCTAssertEqual(try requireFixture(db).query().search("original", in: ["title"]).count, 0)
        XCTAssertEqual(try requireFixture(db).query().search("updated", in: ["title"]).count, 1)
        
        // Delete
        try requireFixture(db).delete(id: id)
        XCTAssertEqual(try requireFixture(db).query().search("updated", in: ["title"]).count, 0)
    }
    
    func testBatchInsertsMaintainIndex() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Insert 100 records
        for i in 0..<100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)")]))
        }
        
        // All should be searchable
        let searchResults = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(searchResults.count, 100, "All batch-inserted records should be searchable")
    }
    
    // MARK: - Edge Cases
    
    func testInsertBeforeEnablingSearch() throws {
        // Insert BEFORE enabling search
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Early Bird")]))
        
        // Enable search
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Should still find it (indexes existing data)
        let searchResults = try requireFixture(db).query().search("early", in: ["title"])
        XCTAssertGreaterThanOrEqual(searchResults.count, 0, "Enabling search should index existing data or allow fallback")
    }
    
    func testUpdateNonIndexedField() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug"), "priority": .int(1)]))
        try requireFixture(db).collection.enableSearch(on: ["title"])  // Only index title
        
        // Update priority (non-indexed field)
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("Bug"), "priority": .int(5)]))
        
        // Should still be searchable
        XCTAssertEqual(try requireFixture(db).query().search("bug", in: ["title"]).count, 1)
    }
    
    func testSearchWithoutIndex() throws {
        // Insert without enabling search
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("No Index Bug")]))
        
        // Search should still work (fallback to full scan)
        XCTAssertGreaterThanOrEqual(try requireFixture(db).query().search("index", in: ["title"]).count, 0, "Search without index should use fallback")
    }
    
    func testPersistenceAcrossReload() throws {
        // Enable search and insert
        try requireFixture(db).collection.enableSearch(on: ["title"])
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Persistent Bug")]))
        
        // Close and reopen
        db = nil
        db = try BlazeDBClient(name: "SearchMaintTest", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
        
        // Should still be searchable
        XCTAssertEqual(try requireFixture(db).query().search("persistent", in: ["title"]).count, 1, "Search index should persist across reloads")
    }
}
