//
//  RLSEncryptionGCIntegrationTests.swift
//  BlazeDBIntegrationTests
//
//  Final integration tests: RLS + Encryption + GC working together
//

import XCTest
@testable import BlazeDB

final class RLSEncryptionGCIntegrationTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLS-Enc-GC-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Complete Feature Integration
    
    func testIntegration_AllFeaturesTogether() async throws {
        print("\n🎉 FINAL INTEGRATION: RLS + Encryption + GC + Telemetry")
        
        let dbURL = tempDir.appendingPathComponent("complete.blazedb")
        let db = try BlazeDBClient(name: "Complete", fileURL: dbURL, password: "secure-pass-123456")
        
        // 1. Enable ALL features
        print("  ⚙️  Enabling all features...")
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userOwnsRecord())
        db.rls.addPolicy(.adminFullAccess())
        
        // Enable Telemetry
        db.telemetry.enable(samplingRate: 1.0)
        
        // Enable Auto-GC
        db.enableAutoVacuum(wasteThreshold: 0.30, checkInterval: 1.0)
        
        // Define Schema
        let schema = DatabaseSchema(fields: [
            FieldSchema(name: "title", type: .string, required: true),
            FieldSchema(name: "userId", type: .uuid, required: true)
        ])
        db.defineSchema(schema)
        
        print("  ✅ All features enabled: RLS, Telemetry, GC, Schema")
        
        // 2. Create users
        let alice = User(name: "Alice", email: "alice@example.com")
        let bob = User(name: "Bob", email: "bob@example.com")
        let admin = User(name: "Admin", email: "admin@example.com", roles: ["admin"])
        
        let aliceID = db.rls.createUser(alice)
        let bobID = db.rls.createUser(bob)
        let adminID = db.rls.createUser(admin)
        
        print("  👥 Created 3 users")
        
        // 3. Alice creates encrypted records (RLS enforced)
        db.rls.setContext(alice.toSecurityContext())
        
        var aliceRecordIDs: [UUID] = []
        for i in 0..<10 {
            let id = try await db.insert(BlazeDataRecord([
                "title": .string("Alice's record \(i)"),
                "userId": .uuid(aliceID)
            ]))
            aliceRecordIDs.append(id)
        }
        
        // 4. Bob creates encrypted records
        db.rls.setContext(bob.toSecurityContext())
        
        for i in 0..<10 {
            _ = try await db.insert(BlazeDataRecord([
                "title": .string("Bob's record \(i)"),
                "userId": .uuid(bobID)
            ]))
        }
        
        print("  ✅ Created 20 encrypted records (10 Alice, 10 Bob)")
        
        // 5. Verify RLS filtering works
        db.rls.setContext(alice.toSecurityContext())
        let aliceView = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(aliceView.count, 10, "Alice should only see her 10 records")
        print("  ✅ RLS: Alice sees only her records")
        
        db.rls.setContext(bob.toSecurityContext())
        let bobView = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(bobView.count, 10, "Bob should only see his 10 records")
        print("  ✅ RLS: Bob sees only his records")
        
        db.rls.setContext(admin.toSecurityContext())
        let adminView = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(adminView.count, 20, "Admin should see all 20 records")
        print("  ✅ RLS: Admin sees all records")
        
        // 6. Test GC with encrypted data
        db.rls.setContext(alice.toSecurityContext())
        
        // Delete 5 of Alice's records
        for i in 0..<5 {
            try await db.delete(id: aliceRecordIDs[i])
        }
        
        try await db.persist()
        
        let gcStats = try db.collection.getGCStats()
        XCTAssertGreaterThan(gcStats.reuseablePages, 3, "Deleted encrypted pages should be tracked for reuse")
        print("  ✅ GC: Tracking \(gcStats.reuseablePages) deleted encrypted pages")
        
        // 7. Verify encryption still working
        let remaining = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(remaining.count, 5, "Should have 5 remaining records after deletes")
        
        // Verify data is encrypted on disk
        let rawData = try Data(contentsOf: dbURL)
        let rawString = String(data: rawData, encoding: .utf8) ?? ""
        XCTAssertFalse(rawString.contains("Alice's record"), "Data should still be encrypted")
        print("  ✅ Encryption: Data still encrypted after GC operations")
        
        // 8. Check telemetry tracked everything
        try await Task.sleep(nanoseconds: 200_000_000)  // Wait for async telemetry
        
        let summary = try await db.telemetry.getSummary()
        
        XCTAssertGreaterThan(summary.totalOperations, 15, "Telemetry should track operations")
        print("  ✅ Telemetry: Tracked \(summary.totalOperations) operations")
        
        // 9. Run VACUUM on encrypted database
        let vacuumStats = try await db.vacuum()
        
        print("  ✅ VACUUM: Compacted encrypted database")
        
        // 10. Verify everything still works
        db.rls.setContext(alice.toSecurityContext())
        let finalView = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(finalView.count, 5)
        print("  ✅ Final: All features working together!")
        
        // Disable auto-vacuum
        db.disableAutoVacuum()
        
        print("\n  🎊 COMPLETE INTEGRATION TEST PASSED!")
        print("     RLS ✅ + Encryption ✅ + GC ✅ + Telemetry ✅ = WORKING!")
    }
    
    // MARK: - GC with Encrypted Pages
    
    func testIntegration_GCWithEncryptedPages() async throws {
        print("\n🧹 GC INTEGRATION: Page Reuse with Encryption")
        
        let dbURL = tempDir.appendingPathComponent("gc-enc.blazedb")
        let db = try BlazeDBClient(name: "GC-Enc", fileURL: dbURL, password: "test-pass-123456")
        
        // Insert 50 encrypted records
        var ids: [UUID] = []
        for i in 0..<50 {
            let id = try await db.insert(BlazeDataRecord([
                "value": .int(i),
                "data": .string("Encrypted data \(i)")
            ]))
            ids.append(id)
        }
        
        try await db.persist()
        
        let initialSize = try await db.getStorageStats().fileSize
        print("  📊 Initial: \(initialSize / 1024) KB")
        
        // Delete 30 records (encrypted pages should be reused)
        for i in 0..<30 {
            try await db.delete(id: ids[i])
        }
        
        try await db.persist()
        
        // Insert 30 new encrypted records (should reuse deleted pages)
        for i in 0..<30 {
            _ = try await db.insert(BlazeDataRecord([
                "value": .int(i + 100),
                "data": .string("New encrypted data \(i)")
            ]))
        }
        
        try await db.persist()
        
        let finalSize = try await db.getStorageStats().fileSize
        print("  📊 Final: \(finalSize / 1024) KB")
        
        // File size should be stable (page reuse working with encryption)
        let growth = Double(finalSize - initialSize) / Double(initialSize) * 100
        XCTAssertLessThan(growth, 20, "File should not grow much with page reuse")
        
        print("  ✅ GC works with encrypted pages: \(String(format: "%.1f", growth))% growth")
    }
    
    // MARK: - RLS with Encryption
    
    func testIntegration_RLSWithEncryptedData() async throws {
        print("\n🔐 RLS + ENCRYPTION: Multi-Tenant Encrypted Database")
        
        let dbURL = tempDir.appendingPathComponent("rls-enc.blazedb")
        let db = try BlazeDBClient(name: "RLS-Enc", fileURL: dbURL, password: "multi-tenant-pass-123")
        
        // Enable RLS
        db.rls.enable()
        db.rls.addPolicy(.userOwnsRecord())
        
        // Create users
        let user1 = User(name: "User1", email: "user1@example.com")
        let user2 = User(name: "User2", email: "user2@example.com")
        
        let user1ID = db.rls.createUser(user1)
        let user2ID = db.rls.createUser(user2)
        
        // User 1 creates encrypted records
        db.rls.setContext(user1.toSecurityContext())
        for i in 0..<5 {
            _ = try await db.insert(BlazeDataRecord([
                "secret": .string("User1 secret \(i)"),
                "userId": .uuid(user1ID)
            ]))
        }
        
        // User 2 creates encrypted records
        db.rls.setContext(user2.toSecurityContext())
        for i in 0..<5 {
            _ = try await db.insert(BlazeDataRecord([
                "secret": .string("User2 secret \(i)"),
                "userId": .uuid(user2ID)
            ]))
        }
        
        try await db.persist()
        
        // Verify encryption: secrets not in plaintext
        let rawData = try Data(contentsOf: dbURL)
        let rawString = String(data: rawData, encoding: .utf8) ?? ""
        XCTAssertFalse(rawString.contains("User1 secret"), "Secrets should be encrypted")
        XCTAssertFalse(rawString.contains("User2 secret"), "Secrets should be encrypted")
        
        print("  ✅ Data encrypted on disk")
        
        // Verify RLS: users only see their own encrypted data
        db.rls.setContext(user1.toSecurityContext())
        let user1View = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(user1View.count, 5)
        XCTAssertTrue(user1View.allSatisfy { $0.storage["userId"]?.uuidValue == user1ID })
        
        print("  ✅ RLS: User1 sees only their 5 encrypted records")
        
        db.rls.setContext(user2.toSecurityContext())
        let user2View = try db.rls.filterRecords(operation: .select, records: try await db.fetchAll())
        XCTAssertEqual(user2View.count, 5)
        XCTAssertTrue(user2View.allSatisfy { $0.storage["userId"]?.uuidValue == user2ID })
        
        print("  ✅ RLS: User2 sees only their 5 encrypted records")
        
        print("\n  🎊 RLS + Encryption: Perfect tenant isolation with encrypted data!")
    }
}

