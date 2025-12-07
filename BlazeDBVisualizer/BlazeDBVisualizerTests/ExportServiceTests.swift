//
//  ExportServiceTests.swift
//  BlazeDBVisualizerTests
//
//  Comprehensive tests for export operations
//  ✅ CSV export with proper escaping
//  ✅ JSON export (pretty and compact)
//  ✅ Unicode handling
//  ✅ Large dataset export
//
//  Created by Michael Danylchuk on 11/14/25.
//

import XCTest
import BlazeDB
@testable import BlazeDBVisualizer

final class ExportServiceTests: XCTestCase {
    
    var service: ExportService!
    var tempDirectory: URL!
    var testDBURL: URL!
    let testPassword = "test_password_123"
    
    override func setUp() {
        super.setUp()
        service = ExportService.shared
        
        // Create temp directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test database with diverse data
        testDBURL = tempDirectory.appendingPathComponent("test.blazedb")
        let db = try! BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        
        _ = try! db.insert(BlazeDataRecord([
            "name": .string("Alice"),
            "age": .int(25),
            "email": .string("alice@example.com")
        ]))
        
        _ = try! db.insert(BlazeDataRecord([
            "name": .string("Bob"),
            "age": .int(30),
            "email": .string("bob@example.com")
        ]))
        
        try! db.persist()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - CSV Export Tests
    
    func testExportToCSV() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let records = try db.fetchAll()
        
        let exportURL = tempDirectory.appendingPathComponent("export.csv")
        try service.exportToCSV(records: records, to: exportURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("name"))
        XCTAssertTrue(content.contains("age"))
        XCTAssertTrue(content.contains("email"))
        XCTAssertTrue(content.contains("Alice"))
        XCTAssertTrue(content.contains("Bob"))
    }
    
    func testCSVHasHeaders() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let records = try db.fetchAll()
        
        let exportURL = tempDirectory.appendingPathComponent("export.csv")
        try service.exportToCSV(records: records, to: exportURL)
        
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")
        
        XCTAssertGreaterThan(lines.count, 1, "Should have header + data rows")
        
        let header = lines[0]
        XCTAssertTrue(header.contains("age") || header.contains("email") || header.contains("name"))
    }
    
    func testCSVEscapesCommas() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        _ = try db.insert(BlazeDataRecord([
            "description": .string("This, has, commas")
        ]))
        try db.persist()
        
        let records = try db.fetchAll()
        let exportURL = tempDirectory.appendingPathComponent("export.csv")
        try service.exportToCSV(records: records, to: exportURL)
        
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("\"This, has, commas\""), "Commas should be escaped with quotes")
    }
    
    func testCSVEscapesQuotes() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        _ = try db.insert(BlazeDataRecord([
            "quote": .string("She said \"Hello\"")
        ]))
        try db.persist()
        
        let records = try db.fetchAll()
        let exportURL = tempDirectory.appendingPathComponent("export.csv")
        try service.exportToCSV(records: records, to: exportURL)
        
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("\"\""), "Quotes should be escaped by doubling")
    }
    
    // MARK: - JSON Export Tests
    
    func testExportToJSON() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let records = try db.fetchAll()
        
        let exportURL = tempDirectory.appendingPathComponent("export.json")
        try service.exportToJSON(records: records, to: exportURL, prettyPrint: true)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        let data = try Data(contentsOf: exportURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        XCTAssertEqual(json.count, records.count)
    }
    
    func testJSONIncludesID() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let records = try db.fetchAll()
        
        let exportURL = tempDirectory.appendingPathComponent("export.json")
        try service.exportToJSON(records: records, to: exportURL, prettyPrint: true)
        
        let data = try Data(contentsOf: exportURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        for item in json {
            XCTAssertNotNil(item["_id"], "Each record should have _id field")
        }
    }
    
    func testJSONPrettyPrint() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        let records = try db.fetchAll()
        
        let prettyURL = tempDirectory.appendingPathComponent("pretty.json")
        try service.exportToJSON(records: records, to: prettyURL, prettyPrint: true)
        
        let compactURL = tempDirectory.appendingPathComponent("compact.json")
        try service.exportToJSON(records: records, to: compactURL, prettyPrint: false)
        
        let prettyData = try Data(contentsOf: prettyURL)
        let compactData = try Data(contentsOf: compactURL)
        
        XCTAssertGreaterThan(prettyData.count, compactData.count, "Pretty print should be larger")
    }
    
    // MARK: - Export Full Database Tests
    
    func testExportDatabase() throws {
        let exportURL = tempDirectory.appendingPathComponent("full_export.json")
        
        try service.exportDatabase(
            dbPath: testDBURL.path,
            password: testPassword,
            format: .json(prettyPrint: true),
            to: exportURL
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }
    
    func testExportEmptyDatabase() throws {
        // Create empty database
        let emptyURL = tempDirectory.appendingPathComponent("empty.blazedb")
        let db = try BlazeDBClient(name: "empty", fileURL: emptyURL, password: testPassword)
        try db.persist()
        
        let exportURL = tempDirectory.appendingPathComponent("empty_export.json")
        
        XCTAssertThrowsError(try service.exportDatabase(
            dbPath: emptyURL.path,
            password: testPassword,
            format: .json(prettyPrint: true),
            to: exportURL
        )) { error in
            XCTAssertTrue(error is ExportServiceError, "Should throw ExportServiceError for empty database")
        }
    }
    
    // MARK: - Unicode and Special Characters
    
    func testExportUnicodeData() throws {
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        _ = try db.insert(BlazeDataRecord([
            "emoji": .string("🔥🚀💎"),
            "chinese": .string("中文"),
            "arabic": .string("العربية")
        ]))
        try db.persist()
        
        let records = try db.fetchAll()
        let exportURL = tempDirectory.appendingPathComponent("unicode.json")
        
        try service.exportToJSON(records: records, to: exportURL, prettyPrint: true)
        
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(content.contains("🔥"))
        XCTAssertTrue(content.contains("中文"))
        XCTAssertTrue(content.contains("العربية"))
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceExportLargeDataset() throws {
        // Create large dataset
        let db = try BlazeDBClient(name: "test", fileURL: testDBURL, password: testPassword)
        for i in 0..<1000 {
            _ = try db.insert(BlazeDataRecord([
                "id": .int(i),
                "data": .string("Item \(i)")
            ]))
        }
        try db.persist()
        
        let records = try db.fetchAll()
        
        measure {
            let exportURL = tempDirectory.appendingPathComponent("perf_\(UUID()).json")
            try! service.exportToJSON(records: records, to: exportURL, prettyPrint: false)
        }
    }
}

