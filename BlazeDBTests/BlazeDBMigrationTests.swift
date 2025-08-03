//  BlazeDBMigrationTests.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/22/25.

import XCTest
@testable import BlazeDB

@MainActor
final class BlazeDBMigrationTests: XCTestCase {

func testAddRemoveRenameFieldsMigration() throws {
    // Initial schema version
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("migrationtest.blazedb")
    try? FileManager.default.removeItem(at: fileURL)

    // Create database with initial record
    var db = try BlazeDBClient(fileURL: fileURL, password: "test123")
    let id = try db.insert([
        "title": .string("Test Migration Record"),
        "value": .int(42)
    ])
    print("✅ Inserted record with id: \(id)")

    // Simulate app relaunch with new schema
    db = try BlazeDBClient(fileURL: fileURL, password: "test123")
    
    // Define expected schema update
    db.expectedSchema = [
        "title": .string(""),
        "value": .int(0),
        "createdAt": .date(.now),
        "status": .string("open")
    ]
    
    try db.performMigrationIfNeeded()

    let record = try db.fetch(id: id)
    XCTAssertNotNil(record["createdAt"])
    XCTAssertNotNil(record["status"])
    XCTAssertEqual(record["status"], .string("open"))
    print("✅ Auto-migrated new fields onto old record")
}
    
    func testBackupBeforeMigration() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("backuptest.blazedb")
        try? FileManager.default.removeItem(at: fileURL)

        var db = try BlazeDBClient(fileURL: fileURL, password: "backupme")
        _ = try db.insert(["x": .int(1)])

        db = try BlazeDBClient(fileURL: fileURL, password: "backupme")
        db.expectedSchema = ["x": .int(1), "newField": .string("")]
        try db.performMigrationIfNeeded()

        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("backup_v1.blazedb")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        print("✅ Backup created at: \(backupURL.lastPathComponent)")
    }
    
    func testAddRemoveRenameFieldsMigration() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("migrationtest.blazedb")
        try? FileManager.default.removeItem(at: fileURL)

        var db = try BlazeDBClient(fileURL: fileURL, password: "test123")
        let id = try db.insert([
            "summary": .string("Test Migration Record"),
            "value": .int(42)
        ])
        print("✅ Inserted record with id: \(id)")

        db = try BlazeDBClient(fileURL: fileURL, password: "test123")
        db.expectedSchema = [
            "title": .string(""), // should map from "summary"
            "value": .int(0),
            "createdAt": .date(.now),
            "status": .string("open")
        ]
        db.legacyFieldMap = ["summary": "title"]

        try db.performMigrationIfNeeded()

        let record = try db.fetch(id: id)
        XCTAssertNotNil(record["createdAt"])
        XCTAssertNotNil(record["status"])
        XCTAssertEqual(record["status"], .string("open"))
        XCTAssertEqual(record["title"], .string("Test Migration Record"))
        XCTAssertNil(record["summary"])
        print("✅ Auto-migrated new fields and renamed old field")
    }
    
}
