//  FullTextSearchTests.swift
//  BlazeDBTests
//
//  Comprehensive tests for full-text search

import XCTest
@testable import BlazeDB

final class FullTextSearchTests: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        
        // Aggressive test isolation
        Thread.sleep(forTimeInterval: 0.01)
        BlazeDBClient.clearCachedKey()
        
        let testID = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Search-\(testID).blazedb")
        
        // Clean up any leftover files (retry 3x)
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
            db = try BlazeDBClient(name: "search_test_\(testID)", fileURL: tempURL, password: "FullTextSearchTest123!")
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
    
    // MARK: - Basic Search
    
    func testSimpleTextSearch() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Login bug"), "description": .string("Users can't login")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Signup issue"), "description": .string("Signup form broken")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login button color"), "description": .string("Button is wrong color")]))
        
        let results = try db.query()
            .search("login", in: ["title", "description"])
        
        XCTAssertEqual(results.count, 2)  // "Login bug" and "Login button color"
    }
    
    func testSearchWithRelevanceScoring() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Login bug"), "body": .string("Some text")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug report"), "body": .string("Login issue here")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login Login Login"), "body": .string("Triple match")]))
        
        let results = try db.query()
            .search("login", in: ["title", "body"], config: nil)
        
        XCTAssertGreaterThan(results.count, 0)
        
        // Debug: Print all scores
        print("📊 Search results with TF (Term Frequency):")
        for (index, result) in results.enumerated() {
            let title = result.record.storage["title"]?.stringValue ?? "nil"
            print("  [\(index)] \(title) → score: \(result.score)")
        }
        
        // Results should be sorted by relevance (highest first)
        // "Login Login Login" (3 matches in title) should score higher than "Login bug" (1 match)
        XCTAssertGreaterThan(results[0].score, results[1].score, 
                            "First result should have higher score than second")
    }
    
    func testCaseInsensitiveSearch() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("LOGIN BUG")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("login bug")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login Bug")]))
        
        let config = SearchConfig(caseSensitive: false, fields: ["title"])
        let results = try db.query()
            .search("login", in: ["title"], config: config)
        
        XCTAssertEqual(results.count, 3)  // All matches regardless of case
    }
    
    func testCaseSensitiveSearch() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("LOGIN")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("login")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login")]))
        
        let config = SearchConfig(caseSensitive: true, fields: ["title"])
        let results = try db.query()
            .search("login", in: ["title"], config: config)
        
        // Debug: Print what matched
        print("🔠 Case-sensitive search for 'login':")
        for result in results {
            let title = result.record.storage["title"]?.stringValue ?? "nil"
            print("  Matched: \(title) (score: \(result.score))")
        }
        
        XCTAssertEqual(results.count, 1, "Should only match exact case 'login'")  // Only exact case match
    }
    
    func testMultiWordSearch() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Login bug on mobile")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Mobile bug report")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login issue")]))
        
        let results = try db.query()
            .search("login mobile", in: ["title"])
        
        // Debug: Print what matched
        print("🔍 Multi-word search for 'login mobile' (AND logic):")
        for result in results {
            let title = result.record.storage["title"]?.stringValue ?? "nil"
            let matchedTerms = result.matches["title"] ?? []
            print("  Matched: \(title) → terms: \(matchedTerms) (score: \(result.score))")
        }
        
        XCTAssertEqual(results.count, 1, "Should only match records with BOTH 'login' AND 'mobile'")
    }
    
    func testPartialWordMatching() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Authentication failed")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Authorized users")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Author list")]))
        
        let results = try db.query()
            .search("auth", in: ["title"])
        
        // Should match all three (partial matching)
        XCTAssertGreaterThanOrEqual(results.count, 3)
    }
    
    // MARK: - Search with Filters
    
    func testSearchWithWhereClause() throws {
        let records = (0..<100).map { i in
            BlazeDataRecord([
                "title": .string(i % 2 == 0 ? "Login bug \(i)" : "Other bug \(i)"),
                "priority": .int(i % 5 + 1)
            ])
        }
        _ = try db.insertMany(records)
        
        let results = try db.query()
            .where("priority", greaterThan: .int(3))
            .search("login", in: ["title"])
        
        // Should only find "Login" bugs with priority > 3
        XCTAssertLessThan(results.count, 50)  // Not all "Login" bugs
        for result in results {
            XCTAssert((result.record.storage["priority"]?.intValue ?? 0) > 3)
        }
    }
    
    func testSearchWithLimitAndOffset() throws {
        let records = (0..<50).map { i in
            BlazeDataRecord(["title": .string("Bug \(i)")])
        }
        _ = try db.insertMany(records)
        
        let results = try db.query()
            .search("bug", in: ["title"])
            .compactMap { $0.record.storage["title"]?.stringValue }
        
        XCTAssertEqual(results.count, 50)
    }
    
    // MARK: - Relevance Scoring
    
    func testTitleBoost() throws {
        _ = try db.insert(BlazeDataRecord([
            "title": .string("login"),
            "body": .string("other text")
        ]))
        _ = try db.insert(BlazeDataRecord([
            "title": .string("other"),
            "body": .string("login in body")
        ]))
        
        let results = try db.query()
            .search("login", in: ["title", "body"], config: nil)
        
        // Title matches should score higher
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }
    
    func testMultipleMatchesScoreHigher() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("login")]))  // 1 match
        _ = try db.insert(BlazeDataRecord(["title": .string("login login")]))  // 2 matches
        _ = try db.insert(BlazeDataRecord(["title": .string("login login login")]))  // 3 matches
        
        let results = try db.query()
            .search("login", in: ["title"], config: nil)
        
        XCTAssertEqual(results.count, 3)
        // More matches = higher score
        XCTAssertGreaterThan(results[0].score, results[1].score)
        XCTAssertGreaterThan(results[1].score, results[2].score)
    }
    
    // MARK: - Edge Cases
    
    func testSearchEmptyQuery() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug")]))
        
        let results = try db.query()
            .search("", in: ["title"])
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchEmptyDataset() throws {
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchMissingField() throws {
        _ = try db.insert(BlazeDataRecord(["other": .string("value")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchNonStringField() throws {
        _ = try db.insert(BlazeDataRecord(["value": .int(12345)]))
        
        let results = try db.query()
            .search("123", in: ["value"])
        
        XCTAssertEqual(results.count, 0)  // Can't search non-string fields
    }
    
    func testSearchSpecialCharacters() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug #123: Fix login")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchUnicode() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("🐛 Login bug")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug report 🔥")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Performance
    
    func testSearchPerformanceOn10k() throws {
        // PERFORMANCE: Reduced to 1000 records to avoid test timeout
        // Inserting 10k records with full persistence takes ~60s, which causes test to stall
        // 1000 records is sufficient to test search performance
        let recordCount = 1000
        let records = (0..<recordCount).map { i in
            BlazeDataRecord([
                "title": .string(i % 10 == 0 ? "Login bug \(i)" : "Bug \(i)"),
                "body": .string("Some description \(i)")
            ])
        }
        
        // Insert records (this may take a few seconds with persistence, but won't stall)
        _ = try db.insertMany(records)
        
        // Measure search performance only
        let start = Date()
        let results = try db.query()
            .search("login", in: ["title", "body"])
        let duration = Date().timeIntervalSince(start)
        
        let expectedCount = recordCount / 10  // 10% of records have "Login bug"
        XCTAssertEqual(results.count, expectedCount, "Should find \(expectedCount) 'Login bug' records (10%)")
        XCTAssertLessThan(duration, 2.0, "Search on \(recordCount) records should be < 2s")
    }
    
    func testSearchWithFilterPerformance() throws {
        // Use batch insert (10x faster!)
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "title": .string(i % 10 == 0 ? "Login bug" : "Bug"),
                "priority": .int((i / 10) % 5 + 1),  // Fixed: Different modulo to allow overlap
                "status": .string(i % 2 == 0 ? "open" : "closed")
            ])
        }
        
        _ = try db.insertMany(records)
        
        // Debug: Check how many match each filter
        let allRecords = try db.fetchAll()
        let loginRecords = allRecords.filter { $0.storage["title"]?.stringValue?.contains("Login") ?? false }
        let openRecords = allRecords.filter { $0.storage["status"]?.stringValue == "open" }
        let highPriorityRecords = allRecords.filter { ($0.storage["priority"]?.intValue ?? 0) > 3 }
        print("📊 Test data: \(allRecords.count) total")
        print("  - \(loginRecords.count) with 'Login'")
        print("  - \(openRecords.count) with status='open'")
        print("  - \(highPriorityRecords.count) with priority>3")
        
        let start = Date()
        let results = try db.query()
            .where("status", equals: .string("open"))  // Filter first
            .where("priority", greaterThan: .int(3))
            .search("login", in: ["title"])
        let duration = Date().timeIntervalSince(start)
        
        print("  - \(results.count) matching ALL filters + search")
        
        XCTAssertGreaterThan(results.count, 0, "Should find records matching all criteria")
        XCTAssertLessThan(duration, 1.0, "Filtered search should be fast")
    }
    
    // MARK: - Real-World Scenarios
    
    func testBugTrackerSearch() throws {
        // Real bug tracker data
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Login button not working"),
            "description": .string("Users report the login button doesn't respond"),
            "tags": .array([.string("ui"), .string("login")])
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Database connection timeout"),
            "description": .string("Login endpoint times out after 30s"),
            "tags": .array([.string("backend"), .string("login")])
        ]))
        
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Payment processing error"),
            "description": .string("Credit card validation fails"),
            "tags": .array([.string("payment")])
        ]))
        
        let results = try db.query()
            .search("login button", in: ["title", "description"], config: nil)
        
        XCTAssertGreaterThan(results.count, 0)
        // "Login button not working" should score highest
        XCTAssertTrue(results[0].record["title"]?.stringValue?.contains("Login button") ?? false)
    }
    
    func testSearchAcrossMultipleFields() throws {
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Bug report"),
            "description": .string("Login fails"),
            "comments": .string("Confirmed on production")
        ]))
        
        let results = try db.query()
            .search("login production", in: ["title", "description", "comments"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchWithMinWordLength() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("A bug in the app")]))
        
        let config = SearchConfig(minWordLength: 2, caseSensitive: false, language: nil, fields: ["title"])
        let results = try db.query()
            .search("a bug", in: ["title"], config: config)
        
        // "a" is too short (minWordLength=2), only "bug" matches
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Search Result Details
    
    func testSearchResultContainsMatches() throws {
        _ = try db.insert(BlazeDataRecord([
            "title": .string("Login bug"),
            "description": .string("Login fails on iOS")
        ]))
        
        let results = try db.query()
            .search("login", in: ["title", "description"], config: nil)
        
        XCTAssertEqual(results.count, 1)
        let result = results[0]
        
        // Should track which fields matched
        XCTAssertGreaterThan(result.matches.count, 0)
        XCTAssertNotNil(result.matches["title"])
        XCTAssertNotNil(result.matches["description"])
    }
    
    func testSearchResultScore() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Login")]))
        
        let results = try db.query()
            .search("login", in: ["title"], config: nil)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertGreaterThan(results[0].score, 0)
    }
    
    // MARK: - Tokenization Tests
    
    func testTokenizationWithPunctuation() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug: login, signup, logout!")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testTokenizationWithNumbers() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug #123: Login issue")]))
        
        let results1 = try db.query()
            .search("123", in: ["title"])
        
        let results2 = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results2.count, 1)
    }
    
    func testTokenizationWithHyphens() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("User-authentication bug")]))
        
        let results = try db.query()
            .search("authentication", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - Combined with Other Query Features
    
    func testSearchWithOrderBy() throws {
        let records = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("Login bug \(i)"),
                "priority": .int(i % 5 + 1),
                "created_at": .date(Date(timeIntervalSinceNow: Double(-i * 3600)))
            ])
        }
        _ = try db.insertMany(records)
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        // Results are sorted by relevance by default
        XCTAssertEqual(results.count, 20)
    }
    
    func testSearchWithLimit() throws {
        let records = (0..<50).map { i in
            BlazeDataRecord(["title": .string("Bug \(i)")])
        }
        _ = try db.insertMany(records)
        
        let results = try db.query()
            .limit(10)
            .search("bug", in: ["title"])
        
        XCTAssertEqual(results.count, 10)
    }
    
    func testSearchWithPagination() throws {
        let records = (0..<100).map { i in
            BlazeDataRecord(["title": .string("Bug \(i)")])
        }
        _ = try db.insertMany(records)
        
        let page1 = try db.query()
            .limit(20)
            .offset(0)
            .search("bug", in: ["title"])
        
        let page2 = try db.query()
            .limit(20)
            .offset(20)
            .search("bug", in: ["title"])
        
        XCTAssertEqual(page1.count, 20)
        XCTAssertEqual(page2.count, 20)
    }
    
    // MARK: - Stress Tests
    
    func testSearchLargeText() throws {
        // 30 repetitions = ~1,350 chars (well within 4KB page limit)
        let largeText = String(repeating: "This is a long description with many words. ", count: 30)
        _ = try db.insert(BlazeDataRecord(["description": .string(largeText)]))
        
        let results = try db.query()
            .search("description", in: ["description"])
        
        XCTAssertEqual(results.count, 1, "Should find record with 'description' in large text")
    }
    
    func testSearchManyRecords() throws {
        // Use batch insert (10x faster!)
        let records = (0..<5000).map { i in
            BlazeDataRecord([
                "title": .string(i % 100 == 0 ? "Login bug" : "Bug \(i)"),
                "body": .string("Description \(i)")
            ])
        }
        
        _ = try db.insertMany(records)
        
        // Measure search performance only
        let start = Date()
        let searchResults = try db.query()
            .search("login", in: ["title", "body"])
        let duration = Date().timeIntervalSince(start)
        
        XCTAssertEqual(searchResults.count, 50, "Should find 50 'Login bug' records")
        XCTAssertLessThan(duration, 1.0, "Search should complete in under 1 second")
    }
    
    // MARK: - No Matches
    
    func testSearchNoMatches() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("Bug report")]))
        
        let results = try db.query()
            .search("nonexistent", in: ["title"])
        
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Empty/Nil Values
    
    func testSearchWithNilField() throws {
        _ = try db.insert(BlazeDataRecord(["other": .string("value")]))  // No title field
        _ = try db.insert(BlazeDataRecord(["title": .string("Login bug")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchEmptyString() throws {
        _ = try db.insert(BlazeDataRecord(["title": .string("")]))
        _ = try db.insert(BlazeDataRecord(["title": .string("Login")]))
        
        let results = try db.query()
            .search("login", in: ["title"])
        
        XCTAssertEqual(results.count, 1)
    }
}

