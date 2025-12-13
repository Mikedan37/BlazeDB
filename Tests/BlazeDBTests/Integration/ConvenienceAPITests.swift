//
//  ConvenienceAPITests.swift
//  BlazeDBTests
//
//  Tests for the convenience API (name-based database creation)
//
//  Created: 2025-01-XX
//

import XCTest
@testable import BlazeDB

final class ConvenienceAPITests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        // Use temp directory for testing (don't pollute Application Support)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Cleanup: Remove test databases from Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let blazeDBDir = appSupport.appendingPathComponent("BlazeDB")
        
        // Remove test databases
        let testNames = ["TestDB", "TestDB2", "MyApp", "UserData", "App1", "App2"]
        for name in testNames {
            let dbURL = blazeDBDir.appendingPathComponent("\(name).blazedb")
            try? FileManager.default.removeItem(at: dbURL)
            let metaURL = blazeDBDir.appendingPathComponent("\(name).meta")
            try? FileManager.default.removeItem(at: metaURL)
        }
        
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Convenience Initializer Tests
    
    func testConvenienceInit_ByNameOnly() throws {
        // Create database by name only
        let db = try BlazeDBClient(name: "TestDB", password: "ConvenienceAPITest123!")
        
        // Verify it was created in Application Support
        let expectedURL = try BlazeDBClient.defaultDatabaseURL(for: "TestDB")
        XCTAssertEqual(db.fileURL, expectedURL, "Database should be in Application Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path), "Database file should exist")
        
        // Verify we can use it
        let id = try db.insert(BlazeDataRecord(["test": .string("value")]))
        let fetched = try db.fetch(id: id)
        XCTAssertNotNil(fetched, "Should be able to fetch record")
    }
    
    func testConvenienceInit_Failable() {
        // Failable initializer
        let db = BlazeDBClient.create(name: "TestDB2", password: "ConvenienceAPITest123!")
        
        XCTAssertNotNil(db, "Database should be created")
        XCTAssertEqual(db?.name, "TestDB2", "Database name should match")
    }
    
    func testConvenienceInit_WeakPassword() {
        // Weak password should fail
        let db = BlazeDBClient.create(name: "TestDB", password: "123")
        
        XCTAssertNil(db, "Database creation should fail with weak password")
    }
    
    func testConvenienceInit_WithProject() throws {
        // Create with project namespace
        let db = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!", project: "MyProject")
        
        XCTAssertEqual(db.name, "MyApp", "Database name should match")
        // Project is stored internally, verify it works
        let id = try db.insert(BlazeDataRecord(["test": .string("value")]))
        XCTAssertNotNil(id, "Should be able to insert record")
    }
    
    // MARK: - Default Location Tests
    
    func testDefaultDatabaseURL() throws {
        let url = try BlazeDBClient.defaultDatabaseURL(for: "MyApp")
        
        // Should be in Application Support/BlazeDB
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let expectedDir = appSupport.appendingPathComponent("BlazeDB")
        
        XCTAssertTrue(url.path.contains("Application Support/BlazeDB"), "Should be in Application Support/BlazeDB")
        XCTAssertEqual(url.lastPathComponent, "MyApp.blazedb", "Filename should match")
        
        // Directory should be created
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDir.path), "BlazeDB directory should exist")
    }
    
    func testDefaultDatabaseURL_WithExtension() throws {
        // Should handle .blazedb extension
        let url1 = try BlazeDBClient.defaultDatabaseURL(for: "MyApp")
        let url2 = try BlazeDBClient.defaultDatabaseURL(for: "MyApp.blazedb")
        
        XCTAssertEqual(url1, url2, "Should handle extension correctly")
    }
    
    func testDefaultDatabaseDirectory() throws {
        let directory = try BlazeDBClient.defaultDatabaseDirectory
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let expectedDir = appSupport.appendingPathComponent("BlazeDB")
        
        XCTAssertEqual(directory, expectedDir, "Should return Application Support/BlazeDB")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path), "Directory should exist")
    }
    
    // MARK: - Discovery Tests
    
    func testDiscoverDatabases() throws {
        // Create a few databases
        _ = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        _ = try BlazeDBClient(name: "UserData", password: "ConvenienceAPITest123!")
        
        // Discover them
        let databases = try BlazeDBClient.discoverDatabases()
        
        XCTAssertGreaterThanOrEqual(databases.count, 2, "Should find at least 2 databases")
        
        let names = databases.map { $0.name }
        XCTAssertTrue(names.contains("MyApp") || names.contains { $0.contains("MyApp") }, "Should find MyApp")
        XCTAssertTrue(names.contains("UserData") || names.contains { $0.contains("UserData") }, "Should find UserData")
    }
    
    func testFindDatabase() throws {
        // Create a database
        _ = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        
        // Find it
        let found = try BlazeDBClient.findDatabase(named: "MyApp")
        
        XCTAssertNotNil(found, "Should find database")
        XCTAssertTrue(found?.path.contains("MyApp") ?? false, "Path should contain MyApp")
    }
    
    func testFindDatabase_NotFound() throws {
        // Try to find non-existent database
        let found = try BlazeDBClient.findDatabase(named: "NonExistent")
        
        XCTAssertNil(found, "Should not find non-existent database")
    }
    
    func testDatabaseExists() {
        // Create a database
        _ = try? BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        
        // Check if it exists
        XCTAssertTrue(BlazeDBClient.databaseExists(named: "MyApp"), "Database should exist")
        XCTAssertFalse(BlazeDBClient.databaseExists(named: "NonExistent"), "Non-existent database should not exist")
    }
    
    // MARK: - Registry Tests
    
    func testRegisterDatabase() throws {
        let db = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        
        // Register it
        BlazeDBClient.registerDatabase(name: "MyApp", client: db)
        
        // Get it back
        let retrieved = BlazeDBClient.getRegisteredDatabase(named: "MyApp")
        
        XCTAssertNotNil(retrieved, "Should retrieve registered database")
        XCTAssertEqual(retrieved?.name, "MyApp", "Name should match")
    }
    
    func testUnregisterDatabase() throws {
        let db = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        
        // Register it
        BlazeDBClient.registerDatabase(name: "MyApp", client: db)
        
        // Unregister it
        BlazeDBClient.unregisterDatabase(named: "MyApp")
        
        // Should not be found
        let retrieved = BlazeDBClient.getRegisteredDatabase(named: "MyApp")
        XCTAssertNil(retrieved, "Should not retrieve unregistered database")
    }
    
    func testRegisteredDatabases() throws {
        // Register multiple databases
        let db1 = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        let db2 = try BlazeDBClient(name: "UserData", password: "ConvenienceAPITest123!")
        
        BlazeDBClient.registerDatabase(name: "MyApp", client: db1)
        BlazeDBClient.registerDatabase(name: "UserData", client: db2)
        
        // List all
        let registered = BlazeDBClient.registeredDatabases()
        
        XCTAssertTrue(registered.contains("MyApp"), "Should contain MyApp")
        XCTAssertTrue(registered.contains("UserData"), "Should contain UserData")
    }
    
    // MARK: - Integration Tests
    
    func testIntegration_CreateAndDiscover() throws {
        // Cleanup any existing MyApp database first
        let dbURL = try BlazeDBClient.defaultDatabaseURL(for: "MyApp")
        let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: metaURL)
        
        // Create database by name
        let db = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        
        // Insert some data
        let id = try db.insert(BlazeDataRecord(["value": .int(42)]))
        
        // Persist to disk before discovery
        try db.persist()
        
        // Discover it
        let found = try BlazeDBClient.findDatabase(named: "MyApp")
        
        XCTAssertNotNil(found, "Should find database")
        XCTAssertGreaterThan(found?.recordCount ?? 0, 0, "Should have records")
        
        // Open it again
        let db2 = try BlazeDBClient(name: "MyApp", password: "ConvenienceAPITest123!")
        let fetched = try db2.fetch(id: id)
        
        XCTAssertNotNil(fetched, "Should be able to fetch record from reopened database")
        if let fetched = fetched {
            XCTAssertEqual(try? fetched.int("value"), 42, "Value should match")
        }
    }
    
    func testIntegration_MultipleDatabases() throws {
        // Cleanup any existing databases first
        for name in ["App1", "App2"] {
            let dbURL = try BlazeDBClient.defaultDatabaseURL(for: name)
            let metaURL = dbURL.deletingPathExtension().appendingPathExtension("meta")
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(at: metaURL)
        }
        
        // Create multiple databases
        let db1 = try BlazeDBClient(name: "App1", password: "ConvenienceAPITest123!")
        let db2 = try BlazeDBClient(name: "App2", password: "ConvenienceAPITest123!")
        
        // Insert data in each
        let id1 = try db1.insert(BlazeDataRecord(["app": .string("1")]))
        let id2 = try db2.insert(BlazeDataRecord(["app": .string("2")]))
        
        // Persist both databases to disk before discovery
        try db1.persist()
        try db2.persist()
        
        // Discover all
        let databases = try BlazeDBClient.discoverDatabases()
        
        XCTAssertGreaterThanOrEqual(databases.count, 2, "Should find at least 2 databases")
        
        // Verify data is separate
        let fetched1 = try db1.fetch(id: id1)
        let fetched2 = try db2.fetch(id: id2)
        
        XCTAssertNotNil(fetched1, "Should fetch from db1")
        XCTAssertNotNil(fetched2, "Should fetch from db2")
        if let fetched1 = fetched1 {
            XCTAssertEqual(try? fetched1.string("app"), "1", "db1 should have app=1")
        }
        if let fetched2 = fetched2 {
            XCTAssertEqual(try? fetched2.string("app"), "2", "db2 should have app=2")
        }
    }
}

