//
//  MigrationVersioningTests.swift
//  BlazeDBIntegrationTests
//
//  Tests database migrations, schema versioning, and backward compatibility
//  Validates smooth upgrades from v1 → v2 → v3 without data loss
//

import XCTest
@testable import BlazeDBCore

final class MigrationVersioningTests: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Migration-\(UUID().uuidString).blazedb")
    }
    
    override func tearDown() {
        guard let dbURL = dbURL else {
            super.tearDown()
            return
        }
        let extensions = ["", "meta", "indexes", "wal", "backup"]
        for ext in extensions {
            let url = ext.isEmpty ? dbURL : dbURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: url)
        }
        super.tearDown()
    }
    
    // MARK: - Schema Evolution Scenarios
    
    /// SCENARIO: App v1.0 → v2.0 → v3.0 (3 generations of schema)
    func testMigration_ThreeGenerationsOfSchema() async throws {
        print("\n🔄 MIGRATION: V1 → V2 → V3 Schema Evolution")
        
        // ═══════════════════════════════════════════════════════
        // V1.0: Minimal schema (2 fields)
        // ═══════════════════════════════════════════════════════
        print("  📦 V1.0: Initial release (minimal schema)")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "MigrationApp", fileURL: dbURL, password: "migration-123")
        
        let v1Records = (0..<100).map { i in
            BlazeDataRecord([
                "title": .string("V1 Bug \(i)"),
                "status": .string("open")
                // Only 2 fields in V1
            ])
        }
        
        _ = try await db!.insertMany(v1Records)
        print("    ✅ V1: 100 bugs with 2 fields (title, status)")
        
        try await db!.persist()
        db = nil
        
        // ═══════════════════════════════════════════════════════
        // V2.0: Add new fields (priority, assignee)
        // ═══════════════════════════════════════════════════════
        print("\n  📦 V2.0: Add priority and assignee fields")
        
        db = try BlazeDBClient(name: "MigrationApp", fileURL: dbURL, password: "migration-123")
        
        // Old V1 records should still be readable
        let v1Data = try await db!.fetchAll()
        XCTAssertEqual(v1Data.count, 100, "V1 data should still be accessible")
        print("    ✅ V1 data accessible: \(v1Data.count) records")
        
        // Insert V2 records with new fields
        let v2Records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("V2 Bug \(i)"),
                "status": .string("open"),
                "priority": .int(i % 5 + 1),  // NEW field!
                "assignee": .string("dev@team.com")  // NEW field!
            ])
        }
        
        _ = try await db!.insertMany(v2Records)
        print("    ✅ V2: 50 bugs with 4 fields (title, status, priority, assignee)")
        
        // Verify: Can query by new field
        let highPriority = try await db!.query()
            .where("priority", equals: .int(5))
            .execute()
        
        print("    ✅ Query by new field: \(highPriority.count) P5 bugs")
        
        try await db!.persist()
        db = nil
        
        // ═══════════════════════════════════════════════════════
        // V3.0: Add tags (array), remove assignee (rename to owner)
        // ═══════════════════════════════════════════════════════
        print("\n  📦 V3.0: Add tags array, rename assignee → owner")
        
        db = try BlazeDBClient(name: "MigrationApp", fileURL: dbURL, password: "migration-123")
        
        // Verify: V1 and V2 data still accessible
        let allData = try await db!.fetchAll()
        XCTAssertEqual(allData.count, 150, "All historical data accessible")
        print("    ✅ All data accessible: 100 V1 + 50 V2 = 150 records")
        
        // Insert V3 records
        let v3Records = (0..<25).map { i in
            BlazeDataRecord([
                "title": .string("V3 Bug \(i)"),
                "status": .string("open"),
                "priority": .int(i % 5 + 1),
                "owner": .string("new-dev@team.com"),  // Renamed from "assignee"
                "tags": .array([  // NEW array field!
                    .string("v3"),
                    .string(["frontend", "backend", "database"].randomElement()!)
                ])
            ])
        }
        
        _ = try await db!.insertMany(v3Records)
        print("    ✅ V3: 25 bugs with 5 fields (title, status, priority, owner, tags)")
        
        // Final verification
        let finalCount = try await db!.count()
        XCTAssertEqual(finalCount, 175, "Should have all 3 versions")
        
        print("\n  📊 FINAL STATE:")
        print("    V1 records: 100 (2 fields)")
        print("    V2 records: 50 (4 fields)")
        print("    V3 records: 25 (5 fields)")
        print("    Total: 175 records across 3 schema versions")
        
        // Verify: Can query across all versions
        let allOpen = try await db!.query()
            .where("status", equals: .string("open"))
            .execute()
        
        print("    ✅ Query across all versions: \(allOpen.count) open bugs")
        
        print("  ✅ VALIDATED: 3 generations of schema coexist perfectly!")
    }
    
    /// SCENARIO: Backward compatibility - old code reading new schema
    func testBackwardCompatibility_OldCodeReadsNewSchema() async throws {
        print("\n🔙 BACKWARD COMPATIBILITY: Old Code Reads New Schema")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "BackCompat", fileURL: dbURL, password: "compat-123")
        
        // New code: Insert record with many fields
        print("  📝 New code: Insert record with 10 fields")
        let newID = try await db!.insert(BlazeDataRecord([
            "title": .string("Modern Bug"),
            "status": .string("open"),
            "priority": .int(5),
            "assignee": .string("alice@team.com"),
            "tags": .array([.string("critical")]),
            "created_at": .date(Date()),
            "updated_at": .date(Date()),
            "version": .int(2),
            "metadata": .dictionary(["key": .string("value")]),
            "description": .string("Full description")
        ]))
        
        print("    ✅ New record created with 10 fields")
        
        // Old code: Read only 2 fields (simulates old app version)
        print("  📖 Old code: Read only 2 fields")
        
        if let record = try await db!.fetch(id: newID) {
            let title = record.storage["title"]?.stringValue
            let status = record.storage["status"]?.stringValue
            
            XCTAssertNotNil(title)
            XCTAssertNotNil(status)
            
            print("    ✅ Old code can read: title='\(title ?? "nil")', status='\(status ?? "nil")'")
            print("    ✅ Extra fields ignored (no crash)")
        }
        
        print("  ✅ VALIDATED: Backward compatibility maintained!")
    }
    
    /// SCENARIO: Forward compatibility - new code reading old schema
    func testForwardCompatibility_NewCodeReadsOldSchema() async throws {
        print("\n🔜 FORWARD COMPATIBILITY: New Code Reads Old Schema")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "ForwardCompat", fileURL: dbURL, password: "compat-123")
        
        // Old code: Insert minimal record
        print("  📝 Old code: Insert minimal record (2 fields)")
        let oldID = try await db!.insert(BlazeDataRecord([
            "title": .string("Old Bug"),
            "status": .string("open")
        ]))
        
        // New code: Read expecting 10 fields (with defaults)
        print("  📖 New code: Read expecting 10 fields")
        
        struct ModernBug: BlazeStorable {
            var id: UUID
            var title: String
            var status: String
            var priority: Int?           // Optional (missing in old)
            var assignee: String?         // Optional
            var tags: [String]?           // Optional
            var created_at: Date?         // Optional
            var description: String?      // Optional
        }
        
        let modernBug = try await db!.fetch(ModernBug.self, id: oldID)
        
        XCTAssertNotNil(modernBug, "Should convert successfully")
        XCTAssertEqual(modernBug?.title, "Old Bug")
        XCTAssertEqual(modernBug?.status, "open")
        XCTAssertNil(modernBug?.priority, "Missing fields should be nil")
        XCTAssertNil(modernBug?.assignee, "Missing fields should be nil")
        
        print("    ✅ Converted successfully:")
        print("      title: '\(modernBug?.title ?? "nil")'")
        print("      status: '\(modernBug?.status ?? "nil")'")
        print("      priority: \(modernBug?.priority as Int? ?? nil as Int?) (nil - OK!)")
        print("      assignee: \(modernBug?.assignee ?? "nil") (nil - OK!)")
        
        print("  ✅ VALIDATED: Forward compatibility with optional fields!")
    }
    
    /// SCENARIO: Zero-downtime migration
    /// Tests: Migrate while app is running
    func testMigration_ZeroDowntime() async throws {
        print("\n🔄 MIGRATION: Zero-Downtime Schema Update")
        
        let db = try BlazeDBClient(name: "ZeroDowntime", fileURL: dbURL, password: "zero-123")
        
        // Phase 1: App v1 running
        print("  📱 Phase 1: App v1 running with old schema")
        
        let v1Records = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Bug \(i)"),
                "assignee": .string("old-field-name")
            ])
        }
        _ = try await db.insertMany(v1Records)
        print("    ✅ 50 V1 records with 'assignee' field")
        
        // Phase 2: Deploy v2 (adds new field, keeps old)
        print("  🚀 Phase 2: Deploy v2 (dual-write)")
        
        // New code writes to BOTH old and new fields
        _ = try await db.insert(BlazeDataRecord([
            "title": .string("Transition Bug"),
            "assignee": .string("bob@team.com"),  // Old field (for v1 clients)
            "owner": .string("bob@team.com")      // New field (for v2 clients)
        ]))
        
        print("    ✅ Dual-write: both 'assignee' and 'owner' fields")
        
        // Phase 3: Background migration (old → new)
        print("  ⚙️  Phase 3: Background migration of old records")
        
        let oldRecords = try await db.fetchAll().filter { record in
            record.storage["owner"] == nil && record.storage["assignee"] != nil
        }
        
        print("    ⚙️  Migrating \(oldRecords.count) old records...")
        
        for record in oldRecords {
            if let id = record.storage["id"]?.uuidValue,
               let assignee = record.storage["assignee"]?.stringValue {
                try await db.update(id: id, with: BlazeDataRecord([
                    "owner": .string(assignee)  // Copy assignee → owner
                ]))
            }
        }
        
        print("    ✅ Migrated \(oldRecords.count) records")
        
        // Verify: All records now have 'owner'
        let withOwner = try await db.fetchAll().filter { $0.storage["owner"] != nil }
        XCTAssertEqual(withOwner.count, 51, "All records should have 'owner' field")
        
        print("  ✅ VALIDATED: Zero-downtime migration successful!")
    }
}

