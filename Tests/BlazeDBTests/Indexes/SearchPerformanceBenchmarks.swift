//
//  SearchPerformanceBenchmarks.swift
//  BlazeDBTests
//
//  Performance benchmarks for full-text search optimization.
//  Measures speedup from inverted indexing.
//
//  Created by Michael Danylchuk on 7/1/25.
//

import XCTest
@testable import BlazeDB
import Foundation

final class SearchPerformanceBenchmarks: XCTestCase {
    
    var tempURL: URL!
    var db: BlazeDBClient!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Benchmark-\(UUID().uuidString).blazedb")
        do {
            db = try BlazeDBClient(name: "BenchmarkTest", fileURL: tempURL, password: "SearchPerformance123!")
        } catch {
            XCTFail("Failed to initialize BlazeDBClient: \(error)")
        }
    }
    
    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
        super.tearDown()
    }
    
    // MARK: - Benchmark Tests
    
    func testBenchmark_SearchWith1000Records() throws {
        // Batch insert 1,000 records (10x faster!)
        let records = (1...1000).map { i in
            BlazeDataRecord([
                "title": .string("Bug Report \(i)"),
                "description": .string("This is a detailed description for bug number \(i) in the system")
            ])
        }
        _ = try db.insertMany(records)
        
        // Enable index
        try db.collection.enableSearch(on: ["title", "description"])
        
        // Measure search WITH index
        let start = Date()
        let results = try db.query().search("bug description system", in: ["title", "description"])
        let duration = Date().timeIntervalSince(start)
        
        print("""
            
            📊 BENCHMARK: 1,000 Records WITH Index
            ==========================================
            Search time: \(String(format: "%.2f", duration * 1000))ms
            Results: \(results.count)
            """)
        
        XCTAssertGreaterThan(results.count, 0)
    }
    
    func testBenchmark_SearchWith5000Records() throws {
        // Batch insert 5,000 records (15x faster!)
        let records = (1...5000).map { i in
            BlazeDataRecord([
                "title": .string("Bug Report \(i)"),
                "description": .string("This is a detailed description for bug number \(i) in the system")
            ])
        }
        _ = try db.insertMany(records)
        
        // Enable index
        let indexStart = Date()
        try db.collection.enableSearch(on: ["title", "description"])
        let indexDuration = Date().timeIntervalSince(indexStart)
        
        let stats = try db.collection.getSearchStats()!
        
        // Measure search WITH index
        let start = Date()
        let results = try db.query().search("bug description system", in: ["title", "description"])
        let duration = Date().timeIntervalSince(start)
        
        print("""
            
            📊 BENCHMARK: 5,000 Records WITH Index
            ==========================================
            Index build time: \(String(format: "%.2f", indexDuration))s
            Search time: \(String(format: "%.2f", duration * 1000))ms
            Results: \(results.count)
            Index stats:
              Words: \(stats.totalWords)
              Mappings: \(stats.totalMappings)
              Memory: \(stats.memoryUsage / 1024) KB
            """)
        
        XCTAssertGreaterThan(results.count, 0)
    }
    
    func testBenchmark_SearchWith10000Records() throws {
        // Insert 10,000 records (BATCH INSERT - 20x faster!)
        print("⚡ Batch inserting 10,000 records...")
        let insertStart = Date()
        
        let records = (1...10000).map { i -> BlazeDataRecord in
            // Add "urgent" keyword to only 1% of records for selective testing
            let isUrgent = i % 100 == 0
            return BlazeDataRecord([
                "title": .string("Bug Report \(i)\(isUrgent ? " urgent" : "")"),
                "description": .string("This is a detailed description for bug number \(i) in the system")
            ])
        }
        _ = try db.insertMany(records)
        
        let insertDuration = Date().timeIntervalSince(insertStart)
        print("  ✅ Inserted 10,000 records in \(String(format: "%.2f", insertDuration))s")
        
        // Enable index
        print("🔍 Building search index...")
        let indexStart = Date()
        try db.collection.enableSearch(on: ["title", "description"])
        let indexDuration = Date().timeIntervalSince(indexStart)
        print("  ✅ Index built in \(String(format: "%.2f", indexDuration))s")
        
        guard let stats = try db.collection.getSearchStats() else {
            XCTFail("Failed to retrieve search stats")
            return
        }
        
        // Measure search WITH index (use selective query for realistic benchmark)
        print("🔎 Searching...")
        
        // Debug: Check individual term matches
        let reportMatches = try db.query().search("report", in: ["title", "description"])
        let urgentMatches = try db.query().search("urgent", in: ["title", "description"])
        print("  Single term 'report': \(reportMatches.count) matches")
        print("  Single term 'urgent': \(urgentMatches.count) matches")
        
        let start = Date()
        let results = try db.query().search("report urgent", in: ["title", "description"])
        let duration = Date().timeIntervalSince(start)
        print("  Combined 'report urgent' (AND): \(results.count) matches")
        
        print("""
            
            📊 BENCHMARK: 10,000 Records WITH Index
            ==========================================
            Insert time: \(String(format: "%.2f", insertDuration))s
            Index build time: \(String(format: "%.2f", indexDuration))s
            Search time: \(String(format: "%.2f", duration * 1000))ms
            Query: "report urgent" (selective, ~100 matches = 1%)
            Results: \(results.count)
            Index stats:
              Words: \(stats.totalWords)
              Mappings: \(stats.totalMappings)
              Memory: \(stats.memoryUsage / 1024) KB
            ==========================================
            ✅ TOTAL TIME: \(String(format: "%.2f", insertDuration + indexDuration + duration))s
            """)
        
        XCTAssertGreaterThan(results.count, 0, "Should find matching records")
        XCTAssertEqual(results.count, 100, "Should match exactly 100 records (1% with 'urgent')")
        // Expect ~100 matches (1%), allow up to 200ms for AND logic validation
        XCTAssertLessThan(duration, 0.2, "Selective search (1% matches) should be < 200ms for 10K records")
    }
    
    // MARK: - Real-World Scenario Benchmarks
    
    func testRealWorldBugTrackerScenario() throws {
        print("""
            
            📊 REAL-WORLD SCENARIO: Bug Tracker
            ==========================================
            """)
        
        // Simulate bug tracker with 5,000 bugs (BATCH INSERT - 15x faster!)
        let statuses = ["open", "in_progress", "resolved", "closed"]
        let priorities = ["low", "medium", "high", "critical"]
        
        let bugRecords = (1...5000).map { i in
            BlazeDataRecord([
                "title": .string("Bug #\(i): \(["Login", "Logout", "Payment", "Auth", "UI"][i % 5]) issue"),
                "description": .string("Detailed description of bug \(i) with multiple words and context"),
                "status": .string(statuses[i % statuses.count]),
                "priority": .string(priorities[i % priorities.count]),
                "assignee": .string("user\(i % 10)")
            ])
        }
        _ = try db.insertMany(bugRecords)
        
        print("✅ Batch inserted 5,000 bugs")
        
        // Enable search
        let indexStart = Date()
        try db.collection.enableSearch(on: ["title", "description"])
        let indexDuration = Date().timeIntervalSince(indexStart)
        
        print("Index built in \(String(format: "%.2f", indexDuration))s")
        
        // Scenario 1: Search for "login issue"
        let search1Start = Date()
        let results1 = try db.query().search("login issue", in: ["title", "description"])
        let search1Duration = Date().timeIntervalSince(search1Start)
        
        // Scenario 2: Search + filter by status
        let search2Start = Date()
        let results2 = try db.query()
            .where("status", equals: .string("open"))
            .search("payment", in: ["title", "description"])
        let search2Duration = Date().timeIntervalSince(search2Start)
        
        // Scenario 3: Search with filters
        let search3Start = Date()
        let results3 = try db.query()
            .where("priority", equals: .string("critical"))
            .search("auth", in: ["title", "description"])
        let search3Duration = Date().timeIntervalSince(search3Start)
        
        print("""
            Results:
              Scenario 1 (search): \(results1.count) results in \(String(format: "%.2f", search1Duration * 1000))ms
              Scenario 2 (search + filter): \(results2.count) results in \(String(format: "%.2f", search2Duration * 1000))ms
              Scenario 3 (search + filter): \(results3.count) results in \(String(format: "%.2f", search3Duration * 1000))ms
            """)
        
        let stats = try db.collection.getSearchStats()!
        print("""
            
            Index stats:
              Memory: \(stats.memoryUsage / 1024) KB
              Words: \(stats.totalWords)
            """)
    }
    
    func testConcurrentSearchPerformance() throws {
        // Batch insert 5,000 records (15x faster!)
        let records = (1...5000).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "description": .string("Description \(i)")
            ])
        }
        _ = try db.insertMany(records)
        
        try db.collection.enableSearch(on: ["title", "description"])
        
        // Measure 50 concurrent searches
        let start = Date()
        let expectation = self.expectation(description: "Concurrent searches")
        expectation.expectedFulfillmentCount = 50
        
        let queue = DispatchQueue(label: "test.search", attributes: .concurrent)
        
        for _ in 1...50 {
            queue.async {
                _ = try? self.db.query().search("bug", in: ["title", "description"])
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        let duration = Date().timeIntervalSince(start)
        let avgPerSearch = duration / 50
        
        print("""
            
            📊 CONCURRENT SEARCH BENCHMARK
            ==========================================
            50 concurrent searches: \(String(format: "%.2f", duration))s
            Average per search: \(String(format: "%.2f", avgPerSearch * 1000))ms
            Throughput: \(String(format: "%.0f", 50 / duration)) searches/sec
            """)
    }
}

