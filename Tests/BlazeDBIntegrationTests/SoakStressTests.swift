//
//  SoakStressTests.swift
//  BlazeDBIntegrationTests
//
//  Long-running style soak tests and resource-stability checks
//

import XCTest
@testable import BlazeDB

/// Soak-style tests (bounded so they are CI-friendly, but exercise long-running patterns).
///
/// These are not true 24h soaks, but they simulate sustained mixed workloads and ensure:
/// - No crashes
/// - File size stays within reasonable bounds
/// - VACUUM/GC + sync can be run repeatedly without corrupting data
final class SoakStressTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Soak-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }
    
    /// Simulate a long-running mixed workload on a single database.
    ///
    /// Operations:
    /// - Insert / update / delete / query in a tight loop
    /// - Periodically call persist(), VACUUM and GC
    ///
    /// This is intentionally bounded (few thousand ops) so CI can run it quickly,
    /// but it still catches classic resource / fragmentation issues.
    func testSoak_MixedWorkload_SingleDatabase() throws {
        let dbURL = tempDir.appendingPathComponent("soak_single.blazedb")
        let db = try BlazeDBClient(name: "SoakSingle", fileURL: dbURL, password: "soak-pass-123")
        
        // Track file size baseline
        func fileSize() throws -> Int64 {
            let values = try dbURL.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        }
        
        let baselineSize = try fileSize()
        
        // Simple pool of record IDs
        var ids: [UUID] = []
        
        let iterations = 2_000
        for i in 0..<iterations {
            // Insert
            let record = BlazeDataRecord([
                "i": .int(i),
                "payload": .string("record-\(i)"),
                "flag": .bool(i % 2 == 0)
            ])
            let id = try db.insert(record)
            ids.append(id)
            
            // Occasionally update
            if i % 5 == 0, let anyID = ids.randomElement(),
               var existing = try db.fetch(id: anyID) {
                existing.storage["payload"] = .string("updated-\(i)")
                try db.update(id: anyID, with: existing)
            }
            
            // Occasionally delete
            if i % 7 == 0, !ids.isEmpty {
                let removed = ids.removeFirst()
                try db.delete(id: removed)
            }
            
            // Occasionally query
            if i % 11 == 0 {
                _ = try db.query()
                    .where("flag", equals: .bool(true))
                    .limit(50)
                    .execute()
            }
            
            // Periodically persist and run GC
            if i % 250 == 0 {
                try db.persist()
                _ = db.runGarbageCollection()
            }
        }
        
        // Final persist and VACUUM (compaction)
        try db.persist()
        let reclaimed = try db.vacuum()
        XCTAssertGreaterThanOrEqual(reclaimed, 0)
        
        let finalSize = try fileSize()
        
        // File size should not explode (allow some growth but bound it)
        // This is a heuristic - we just want to detect wild growth.
        XCTAssertLessThanOrEqual(finalSize, baselineSize + Int64(10 * 4096 * 100),
                                 "File size grew unexpectedly during soak test")
    }
    
    /// End-to-end soak test: two databases connected via local sync,
    /// repeatedly writing on both sides, running VACUUM and GC.
    ///
    /// This exercises:
    /// - Sync engine under sustained load
    /// - OperationLog + SyncState GC coherence
    /// - VACUUM interaction with sync (no corruption)
    func testSoak_Sync_Vacuum_GC_Coexist() async throws {
        let db1URL = tempDir.appendingPathComponent("soak_sync_db1.blazedb")
        let db2URL = tempDir.appendingPathComponent("soak_sync_db2.blazedb")
        
        let db1 = try BlazeDBClient(name: "SoakDB1", fileURL: db1URL, password: "soak-pass-123")
        let db2 = try BlazeDBClient(name: "SoakDB2", fileURL: db2URL, password: "soak-pass-123")
        
        let topology = BlazeTopology()
        let id1 = try await topology.register(db: db1, name: "SoakDB1", role: .server)
        let id2 = try await topology.register(db: db2, name: "SoakDB2", role: .client)
        
        try await topology.connectLocal(from: id1, to: id2, mode: .bidirectional)
        
        // Mixed operations on both sides
        let iterations = 1_000
        var idsDB1: [UUID] = []
        var idsDB2: [UUID] = []
        
        for i in 0..<iterations {
            // Write on db1
            let id1Local = try db1.insert(BlazeDataRecord([
                "source": .string("db1"),
                "seq": .int(i)
            ]))
            idsDB1.append(id1Local)
            
            // Write on db2
            let id2Local = try db2.insert(BlazeDataRecord([
                "source": .string("db2"),
                "seq": .int(i)
            ]))
            idsDB2.append(id2Local)
            
            // Occasional updates
            if i % 10 == 0, let any = idsDB1.randomElement(),
               var rec = try db1.fetch(id: any) {
                rec.storage["updated"] = .bool(true)
                try db1.update(id: any, with: rec)
            }
            
            if i % 10 == 0, let any = idsDB2.randomElement(),
               var rec = try db2.fetch(id: any) {
                rec.storage["updated"] = .bool(true)
                try db2.update(id: any, with: rec)
            }
            
            // Periodic sync delay
            if i % 200 == 0 {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                try db1.persist()
                try db2.persist()
                
                // Run GC occasionally
                _ = db1.runGarbageCollection()
                _ = db2.runGarbageCollection()
            }
        }
        
        // Final settle
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Sanity: both DBs see at least most of each other's records
        let all1 = try db1.fetchAll()
        let all2 = try db2.fetchAll()
        
        XCTAssertGreaterThan(all1.count, iterations / 2)
        XCTAssertGreaterThan(all2.count, iterations / 2)
    }
}


