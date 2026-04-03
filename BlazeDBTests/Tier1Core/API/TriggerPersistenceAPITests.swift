import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class TriggerPersistenceAPITests: XCTestCase {
    private var dbURL: URL?

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trigger-persist-\(UUID().uuidString).blazedb")
    }

    override func tearDownWithError() throws {
        let metaURL = try requireFixture(dbURL).deletingPathExtension().appendingPathExtension("meta")
        try? FileManager.default.removeItem(at: try requireFixture(dbURL))
        try? FileManager.default.removeItem(at: try requireFixture(metaURL))
    }

    func testOnInsertTriggerDefinitionIsPersistedToLayoutMetadata() throws {
        let db = try BlazeDBClient(name: "trigger-persist", fileURL: try requireFixture(dbURL), password: "TriggerPass-123!")
        defer { try? try requireFixture(db).close() }

        try requireFixture(db).onInsert(name: "persisted_on_insert") { _, _, _ in
            // no-op
        }

        let layout = try StorageLayout.loadSecure(
            from: try requireFixture(db).collection.metaURLPath,
            signingKey: try requireFixture(db).collection.encryptionKey
        )
        let stored = try XCTUnwrap(layout.metaData["_triggers"])
        let raw: Data
        if let data = stored.dataValue {
            raw = data
        } else if let base64 = stored.stringValue, let decoded = Data(base64Encoded: base64) {
            raw = decoded
        } else {
            XCTFail("Expected _triggers metadata to be stored as data or base64 string")
            return
        }
        let decoded = try JSONDecoder().decode([TriggerDefinition].self, from: raw)

        XCTAssertTrue(
            decoded.contains(where: { $0.name == "persisted_on_insert" }),
            "Registering onInsert trigger should persist trigger metadata"
        )
    }
}
