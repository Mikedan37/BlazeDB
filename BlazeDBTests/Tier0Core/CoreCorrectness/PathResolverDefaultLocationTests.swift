//
//  PathResolverDefaultLocationTests.swift
//  BlazeDB_Tier0
//
//  Regression: default DB and telemetry paths must use sandbox-safe locations on Apple
//  (Application Support + BlazeDB/), never homeDirectoryForCurrentUser (unavailable on iOS).
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class PathResolverDefaultLocationTests: XCTestCase {

    /// Mirrors `TelemetryConfiguration.init(metricsURL: nil)` layout; Telemetry sources are excluded
    /// from the SwiftPM `BlazeDBCore` product, so this string must stay aligned with that type.
    private static func defaultMetricsURLAsTelemetryWould() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("BlazeDB", isDirectory: true)
            .appendingPathComponent("metrics", isDirectory: true)
            .appendingPathComponent("telemetry.blazedb")
    }

    #if os(macOS) || os(iOS)
    func testDefaultDatabaseDirectory_Apple_UsesApplicationSupportBlazeDB() throws {
        let dir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertEqual(dir.lastPathComponent, "BlazeDB", "Last path component must be BlazeDB")
        let path = dir.path
        XCTAssertTrue(
            path.contains("Application Support"),
            "Expected Library/Application Support on Apple platforms; got \(path)"
        )
    }

    func testDefaultMetricsPath_AlignedWithPathResolverBlazeDBRoot() throws {
        let dbRoot = try PathResolver.defaultDatabaseDirectory()
        let metrics = Self.defaultMetricsURLAsTelemetryWould()
        let metricsBlazeRoot = metrics
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        XCTAssertEqual(
            metricsBlazeRoot.path,
            dbRoot.path,
            "Default metrics DB must live under the same BlazeDB/ directory as PathResolver"
        )
        XCTAssertEqual(metrics.lastPathComponent, "telemetry.blazedb")
        XCTAssertEqual(metrics.deletingLastPathComponent().lastPathComponent, "metrics")
    }
    #elseif os(Linux)
    func testDefaultDatabaseDirectory_Linux_UsesLocalShareBlazedb() throws {
        let dir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertEqual(dir.lastPathComponent, "blazedb")
        XCTAssertTrue(dir.path.contains(".local/share/blazedb"), dir.path)
    }
    #else
    func testDefaultDatabaseDirectory_Fallback_UsesTemporaryBlazeDB() throws {
        let dir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertEqual(dir.lastPathComponent, "BlazeDB")
        let tmp = FileManager.default.temporaryDirectory.path
        XCTAssertTrue(
            dir.path.hasPrefix(tmp) || dir.path.contains(tmp),
            "Expected fallback under temporaryDirectory; got \(dir.path)"
        )
    }
    #endif
}
