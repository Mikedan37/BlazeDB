//
//  VacuumPerformanceTests.swift
//  BlazeDBTests
//
//  Lightweight VACUUM and storage stats performance checks.
//  Lives in Tier3Heavy so benchmark-style behavior does not affect core Tier1 correctness gates.
//

import XCTest
@testable import BlazeDBCore

final class VacuumPerformanceTests: XCTestCase {

    func testVacuumPerformance_Smoke() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VacuumPerf-\(UUID().uuidString).blazedb")
        let db = try BlazeDBClient(name: "VacuumPerf", fileURL: tempURL, password: "SecureTestDB-456!")

        // Prepare workload
        let ids = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })
        for i in 0..<50 {
            try await db.delete(id: ids[i])
        }

        let start = Date()
        _ = try await db.vacuum()
        let duration = Date().timeIntervalSince(start)

        // Sanity bound: VACUUM for this tiny workload should be sub-second.
        XCTAssertLessThan(duration, 1.0, "VACUUM smoke run should complete quickly for 100 records")
    }

    func testStorageStatsPerformance_Smoke() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatsPerf-\(UUID().uuidString).blazedb")
        let db = try BlazeDBClient(name: "StatsPerf", fileURL: tempURL, password: "SecureTestDB-456!")

        // Insert some data to make stats meaningful
        _ = try await db.insertMany((0..<100).map { i in BlazeDataRecord(["value": .int(i)]) })

        let start = Date()
        _ = try await db.getStorageStats()
        let duration = Date().timeIntervalSince(start)

        // Sanity bound: stats call should be very fast at this scale.
        XCTAssertLessThan(duration, 0.5, "getStorageStats() smoke run should complete quickly for 100 records")
    }
}

