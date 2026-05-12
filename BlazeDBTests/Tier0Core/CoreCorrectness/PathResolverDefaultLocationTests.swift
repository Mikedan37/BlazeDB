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
    /// from the SwiftPM `BlazeDBCore` product, so this helper verifies the same root selection.
    private static func defaultMetricsURLAsTelemetryWould() -> URL {
        let base = (try? PathResolver.defaultDatabaseDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("BlazeDB", isDirectory: true)
        return base
            .appendingPathComponent("metrics", isDirectory: true)
            .appendingPathComponent("telemetry.blazedb")
    }

    #if !os(Windows)
    private static func assertPrivateDirectoryPermissions(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber, file: file, line: line).intValue
        XCTAssertEqual(permissions & 0o077, 0, "Default database root must not be group/world accessible", file: file, line: line)
    }

    func testDefaultDatabaseDirectory_RepairsGroupWorldAccessiblePermissions() throws {
        let fileManager = FileManager.default
        let dir = try PathResolver.defaultDatabaseDirectory()
        let originalPermissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber
        )
        defer {
            try? fileManager.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: dir.path)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        _ = try PathResolver.defaultDatabaseDirectory()

        try Self.assertPrivateDirectoryPermissions(dir)
    }
    #endif

    #if os(macOS) || os(iOS)
    func testDefaultDatabaseDirectory_Apple_UsesApplicationSupportBlazeDB() throws {
        let dir = try PathResolver.defaultDatabaseDirectory()
        XCTAssertEqual(dir.lastPathComponent, "BlazeDB", "Last path component must be BlazeDB")
        let path = dir.path
        XCTAssertTrue(
            path.contains("Application Support"),
            "Expected Library/Application Support on Apple platforms; got \(path)"
        )
        try Self.assertPrivateDirectoryPermissions(dir)
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
        try Self.assertPrivateDirectoryPermissions(dir)
    }

    func testConvenienceDefaultDatabaseURL_Linux_MatchesPathResolverRoot() throws {
        let dir = try PathResolver.defaultDatabaseDirectory()
        let dbURL = try BlazeDBClient.defaultDatabaseURL(for: "myapp")

        XCTAssertEqual(dbURL.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(dbURL.lastPathComponent, "myapp.blazedb")
    }

    func testConvenienceDefaultDatabaseURL_Linux_PreservesExistingLegacyApplicationSupportFile() throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw XCTSkip("Application Support directory is unavailable")
        }

        let name = "legacy-\(UUID().uuidString)"
        let legacyDirectory = applicationSupport.appendingPathComponent("BlazeDB", isDirectory: true)
        let legacyURL = legacyDirectory.appendingPathComponent("\(name).blazedb")
        let canonicalURL = try PathResolver.defaultDatabaseDirectory()
            .appendingPathComponent("\(name).blazedb")

        try fileManager.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: legacyURL.path, contents: Data("legacy".utf8))
        defer {
            try? fileManager.removeItem(at: legacyURL)
            try? fileManager.removeItem(at: canonicalURL)
        }

        XCTAssertFalse(fileManager.fileExists(atPath: canonicalURL.path))
        let resolved = try BlazeDBClient.defaultDatabaseURL(for: name)
        XCTAssertEqual(resolved.standardizedFileURL, legacyURL.standardizedFileURL)
    }

    func testOpenNamed_Linux_PreservesExistingLegacyApplicationSupportDatabase() throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw XCTSkip("Application Support directory is unavailable")
        }

        let name = "legacy-open-\(UUID().uuidString)"
        let password = "SecureLegacy-123!"
        let legacyDirectory = applicationSupport.appendingPathComponent("BlazeDB", isDirectory: true)
        let legacyURL = legacyDirectory.appendingPathComponent("\(name).blazedb")
        let canonicalURL = try PathResolver.defaultDatabaseDirectory()
            .appendingPathComponent("\(name).blazedb")

        func databaseArtifacts(for url: URL) -> [URL] {
            [
                url,
                url.deletingPathExtension().appendingPathExtension("meta"),
                url.deletingPathExtension().appendingPathExtension("salt"),
                url.deletingPathExtension().appendingPathExtension("wal")
            ]
        }

        try fileManager.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        defer {
            for artifact in databaseArtifacts(for: legacyURL) + databaseArtifacts(for: canonicalURL) {
                try? fileManager.removeItem(at: artifact)
            }
        }

        let seeded = try BlazeDBClient(name: name, fileURL: legacyURL, password: password)
        let recordID = try seeded.insert(BlazeDataRecord(["marker": .string("legacy")]))
        try seeded.close()

        XCTAssertFalse(fileManager.fileExists(atPath: canonicalURL.path))

        let reopened = try BlazeDBClient.open(named: name, password: password)
        defer { try? reopened.close() }

        XCTAssertEqual(reopened.fileURL.standardizedFileURL, legacyURL.standardizedFileURL)
        XCTAssertNotNil(try reopened.fetch(id: recordID), "open(named:) must read the existing legacy database")
        XCTAssertFalse(fileManager.fileExists(atPath: canonicalURL.path))
    }

    func testDefaultMetricsPath_Linux_AlignedWithPathResolverBlazedbRoot() throws {
        let dbRoot = try PathResolver.defaultDatabaseDirectory()
        let metrics = Self.defaultMetricsURLAsTelemetryWould()
        let metricsBlazeRoot = metrics
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        XCTAssertEqual(
            metricsBlazeRoot.path,
            dbRoot.path,
            "Default metrics DB must live under the same blazedb/ directory as PathResolver"
        )
        XCTAssertEqual(metrics.lastPathComponent, "telemetry.blazedb")
        XCTAssertEqual(metrics.deletingLastPathComponent().lastPathComponent, "metrics")
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
