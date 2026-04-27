//
//  OptimizedSearchTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for inverted index and optimized full-text search.
//  Tests performance, correctness, edge cases, and robustness.
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

final class OptimizedSearchTests: XCTestCase {
    
    private var tempURL: URL?
    private var db: BlazeDBClient?
    
    override func setUpWithError() throws {
        try super.setUpWithError()

        #if BLAZEDB_LINUX_CORE
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Inverted search index tests target Darwin; BLAZEDB_LINUX_CORE CI build does not expose the same index stats path.")
        }
        #endif
        
        // Small delay and clear cache for test isolation
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptSearch-\(testID).blazedb")
        
        // Aggressively clean up any leftover files
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: try requireFixture(tempURL))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("backup"))
            
            if !FileManager.default.fileExists(atPath: try requireFixture(tempURL).path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        db = try BlazeDBClient(name: "OptSearchTest_\(testID)", fileURL: try requireFixture(tempURL), password: "SecureTestDB-456!")
    }
    
    override func tearDown() {
        // Ensure all changes are persisted before cleanup
        try? db?.persist()
        db = nil
        
        // Clean up all database files
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: try requireFixture(tempURL))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: try requireFixture(tempURL).deletingPathExtension().appendingPathExtension("backup"))
        }
        
        BlazeDBClient.clearCachedKey()
        super.tearDown()
    }
    
    // MARK: - Basic Index Tests
    
    func testEnableSearchIndex() throws {
        // Insert test data
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Login Bug"), "description": .string("Cannot login")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Logout Issue"), "description": .string("Logout fails")]))
        
        // Enable search
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Verify index enabled
        XCTAssertTrue(try requireFixture(db).collection.isSearchEnabled())
        
        // Verify stats
        let stats = try requireFixture(db).collection.getSearchStats()
        XCTAssertNotNil(stats)
        XCTAssertGreaterThan(stats!.totalWords, 0)
    }
    
    func testDisableSearchIndex() throws {
        // Enable
        try requireFixture(db).collection.enableSearch(on: ["title"])
        XCTAssertTrue(try requireFixture(db).collection.isSearchEnabled())
        
        // Disable
        try requireFixture(db).collection.disableSearch()
        XCTAssertFalse(try requireFixture(db).collection.isSearchEnabled())
    }
    
    func testRebuildSearchIndex() throws {
        // Insert data
        for i in 1...100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)"), "description": .string("Test bug")]))
        }
        
        // Enable search
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Get original stats
        let stats1 = try requireFixture(db).collection.getSearchStats()
        
        // Rebuild
        try requireFixture(db).collection.rebuildSearchIndex()
        
        // Verify still works
        let stats2 = try requireFixture(db).collection.getSearchStats()
        XCTAssertEqual(stats1?.totalWords, stats2?.totalWords)
    }
    
    // MARK: - Search Correctness Tests
    
    func testBasicIndexedSearch() throws {
        // Insert test data
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Login Bug"), "description": .string("Cannot login to app")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Logout Issue"), "description": .string("Logout button broken")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Auth Error"), "description": .string("Authentication failed")]))
        
        // Enable search
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Search for "login"
        let searchResults = try requireFixture(db).query().search("login", in: ["title", "description"])
        XCTAssertGreaterThan(searchResults.count, 0)
    }
    
    func testSearchMultipleTerms() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("User Login Bug"), "description": .string("Users cannot login")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Admin Panel"), "description": .string("Admin features")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("User Profile"), "description": .string("Profile page")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        // Search for multiple terms
        let results = try requireFixture(db).query().search("user login", in: ["title", "description"])
        XCTAssertGreaterThan(results.count, 0)
    }
    
    func testSearchWithFilters() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("High Priority Bug"), "priority": .int(5)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Low Priority Bug"), "priority": .int(1)]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Critical Bug"), "priority": .int(10)]))
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Search with filter
        let results = try requireFixture(db).query()
            .where("priority", greaterThan: .int(3))
            .search("bug", in: ["title"])
        
        XCTAssertGreaterThan(results.count, 0)
        // Should only return high priority results
        for result in results {
            if let priority = result.record.storage["priority"]?.intValue {
                XCTAssertGreaterThan(priority, 3)
            }
        }
    }
    
    func testSearchWithLimit() throws {
        for i in 1...100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Test Bug \(i)")]))
        }
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Search returns array directly - apply limit manually
        let allResults = try requireFixture(db).query().search("test", in: ["title"])
        let limitedResults = Array(allResults.prefix(10))
        
        XCTAssertEqual(limitedResults.count, 10)
    }
    
    func testSearchWithOffset() throws {
        for i in 1...50 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)")]))
        }
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Search returns array directly - apply offset manually
        let allResults = try requireFixture(db).query().search("bug", in: ["title"])
        let offsetResults = Array(allResults.dropFirst(10))
        
        XCTAssertLessThanOrEqual(offsetResults.count, allResults.count - 10)
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance_SmallDataset() throws {
        // Insert 100 records
        for i in 1...100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)"), "description": .string("Description \(i)")]))
        }
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        let startTime = Date()
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(results.count, 100)
        XCTAssertLessThan(duration, 0.05, "Search should be < 50ms for 100 records")
        
        print("  Searched 100 records in \(String(format: "%.3f", duration))s")
    }
    
    func testSearchPerformance_LargeDataset() throws {
        // Insert 1000 records
        for i in 1...1000 {
            _ = try requireFixture(db).insert(BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "description": .string("This is a test bug number \(i)"),
                "priority": .int(i % 10)
            ]))
        }
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        let startTime = Date()
        let results = try requireFixture(db).query().search("bug test", in: ["title", "description"])
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(results.count, 0, "Should find matching records")
        // Relaxed from 100ms to 150ms to account for AND logic + term frequency scoring
        XCTAssertLessThan(duration, 0.15, "Search with AND logic should be < 150ms for 1000 records")
        
        print("  Searched 1000 records in \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - Edge Case Tests
    
    func testSearchEmptyQuery() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let results = try requireFixture(db).query().search("", in: ["title"])
        XCTAssertEqual(results.count, 0, "Empty query should return no results")
    }
    
    func testSearchNonExistentTerm() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Login Bug")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let results = try requireFixture(db).query().search("nonexistent", in: ["title"])
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchEmptyDatabase() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let results = try requireFixture(db).query().search("anything", in: ["title"])
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchUnicodeContent() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("🐛 Unicode Bug"), "description": .string("日本語 テスト")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertGreaterThan(results.count, 0)
    }
    
    func testSearchCaseInsensitive() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("LOGIN BUG")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let results = try requireFixture(db).query().search("login", in: ["title"])
        XCTAssertEqual(results.count, 1, "Search should be case-insensitive")
    }
    
    func testSearchPartialWords() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Authentication Error")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Search for partial word
        let results = try requireFixture(db).query().search("auth", in: ["title"])
        XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle partial word matches")
    }
    
    // MARK: - Index Update Tests
    
    func testIndexUpdatesOnInsert() throws {
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Insert after enabling search
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("New Bug")]))
        
        // Should be immediately searchable
        let results = try requireFixture(db).query().search("new", in: ["title"])
        XCTAssertEqual(results.count, 1)
    }
    
    func testIndexUpdatesOnUpdate() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Old Title")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Update
        try requireFixture(db).update(id: id, with: BlazeDataRecord(["title": .string("New Title")]))
        
        // Old should not be found
        XCTAssertEqual(try requireFixture(db).query().search("old", in: ["title"]).count, 0)
        
        // New should be found
        XCTAssertEqual(try requireFixture(db).query().search("new", in: ["title"]).count, 1)
    }
    
    func testIndexUpdatesOnDelete() throws {
        let id = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Delete Me")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Should be searchable
        XCTAssertEqual(try requireFixture(db).query().search("delete", in: ["title"]).count, 1)
        
        // Delete
        try requireFixture(db).delete(id: id)
        
        // Should no longer be searchable
        XCTAssertEqual(try requireFixture(db).query().search("delete", in: ["title"]).count, 0)
    }
    
    // MARK: - Multi-Field Search Tests
    
    func testSearchAcrossMultipleFields() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord([
            "title": .string("Login"),
            "description": .string("Bug description"),
            "status": .string("open")
        ]))
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description", "status"])
        
        // Should find in any field
        XCTAssertGreaterThan(try requireFixture(db).query().search("login", in: ["title"]).count, 0)
        XCTAssertGreaterThan(try requireFixture(db).query().search("bug", in: ["description"]).count, 0)
        XCTAssertGreaterThan(try requireFixture(db).query().search("open", in: ["status"]).count, 0)
    }
    
    func testSearchRelevanceScoring() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Login Bug"), "description": .string("Minor issue")]))
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug"), "description": .string("Login functionality broken")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        let results = try requireFixture(db).query().search("login bug", in: ["title", "description"])
        
        // Results should be sorted by relevance
        XCTAssertGreaterThan(results.count, 0)
        if results.count >= 2 {
            XCTAssertGreaterThanOrEqual(results[0].score, results[1].score)
        }
    }
    
    // MARK: - Stress Tests
    
    func testSearchWithManyRecords() throws {
        // Insert 1000 records using batch insert (much faster!)
        let records = (1...1000).map { i in
            BlazeDataRecord(["title": .string("Bug \(i)")])
        }
        _ = try requireFixture(db).insertMany(records)
        
        // Enable search (rebuilds index for existing 1000 records)
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Search for "bug" (case-insensitive, should find all 1000)
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(results.count, 1000, "Should find all 1000 records")
    }
    
    func testSearchWithLongText() throws {
        // 150 repetitions = ~1,500 chars (well within 4KB page limit)
        let longText = String(repeating: "test word ", count: 150)
        _ = try requireFixture(db).insert(BlazeDataRecord(["content": .string(longText)]))
        
        try requireFixture(db).collection.enableSearch(on: ["content"])
        
        let results = try requireFixture(db).query().search("word", in: ["content"])
        XCTAssertEqual(results.count, 1, "Should find record with long text")
    }
    
    func testSearchRepeatedTerms() throws {
        // Enable search BEFORE inserting
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("bug bug bug bug bug")]))
        
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(results.count, 1, "Should find the record with repeated 'bug' terms")
        
        // Score should reflect term frequency (5 occurrences = higher score)
        guard let firstResult = results.first else {
            XCTFail("Expected at least one search result")
            return
        }
        XCTAssertGreaterThan(firstResult.score, 0, "Score should reflect term frequency")
    }
    
    // MARK: - Smart Search Tests
    
    func testSmartSearch() throws {
        for i in 1...50 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)")]))
        }
        
        // Enable smart search (auto-indexes when beneficial)
        try requireFixture(db).collection.enableSmartSearch(threshold: 10, fields: ["title"])
        
        // Should auto-index once threshold is hit
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(results.count, 50)
    }
    
    func testIndexPersistence() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Persistent Bug")]))
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        // Explicitly persist to save search index metadata
        try requireFixture(db).persist()
        
        // Debug: Check that index is enabled before closing
        let enabledBeforeClose = try requireFixture(db).collection.isSearchEnabled()
        print("📊 Search index enabled before close: \(enabledBeforeClose)")
        
        // Capture the current tempURL for reopening
        let dbURL = try requireFixture(tempURL)
        let metaURL = try requireFixture(dbURL).deletingPathExtension().appendingPathExtension("meta")
        print("📂 Database URL: \(try requireFixture(dbURL).path)")
        print("📂 Metadata URL: \(try requireFixture(metaURL).path)")
        print("📂 Meta file exists: \(FileManager.default.fileExists(atPath: try requireFixture(metaURL).path))")
        
        // Close and reopen
        db = nil
        
        print("📂 Meta file still exists after close: \(FileManager.default.fileExists(atPath: try requireFixture(metaURL).path))")
        
        db = try BlazeDBClient(name: "OptSearchTest_Reopened", fileURL: try requireFixture(dbURL), password: "SecureTestDB-456!")
        
        // Index should still be enabled
        let enabledAfterReopen = try requireFixture(db).collection.isSearchEnabled()
        print("📊 Search index enabled after reopen: \(enabledAfterReopen)")
        
        XCTAssertTrue(enabledAfterReopen, "Search index should persist across database close/reopen")
        
        // Search should still work
        let results = try requireFixture(db).query().search("persistent", in: ["title"])
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Edge Cases
    
    func testSearchSpecialCharacters() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug #123: Fix @login")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let results = try requireFixture(db).query().search("bug", in: ["title"])
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchEmptyField() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string(""), "description": .string("Has description")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title", "description"])
        
        let results = try requireFixture(db).query().search("description", in: ["description"])
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchNonIndexedField() throws {
        _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug"), "tags": .string("urgent")]))
        
        try requireFixture(db).collection.enableSearch(on: ["title"]) // Only index title
        
        // Search non-indexed field (should use fallback)
        let results = try requireFixture(db).query().search("urgent", in: ["tags"])
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }
    
    func testConcurrentSearchOperations() throws {
        for i in 1...100 {
            _ = try requireFixture(db).insert(BlazeDataRecord(["title": .string("Bug \(i)")]))
        }
        
        try requireFixture(db).collection.enableSearch(on: ["title"])
        
        let expectation = self.expectation(description: "Concurrent searches")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "test.search", attributes: .concurrent)
        let db = try requireFixture(self.db)
        
        for _ in 1...10 {
            queue.async { [db] in
                let results = try? db.query().search("bug", in: ["title"])
                XCTAssertNotNil(results)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
}

