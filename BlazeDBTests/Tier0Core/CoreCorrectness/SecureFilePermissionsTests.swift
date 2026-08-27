//
//  SecureFilePermissionsTests.swift
//  BlazeDBTests
//
//  Regression tests for #357 / #324: owner-only creation of sensitive artifacts.
//

import XCTest
@testable import BlazeDBCore

final class SecureFilePermissionsTests: XCTestCase {
    private var tempDir: URL!
    private let password = "SecureFilePerms-Test-2026!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecureFilePerms-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testNewDatabaseArtifactsAreOwnerOnlyOnPOSIX() throws {
        #if os(Windows)
        throw XCTSkip("POSIX permissions not applicable on Windows")
        #else
        let url = tempDir.appendingPathComponent("perms.blazedb")
        let db = try BlazeDBClient(name: "perms", fileURL: url, password: password)
        defer { try? db.close() }

        let salt = url.deletingPathExtension().appendingPathExtension("salt")
        let dbMode = try posixMode(at: url)
        let saltMode = try posixMode(at: salt)
        XCTAssertEqual(dbMode & 0o077, 0, "new DB file must not be group/world accessible (#357)")
        XCTAssertEqual(saltMode & 0o077, 0, "new .salt must not be group/world accessible (#357)")
        #endif
    }

    func testMasterKeyringDirectoryIsOwnerOnlyOnPOSIX() throws {
        #if os(Windows)
        throw XCTSkip("POSIX permissions not applicable on Windows")
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".blazedb-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try SecureFileAttributes.ensureOwnerOnlyDirectory(at: dir)
        let mode = try posixMode(at: dir)
        XCTAssertEqual(mode & 0o077, 0, "~/.blazedb-style dirs should be 0700 (#324)")
        #endif
    }

    private func posixMode(at url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let mode = attrs[.posixPermissions] as? NSNumber else {
            throw NSError(domain: "SecureFilePermissionsTests", code: 1)
        }
        return mode.intValue
    }
}
