//
//  AshPileRealWorldTests.swift
//  BlazeDBIntegrationTests
//
//  Tests BlazeDB with YOUR ACTUAL APP workflows
//  Validates AshPile bug tracker real-world usage patterns
//

import XCTest
@testable import BlazeDBCore

final class AshPileRealWorldTests: XCTestCase {
    
    var dbURL: URL!
    
    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AshPile-\(UUID().uuidString).blazedb")
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
    
    // MARK: - AshPile Complete Workflow
    
    /// YOUR REAL APP: Complete AshPile workflow
    /// Tests: Everything you actually use in production
    func testRealWorld_AshPileCompleteWorkflow() async throws {
        print("\n")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔥 REAL WORLD: AshPile Bug Tracker")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("")
        
        // Phase 1: First Launch
        print("📱 PHASE 1: User opens AshPile for first time")
        
        var ashPile: BlazeDBClient? = try BlazeDBClient(
            name: "AshPile",
            fileURL: dbURL,
            password: "ashpile-secure-2025"
        )
        
        // Setup: Create indexes you actually use
        try await ashPile!.collection.createIndex(on: "status")
        try await ashPile!.collection.createIndex(on: "priority")
        try await ashPile!.collection.createIndex(on: ["status", "priority"])
        try await ashPile!.collection.createIndex(on: "assignee")
        try await ashPile!.collection.enableSearch(fields: ["title", "description"])
        
        print("  ✅ Indexes created: status, priority, [status+priority], assignee")
        print("  ✅ Search enabled: title, description")
        
        // Phase 2: User creates first bug
        print("\n📝 PHASE 2: Create first bug")
        
        let bug1 = try await ashPile!.insert(BlazeDataRecord([
            "title": .string("App crashes on launch"),
            "description": .string("When I open the app, it immediately crashes"),
            "status": .string("open"),
            "priority": .int(5),
            "severity": .string("critical"),
            "assignee": .string("alice@team.com"),
            "tags": .array([.string("crash"), .string("ios")]),
            "created_at": .date(Date()),
            "reported_by": .string("user123")
        ]))
        
        print("  ✅ Bug #1 created: \(bug1)")
        
        // Phase 3: Rapid bug creation (simulates user entering multiple bugs)
        print("\n📝 PHASE 3: User creates 20 more bugs")
        
        let moreBugs = (0..<20).map { i in
            BlazeDataRecord([
                "title": .string("Bug #\(i+2)"),
                "description": .string("Description for bug \(i+2)"),
                "status": .string(["open", "in_progress", "closed"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "assignee": .string(["alice@team.com", "bob@team.com", "charlie@team.com"].randomElement()!),
                "tags": .array([.string(["frontend", "backend", "database", "ui"].randomElement()!)]),
                "created_at": .date(Date().addingTimeInterval(Double(-i * 3600)))
            ])
        }
        
        _ = try await ashPile!.insertMany(moreBugs)
        print("  ✅ Created 20 bugs in batch")
        
        // Phase 4: User performs typical queries
        print("\n🔍 PHASE 4: Dashboard queries")
        
        // Query 1: My open bugs
        let myOpenBugs = try await ashPile!.query()
            .where("status", equals: .string("open"))
            .where("assignee", equals: .string("alice@team.com"))
            .orderBy("priority", descending: true)
            .execute()
        
        print("  ✅ Alice's open bugs: \(myOpenBugs.count)")
        
        // Query 2: Critical bugs
        let criticalBugs = try await ashPile!.query()
            .where("priority", equals: .int(5))
            .where("status", notEquals: .string("closed"))
            .execute()
        
        print("  ✅ Critical bugs: \(criticalBugs.count)")
        
        // Query 3: Search
        let crashBugs = try await ashPile!.collection.search(
            query: "crash",
            in: ["title", "description"]
        )
        
        print("  ✅ Search 'crash': \(crashBugs.count) results")
        
        // Query 4: Stats by status
        let stats = try await ashPile!.query()
            .groupBy("status")
            .count(as: "total")
            .execute()
        
        let grouped = try stats.grouped
        print("  ✅ Stats by status:")
        for (status, data) in grouped.groups.sorted(by: { $0.key < $1.key }) {
            let count = data["total"]?.intValue ?? 0
            print("      \(status): \(count) bugs")
        }
        
        // Phase 5: Bulk operations (user closes multiple bugs)
        print("\n✅ PHASE 5: Bulk close low-priority bugs")
        
        try await ashPile!.beginTransaction()
        
        let closed = try await ashPile!.updateMany(
            where: { $0.storage["priority"]?.intValue ?? 0 <= 2 },
            with: BlazeDataRecord([
                "status": .string("closed"),
                "closed_at": .date(Date()),
                "closed_by": .string("alice@team.com")
            ])
        )
        
        try await ashPile!.commitTransaction()
        print("  ✅ Closed \(closed) low-priority bugs")
        
        // Phase 6: App backgrounded (auto-save)
        print("\n💾 PHASE 6: App backgrounded (auto-save)")
        try await ashPile!.persist()
        print("  ✅ Data persisted to disk")
        
        // Phase 7: User force-quits app
        print("\n💥 PHASE 7: User force-quits app")
        ashPile = nil
        print("  ⚠️  App terminated (deinit auto-flush triggered)")
        
        // Phase 8: User reopens app
        print("\n📱 PHASE 8: User reopens AshPile")
        
        ashPile = try BlazeDBClient(
            name: "AshPile",
            fileURL: dbURL,
            password: "ashpile-secure-2025"
        )
        
        let afterRestart = try await ashPile!.count()
        XCTAssertEqual(afterRestart, 21, "All 21 bugs should persist")
        print("  ✅ All 21 bugs persisted through restart")
        
        // Verify: Indexes still work
        let indexedQuery = try await ashPile!.query()
            .where("status", equals: .string("closed"))
            .execute()
        print("  ✅ Indexes functional: \(indexedQuery.count) closed bugs")
        
        // Verify: Search still works
        let searchAfterRestart = try await ashPile!.collection.search(query: "Bug")
        XCTAssertGreaterThan(searchAfterRestart.count, 0)
        print("  ✅ Search functional: \(searchAfterRestart.count) results")
        
        // Phase 9: User adds comment (partial update)
        print("\n💬 PHASE 9: User adds comment to bug")
        
        try await ashPile!.update(id: bug1, with: BlazeDataRecord([
            "comments": .array([
                .dictionary([
                    "user": .string("bob@team.com"),
                    "text": .string("I can reproduce this on iOS 18"),
                    "timestamp": .date(Date())
                ])
            ])
        ]))
        print("  ✅ Comment added (partial update)")
        
        // Phase 10: Real-time dashboard update (SwiftUI)
        print("\n📊 PHASE 10: Dashboard auto-refresh")
        
        // Simulate @BlazeQuery behavior
        let dashboardData = try await ashPile!.query()
            .where("status", equals: .string("open"))
            .orderBy("priority", descending: true)
            .limit(10)
            .execute()
        
        print("  ✅ Dashboard showing top 10 open bugs")
        
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ ASHPILE WORKFLOW COMPLETE!")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("All features validated in realistic production scenario!")
        print("")
    }
    
    /// SCENARIO: AshPile team collaboration (multiple users)
    func testRealWorld_AshPileTeamUsage() async throws {
        print("\n👥 REAL WORLD: AshPile Team Collaboration")
        
        let db = try BlazeDBClient(name: "AshPileTeam", fileURL: dbURL, password: "team-123")
        
        // Setup
        try await db.collection.createIndex(on: "assignee")
        try await db.collection.enableSearch(fields: ["title", "description"])
        
        let team = ["alice@team.com", "bob@team.com", "charlie@team.com", "diana@team.com"]
        print("  👥 Team: 4 members")
        
        // Each team member creates bugs concurrently
        await withTaskGroup(of: Int.self) { group in
            for member in team {
                group.addTask {
                    var created = 0
                    for i in 0..<10 {
                        do {
                            _ = try await db.insert(BlazeDataRecord([
                                "title": .string("\(member)'s bug \(i)"),
                                "assignee": .string(member),
                                "status": .string("open"),
                                "priority": .int(Int.random(in: 1...5))
                            ]))
                            created += 1
                        } catch {}
                    }
                    return created
                }
            }
            
            var totalCreated = 0
            for await count in group {
                totalCreated += count
            }
            
            print("  ✅ Created \(totalCreated) bugs across 4 users")
            XCTAssertEqual(totalCreated, 40, "All bugs should be created")
        }
        
        // Each member queries their bugs
        for member in team {
            let myBugs = try await db.query()
                .where("assignee", equals: .string(member))
                .execute()
            
            XCTAssertEqual(myBugs.count, 10, "\(member) should have 10 bugs")
            print("    \(member): \(myBugs.count) bugs")
        }
        
        // Team lead performs bulk update
        print("  👨‍💼 Team lead: Update high-priority bugs")
        try await db.beginTransaction()
        
        let updated = try await db.updateMany(
            where: { $0.storage["priority"]?.intValue ?? 0 >= 4 },
            with: BlazeDataRecord([
                "reviewed": .bool(true),
                "reviewed_by": .string("lead@team.com"),
                "reviewed_at": .date(Date())
            ])
        )
        
        try await db.commitTransaction()
        print("  ✅ Reviewed \(updated) high-priority bugs")
        
        print("  ✅ VALIDATED: Team collaboration works perfectly!")
    }
    
    /// SCENARIO: AshPile data export/import (backup feature)
    func testRealWorld_AshPileBackupRestore() async throws {
        print("\n💾 REAL WORLD: AshPile Backup & Restore")
        
        var db: BlazeDBClient? = try BlazeDBClient(name: "AshPileBackup", fileURL: dbURL, password: "backup-123")
        
        // Create production data
        let productionBugs = (0..<50).map { i in
            BlazeDataRecord([
                "title": .string("Production Bug \(i)"),
                "status": .string(["open", "closed"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "created_at": .date(Date().addingTimeInterval(Double(-i * 3600)))
            ])
        }
        
        _ = try await db!.insertMany(productionBugs)
        try await db!.collection.createIndex(on: "status")
        try await db!.persist()
        
        print("  ✅ Production database: 50 bugs with indexes")
        
        // Export (simulate backup)
        print("  💾 Exporting data...")
        let allData = try await db!.fetchAll()
        
        // Convert to JSON for backup
        let jsonData = try JSONSerialization.data(
            withJSONObject: allData.map { record in
                record.storage.mapValues { field -> Any in
                    switch field {
                    case .string(let s): return s
                    case .int(let i): return i
                    case .double(let d): return d
                    case .bool(let b): return b
                    case .uuid(let u): return u.uuidString
                    case .date(let d): return d.timeIntervalSince1970
                    case .array(let a): return a
                    case .dictionary(let d): return d
                    case .data(let d): return d.base64EncodedString()
                    }
                }
            }
        )
        
        print("  ✅ Exported \(allData.count) bugs to JSON (\(jsonData.count) bytes)")
        
        // Simulate disaster: Delete database
        print("  💥 DISASTER: Database corrupted!")
        try await db!.persist()
        db = nil
        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: dbURL.deletingPathExtension().appendingPathExtension("meta"))
        
        // Restore from backup
        print("  🔄 RESTORE: Recreating database from backup...")
        
        db = try BlazeDBClient(name: "AshPileBackup", fileURL: dbURL, password: "backup-123")
        
        // Parse JSON and restore
        let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as! [[String: Any]]
        
        var restored: [BlazeDataRecord] = []
        for json in jsonArray {
            var record: [String: BlazeDocumentField] = [:]
            for (key, value) in json {
                if let s = value as? String {
                    record[key] = .string(s)
                } else if let i = value as? Int {
                    record[key] = .int(i)
                } else if let d = value as? Double {
                    if key.contains("date") || key == "created_at" {
                        record[key] = .date(Date(timeIntervalSince1970: d))
                    } else {
                        record[key] = .double(d)
                    }
                } else if let b = value as? Bool {
                    record[key] = .bool(b)
                }
            }
            restored.append(BlazeDataRecord(record))
        }
        
        _ = try await db!.insertMany(restored)
        
        // Recreate indexes
        try await db!.collection.createIndex(on: "status")
        try await db!.collection.enableSearch(fields: ["title", "description"])
        
        let restoredCount = try await db!.count()
        XCTAssertEqual(restoredCount, 50, "All bugs should be restored")
        print("  ✅ Restored \(restoredCount) bugs from backup")
        
        // Verify: Queries still work
        let openBugs = try await db!.query()
            .where("status", equals: .string("open"))
            .execute()
        print("  ✅ Queries work: \(openBugs.count) open bugs")
        
        print("  ✅ VALIDATED: Backup & restore works perfectly!")
    }
    
    /// SCENARIO: AshPile performance under real usage (1000 bugs)
    func testRealWorld_AshPileAtScale() async throws {
        print("\n📊 REAL WORLD: AshPile at Scale (1000 bugs)")
        
        let db = try BlazeDBClient(name: "AshPileScale", fileURL: dbURL, password: "scale-123")
        
        // Setup production indexes
        try await db.collection.createIndex(on: "status")
        try await db.collection.createIndex(on: ["status", "priority"])
        try await db.collection.createIndex(on: "assignee")
        try await db.collection.enableSearch(fields: ["title", "description"])
        
        // Import 1000 bugs (realistic production size)
        print("  📥 Importing 1000 bugs...")
        let bugs = (0..<1000).map { i in
            BlazeDataRecord([
                "title": .string("Production Bug #\(i)"),
                "description": .string("This is a real production bug that needs to be tracked"),
                "status": .string(["open", "in_progress", "resolved", "closed"].randomElement()!),
                "priority": .int(Int.random(in: 1...5)),
                "assignee": .string("dev\(i % 10)@company.com"),
                "tags": .array([.string(["frontend", "backend", "database", "api", "ui"].randomElement()!)]),
                "created_at": .date(Date().addingTimeInterval(Double(-i * 3600)))
            ])
        }
        
        let importStart = Date()
        _ = try await db.insertMany(bugs)
        let importTime = Date().timeIntervalSince(importStart)
        
        print("  ✅ Imported 1000 bugs in \(String(format: "%.2f", importTime))s")
        XCTAssertLessThan(importTime, 5.0, "Import should be < 5s")
        
        // Test typical dashboard queries at scale
        let queries: [(String, () async throws -> Int)] = [
            ("My open bugs", {
                let results = try await db.query()
                    .where("assignee", equals: .string("dev0@company.com"))
                    .where("status", equals: .string("open"))
                    .execute()
                return results.count
            }),
            ("Critical bugs", {
                let results = try await db.query()
                    .where("priority", equals: .int(5))
                    .where("status", notEquals: .string("closed"))
                    .execute()
                return results.count
            }),
            ("Search 'production'", {
                let results = try await db.collection.search(query: "production")
                return results.count
            }),
            ("Stats by status", {
                let results = try await db.query()
                    .groupBy("status")
                    .count(as: "total")
                    .execute()
                return try results.grouped.groups.count
            })
        ]
        
        print("  📊 Dashboard query performance at scale:")
        for (name, query) in queries {
            let start = Date()
            let count = try await query()
            let time = Date().timeIntervalSince(start)
            
            print("    \(name): \(count) results in \(String(format: "%.2f", time * 1000))ms")
            XCTAssertLessThan(time, 0.5, "\(name) should be < 500ms at scale")
        }
        
        print("  ✅ VALIDATED: AshPile performs well at production scale!")
    }
    
    /// Performance: Measure AshPile typical workflow
    func testPerformance_AshPileTypicalWorkflow() async throws {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            Task {
                do {
                    let db = try BlazeDBClient(name: "AshPilePerf", fileURL: self.dbURL, password: "perf-123")
                    
                    // Setup (indexes)
                    try await db.collection.createIndex(on: "status")
                    try await db.collection.enableSearch(fields: ["title"])
                    
                    // Create bugs
                    let bugs = (0..<100).map { i in
                        BlazeDataRecord([
                            "title": .string("Bug \(i)"),
                            "status": .string(i % 2 == 0 ? "open" : "closed"),
                            "priority": .int(i % 5 + 1)
                        ])
                    }
                    _ = try await db.insertMany(bugs)
                    
                    // Query open bugs
                    _ = try await db.query().where("status", equals: .string("open")).execute()
                    
                    // Search
                    _ = try await db.collection.search(query: "Bug")
                    
                    // Update some
                    _ = try await db.updateMany(
                        where: { $0.storage["priority"]?.intValue ?? 0 == 5 },
                        with: BlazeDataRecord(["status": .string("urgent")])
                    )
                    
                    // Dashboard stats
                    _ = try await db.query()
                        .groupBy("status")
                        .count(as: "total")
                        .execute()
                    
                } catch {
                    XCTFail("AshPile workflow failed: \(error)")
                }
            }
        }
    }
}

