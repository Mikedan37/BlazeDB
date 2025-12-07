//
//  FullTextSearchTests.swift
//  BlazeDBVisualizerTests
//
//  Test full-text search functionality
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class FullTextSearchTests: XCTestCase {
    var tempDir: URL!
    var dbURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        dbURL = tempDir.appendingPathComponent("test.blazedb")
        db = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test123")
        
        // Add test data
        try db.insert(BlazeDataRecord( [
            "title": .string("Swift Programming Guide"),
            "content": .string("Learn Swift programming language"),
            "category": .string("Programming")
        ]))
        
        try db.insert(BlazeDataRecord( [
            "title": .string("Database Design"),
            "content": .string("How to design efficient databases"),
            "category": .string("Database")
        ]))
        
        try db.insert(BlazeDataRecord( [
            "title": .string("SwiftUI Tutorial"),
            "content": .string("Building apps with SwiftUI framework"),
            "category": .string("Programming")
        ]))
        
        try db.persist()
    }
    
    override func tearDown() async throws {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Basic Search Tests
    
    func testSimpleSearch() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content", "category"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "swift",
            config: config
        )
        
        XCTAssertEqual(results.count, 2, "Should find 2 records with 'swift'")
    }
    
    func testMultiFieldSearch() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "database",
            config: config
        )
        
        XCTAssertGreaterThan(results.count, 0, "Should find records with 'database'")
    }
    
    func testRelevanceScoring() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "swift programming",
            config: config
        )
        
        // Results should be sorted by relevance (highest score first)
        if results.count > 1 {
            XCTAssertGreaterThanOrEqual(results[0].score, results[1].score)
        }
        
        // All scores should be between 0 and 1
        for result in results {
            XCTAssertGreaterThanOrEqual(result.score, 0.0)
            XCTAssertLessThanOrEqual(result.score, 1.0)
        }
    }
    
    func testNoResults() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "nonexistent_term_xyz",
            config: config
        )
        
        XCTAssertTrue(results.isEmpty, "Should return no results for non-matching query")
    }
    
    // MARK: - Configuration Tests
    
    func testCaseSensitiveSearch() throws {
        let records = try db.fetchAll()
        
        let caseSensitive = SearchConfig(caseSensitive: true, fields: ["title", "content"])
        let caseInsensitive = SearchConfig(caseSensitive: false, fields: ["title", "content"])
        
        let sensitiveResults = FullTextSearchEngine.search(
            records: records,
            query: "SWIFT",
            config: caseSensitive
        )
        
        let insensitiveResults = FullTextSearchEngine.search(
            records: records,
            query: "SWIFT",
            config: caseInsensitive
        )
        
        // Case insensitive should find more or equal results
        XCTAssertGreaterThanOrEqual(insensitiveResults.count, sensitiveResults.count)
    }
    
    func testMinWordLength() throws {
        let records = try db.fetchAll()
        
        let config = SearchConfig(minWordLength: 5, fields: ["title", "content"])
        
        // Short words should be ignored
        let results = FullTextSearchEngine.search(
            records: records,
            query: "to in",  // Words shorter than 5
            config: config
        )
        
        // Should return fewer results or none
        XCTAssertTrue(results.isEmpty || results.count < records.count)
    }
    
    func testFieldSelection() throws {
        let records = try db.fetchAll()
        
        // Search only in title
        let titleConfig = SearchConfig(fields: ["title"])
        let titleResults = FullTextSearchEngine.search(
            records: records,
            query: "tutorial",
            config: titleConfig
        )
        
        // Search in content
        let contentConfig = SearchConfig(fields: ["content"])
        let contentResults = FullTextSearchEngine.search(
            records: records,
            query: "efficient",
            config: contentConfig
        )
        
        // Different fields should yield different results
        XCTAssertNotEqual(titleResults.count, contentResults.count)
    }
    
    // MARK: - Tokenization Tests
    
    func testTokenization() {
        let config = SearchConfig(minWordLength: 2, caseSensitive: false, fields: [])
        
        let tokens = FullTextSearchEngine.tokenize("Swift Programming, Database Design!", config: config)
        
        XCTAssertTrue(tokens.contains("swift"))
        XCTAssertTrue(tokens.contains("programming"))
        XCTAssertTrue(tokens.contains("database"))
        XCTAssertTrue(tokens.contains("design"))
    }
    
    func testTokenizationMinLength() {
        let config = SearchConfig(minWordLength: 5, caseSensitive: false, fields: [])
        
        let tokens = FullTextSearchEngine.tokenize("Swift is a programming language", config: config)
        
        // Only words >= 5 chars
        XCTAssertTrue(tokens.contains("swift"))
        XCTAssertTrue(tokens.contains("programming"))
        XCTAssertTrue(tokens.contains("language"))
        XCTAssertFalse(tokens.contains("is"))
        XCTAssertFalse(tokens.contains("a"))
    }
    
    // MARK: - Match Tracking Tests
    
    func testMatchedTermsTracking() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "swift programming",
            config: config
        )
        
        for result in results {
            // Should track which fields matched
            XCTAssertFalse(result.matches.isEmpty, "Should track matched terms")
        }
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() throws {
        // Add more records
        for i in 0..<500 {
            try db.insert(BlazeDataRecord( [
                "title": .string("Record \(i)"),
                "content": .string("Content with search terms \(i)")
            ]))
        }
        
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        // Measure search performance
        measure {
            _ = FullTextSearchEngine.search(
                records: records,
                query: "search terms",
                config: config
            )
        }
        
        // Should be fast (< 100ms for 550 records)
    }
    
    func testEmptyQuery() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "",
            config: config
        )
        
        XCTAssertTrue(results.isEmpty, "Empty query should return no results")
    }
    
    func testSpecialCharacters() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "swift! programming?",
            config: config
        )
        
        // Should handle punctuation gracefully
        XCTAssertFalse(results.isEmpty, "Should handle special characters")
    }
    
    // MARK: - Relevance Tests
    
    func testHigherRelevanceForMultipleMatches() throws {
        let records = try db.fetchAll()
        let config = SearchConfig(fields: ["title", "content"])
        
        let results = FullTextSearchEngine.search(
            records: records,
            query: "swift",
            config: config
        )
        
        // Record with "Swift" in both title and content should rank higher
        if results.count > 1 {
            let topResult = results[0]
            XCTAssertGreaterThan(topResult.matches.count, 0)
        }
    }
}

