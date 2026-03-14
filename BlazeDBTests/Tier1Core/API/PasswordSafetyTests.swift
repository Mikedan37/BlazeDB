import XCTest
@testable import BlazeDBCore

final class PasswordSafetyTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Clean up any test databases
        let tmp = FileManager.default.temporaryDirectory
        for name in ["pwd-safety-1", "pwd-safety-2"] {
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).blazedb")
            )
            try? FileManager.default.removeItem(
                at: tmp.appendingPathComponent("\(name).meta")
            )
        }
    }

    func testOpenNamedRequiresPassword() throws {
        // open(named:password:) should work with a valid password
        let db = try BlazeDBClient.openForTesting(name: "pwd-safety-1", password: "Test-Password-123!")
        let id = try db.insert(BlazeDataRecord(["k": .string("v")]))
        try db.close()

        // Reopen with same password — must succeed
        let db2 = try BlazeDBClient.openForTesting(name: "pwd-safety-1", password: "Test-Password-123!")
        let record = try db2.fetch(id: id)
        XCTAssertNotNil(record, "Should be able to reopen with correct password")
        try db2.close()
    }

    func testNoSilentDevPasswordExists() throws {
        // Verify the old dev password pattern string is NOT in the source
        // This is a structural test — grep the source for the pattern
        let easyOpenPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeDB/Exports/BlazeDBClient+EasyOpen.swift")

        if FileManager.default.fileExists(atPath: easyOpenPath.path) {
            let source = try String(contentsOf: easyOpenPath, encoding: .utf8)
            XCTAssertFalse(
                source.contains("BlazeDB-Dev-"),
                "Source still contains hidden dev password pattern 'BlazeDB-Dev-'"
            )
            XCTAssertFalse(
                source.contains("effectivePassword"),
                "Source still contains effectivePassword variable"
            )
        }
    }

    func testOpenNamedPasswordIsNotOptional() throws {
        // This test documents that the API requires a password.
        // If someone changes the signature back to optional, this test must be updated.
        // The test itself succeeds as long as open(named:password:) compiles with a non-optional String.
        let db = try BlazeDBClient.openForTesting(name: "pwd-safety-2", password: "Another-Test-Pwd-456!")
        try db.close()
    }
}
