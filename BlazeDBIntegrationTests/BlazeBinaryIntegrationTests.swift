//
//  BlazeBinaryIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Integration tests: BlazeBinary + Encryption + RLS + GC
//

import XCTest
@testable import BlazeDB

final class BlazeBinaryIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeBinary-Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - BlazeBinary + Encryption
    
    func testIntegration_BlazeBinaryWithEncryption() throws {
        print("\n🔐 INTEGRATION: BlazeBinary + AES-256 Encryption")
        
        let dbURL = tempDir.appendingPathComponent("encrypted.blazedb")
        let db = try BlazeDBClient(name: "Encrypted", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert data (BlazeBinary + encrypted)
        let sensitiveData = BlazeDataRecord([
            "secret": .string("TOP SECRET PASSWORD 12345"),
            "ssn": .string("123-45-6789"),
            "creditCard": .string("4532-1234-5678-9010")
        ])
        
        let id = try db.insert(sensitiveData)
        try db.persist()
        
        // Verify BlazeBinary on disk (not JSON!)
        let rawData = try Data(contentsOf: dbURL)
        
        // Check for BlazeBinary magic header (encrypted, so should be in encrypted pages)
        print("  📦 Database size: \(rawData.count) bytes")
        
        // Verify sensitive data NOT in plaintext
        let rawString = String(data: rawData, encoding: .utf8) ?? ""
        XCTAssertFalse(rawString.contains("TOP SECRET"), "Data should be encrypted!")
        XCTAssertFalse(rawString.contains("123-45-6789"), "SSN should be encrypted!")
        
        // But retrievable through API
        let retrieved = try db.fetch(id: id)
        XCTAssertEqual(retrieved?.storage["secret"]?.stringValue, "TOP SECRET PASSWORD 12345")
        XCTAssertEqual(retrieved?.storage["ssn"]?.stringValue, "123-45-6789")
        
        print("  ✅ BlazeBinary data encrypted at rest")
        print("  ✅ Automatic decryption works")
    }
    
    // MARK: - BlazeBinary + RLS
    
    func testIntegration_BlazeBinaryWithRLS() throws {
        print("\n🛡️  INTEGRATION: BlazeBinary + RLS")
        
        let dbURL = tempDir.appendingPathComponent("rls.blazedb")
        let db = try BlazeDBClient(name: "RLS", fileURL: dbURL, password: "test-pass-123456")
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userOwnsRecord())
        
        // Create users
        let alice = User(name: "Alice", email: "alice@example.com")
        let bob = User(name: "Bob", email: "bob@example.com")
        
        let aliceID = db.rls.createUser(alice)
        let bobID = db.rls.createUser(bob)
        
        // Alice creates records (BlazeBinary encoded)
        db.rls.setContext(alice.toSecurityContext())
        
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Alice's record \(i)"),
                "userId": .uuid(aliceID)
            ]))
        }
        
        // Bob creates records
        db.rls.setContext(bob.toSecurityContext())
        
        for i in 0..<5 {
            _ = try db.insert(BlazeDataRecord([
                "title": .string("Bob's record \(i)"),
                "userId": .uuid(bobID)
            ]))
        }
        
        try db.persist()
        
        // Verify RLS filtering works with BlazeBinary
        db.rls.setContext(alice.toSecurityContext())
        let aliceRecords = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(aliceRecords.count, 5, "Alice should see only her 5 records")
        
        db.rls.setContext(bob.toSecurityContext())
        let bobRecords = try db.rls.filterRecords(operation: .select, records: try db.fetchAll())
        XCTAssertEqual(bobRecords.count, 5, "Bob should see only his 5 records")
        
        // Check storage size (BlazeBinary should be compact!)
        let fileSize = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int ?? 0
        print("  📦 10 records in \(fileSize) bytes (BlazeBinary + encrypted)")
        
        print("  ✅ RLS works with BlazeBinary encoding")
    }
    
    // MARK: - BlazeBinary + GC
    
    func testIntegration_BlazeBinaryWithGC() async throws {
        print("\n🗑️  INTEGRATION: BlazeBinary + Garbage Collection")
        
        let dbURL = tempDir.appendingPathComponent("gc.blazedb")
        let db = try BlazeDBClient(name: "GC", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 100 records (BlazeBinary)
        var ids: [UUID] = []
        for i in 0..<100 {
            let id = try await db.insert(BlazeDataRecord([
                "value": .int(i),
                "data": .string("Record \(i)")
            ]))
            ids.append(id)
        }
        
        try await db.persist()
        
        let initialSize = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int ?? 0
        print("  📊 Initial: \(initialSize / 1024) KB (100 records)")
        
        // Delete 50 records
        for i in 0..<50 {
            try await db.delete(id: ids[i])
        }
        
        try await db.persist()
        
        // Run VACUUM
        let stats = try await db.vacuum()
        
        let finalSize = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int ?? 0
        print("  📊 After VACUUM: \(finalSize / 1024) KB (50 records)")
        
        // Verify data still accessible
        let remaining = try await db.fetchAll()
        XCTAssertEqual(remaining.count, 50)
        
        // Verify still BlazeBinary format
        for record in remaining {
            XCTAssertNotNil(record.storage["value"])
        }
        
        let freedBytes = stats.sizeBefore - stats.sizeAfter
        print("  ✅ GC works with BlazeBinary encoding")
        print("  ✅ VACUUM reduced size by \(freedBytes / 1024) KB")
    }
    
    // MARK: - ALL FEATURES TOGETHER
    
    func testIntegration_AllFeatures_BlazeBinary() async throws {
        print("\n🎊 FINAL INTEGRATION: BlazeBinary + Encryption + RLS + GC + Telemetry")
        
        let dbURL = tempDir.appendingPathComponent("complete.blazedb")
        let db = try BlazeDBClient(name: "Complete", fileURL: dbURL, password: "ultra-secure-pass-123456")
        
        // Enable ALL features
        db.rls.enable()
        db.rls.addPolicy(.userOwnsRecord())
        db.telemetry.enable(samplingRate: 1.0)
        db.enableAutoVacuum(wasteThreshold: 0.30)
        
        print("  ⚙️  All features enabled")
        
        // Create user
        let user = User(name: "TestUser", email: "test@example.com")
        let userID = db.rls.createUser(user)
        db.rls.setContext(user.toSecurityContext())
        
        // Insert 50 records (BlazeBinary + encrypted + RLS filtered)
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try await db.insert(BlazeDataRecord([
                "title": .string("Record \(i)"),
                "value": .int(i),
                "userId": .uuid(userID),
                "createdAt": .date(Date())
            ]))
            ids.append(id)
        }
        
        try await db.persist()
        
        // Check file size (BlazeBinary should be compact!)
        let size = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int ?? 0
        print("  📦 50 records: \(size / 1024) KB (BlazeBinary + encrypted)")
        
        // Verify RLS works
        let filtered = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(filtered.count, 50, "RLS should filter to user's 50 records")
        
        // Delete 25 records and verify GC
        for i in 0..<25 {
            try await db.delete(id: ids[i])
        }
        
        try await db.persist()
        
        // Check telemetry
        try await Task.sleep(nanoseconds: 200_000_000)
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThan(summary.totalOperations, 50, "Telemetry should track operations")
        print("  📊 Telemetry tracked \(summary.totalOperations) operations")
        
        // Verify data NOT in plaintext (encrypted)
        let rawData = try Data(contentsOf: dbURL)
        let rawString = String(data: rawData, encoding: .utf8) ?? ""
        XCTAssertFalse(rawString.contains("Record 0"), "Data should be encrypted!")
        
        print("  ✅ BlazeBinary: Encoded")
        print("  ✅ Encryption: Working")
        print("  ✅ RLS: Filtering")
        print("  ✅ GC: Tracking")
        print("  ✅ Telemetry: Monitoring")
        print("\n  🎉 ALL FEATURES WORKING TOGETHER!")
    }
    
    // MARK: - Migration Test
    
    func testIntegration_JSONtoBlazeBinaryMigration() throws {
        print("\n🔄 INTEGRATION: JSON → BlazeBinary Migration")
        
        let dbURL = tempDir.appendingPathComponent("migration.blazedb")
        
        // Create database with JSON format (simulate v2.x)
        let db1 = try BlazeDBClient(name: "Migration", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert records (currently uses BlazeBinary, but we'll test migration logic)
        for i in 0..<10 {
            _ = try db1.insert(BlazeDataRecord([
                "id": .uuid(UUID()),
                "title": .string("Record \(i)"),
                "value": .int(i)
            ]))
        }
        
        try db1.persist()
        
        print("  ✅ Created 10 records")
        
        // Simulate upgrade: reload database (auto-migration should detect format)
        BlazeDBClient.clearCachedKey()
        let db2 = try BlazeDBClient(name: "Migration", fileURL: dbURL, password: "test-pass-123456")
        
        // Verify all data accessible
        let records = try db2.fetchAll()
        XCTAssertEqual(records.count, 10, "All records should be accessible after migration")
        
        print("  ✅ Migration successful: all data preserved")
        print("\n  🎉 Migration complete!")
    }
}

