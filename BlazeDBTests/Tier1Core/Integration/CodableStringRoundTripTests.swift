import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Regression tests for GitHub issue #80:
/// BlazeStorable round-trip misdecodes String fields containing valid JSON text.
final class CodableStringRoundTripTests: XCTestCase {

    private var db: BlazeDBClient?
    private var tempURL: URL?

    // MARK: - Test Models

    struct ConfigModel: BlazeStorable {
        var id: UUID = UUID()
        var jsonPayload: String
    }

    struct NestedPayload: Codable, Equatable {
        var key: String
        var values: [Int]
    }

    struct NestedModel: BlazeStorable, Equatable {
        var id: UUID = UUID()
        var payload: NestedPayload

        static func == (lhs: NestedModel, rhs: NestedModel) -> Bool {
            lhs.id == rhs.id && lhs.payload == rhs.payload
        }
    }

    struct MixedModel: BlazeStorable {
        var id: UUID = UUID()
        var label: String
        var jsonPayload: String
        var nested: NestedPayload
    }

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".blazedb")
        db = try BlazeDBClient(
            name: "StringRoundTripTest",
            fileURL: try requireFixture(tempURL),
            password: "TestPassword-123!"
        )
    }

    override func tearDown() {
        db = nil
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    // MARK: - Issue #80: String fields containing JSON text

    func testStringContainingJSONObject_fetch() throws {
        let model = ConfigModel(jsonPayload: "{\"key\":\"value\"}")
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(ConfigModel.self, id: model.id)
        XCTAssertNotNil(fetched, "fetch(id:) should return a result")
        XCTAssertEqual(fetched?.jsonPayload, "{\"key\":\"value\"}")
    }

    func testStringContainingJSONArray_fetch() throws {
        let model = ConfigModel(jsonPayload: "[1,2,3]")
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(ConfigModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.jsonPayload, "[1,2,3]")
    }

    func testStringContainingEmptyJSONObject_fetch() throws {
        let model = ConfigModel(jsonPayload: "{}")
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(ConfigModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.jsonPayload, "{}")
    }

    func testStringContainingEmptyJSONArray_fetch() throws {
        let model = ConfigModel(jsonPayload: "[]")
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(ConfigModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.jsonPayload, "[]")
    }

    func testPlainStringStillRoundTrips() throws {
        let model = ConfigModel(jsonPayload: "hello world")
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(ConfigModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.jsonPayload, "hello world")
    }

    func testStringContainingJSONObject_fetchAll() throws {
        let model = ConfigModel(jsonPayload: "{\"a\":1}")
        _ = try requireFixture(db).insert(model)

        let all = try requireFixture(db).fetchAll(ConfigModel.self)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.jsonPayload, "{\"a\":1}")
    }

    func testStringContainingJSONArray_fetchAll() throws {
        let model = ConfigModel(jsonPayload: "[\"x\",\"y\"]")
        _ = try requireFixture(db).insert(model)

        let all = try requireFixture(db).fetchAll(ConfigModel.self)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.jsonPayload, "[\"x\",\"y\"]")
    }

    // MARK: - Nested Codable struct round-trip (must not regress)

    func testNestedCodableStructRoundTrips() throws {
        let nested = NestedPayload(key: "test", values: [10, 20, 30])
        let model = NestedModel(payload: nested)
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(NestedModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.payload.key, "test")
        XCTAssertEqual(fetched?.payload.values, [10, 20, 30])
    }

    func testNestedCodableStructRoundTrips_fetchAll() throws {
        let nested = NestedPayload(key: "all", values: [1, 2])
        let model = NestedModel(payload: nested)
        _ = try requireFixture(db).insert(model)

        let all = try requireFixture(db).fetchAll(NestedModel.self)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.payload, nested)
    }

    // MARK: - Mixed model: plain JSON-looking string + nested struct

    func testMixedModel_stringAndNestedStructBothRoundTrip() throws {
        let model = MixedModel(
            label: "config",
            jsonPayload: "{\"raw\":true}",
            nested: NestedPayload(key: "inner", values: [42])
        )
        _ = try requireFixture(db).insert(model)

        let fetched = try requireFixture(db).fetch(MixedModel.self, id: model.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.label, "config")
        XCTAssertEqual(fetched?.jsonPayload, "{\"raw\":true}")
        XCTAssertEqual(fetched?.nested.key, "inner")
        XCTAssertEqual(fetched?.nested.values, [42])
    }

    // MARK: - Legacy backward-compatibility

    func testLegacyStringEncodedNestedObject_stillDecodes() throws {
        // Simulate legacy storage: a nested object was stored as .string(json)
        // rather than .dictionary(). The decode path must still handle this.
        let nestedJSON = "{\"key\":\"legacy\",\"values\":[1,2,3]}"
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "payload": .string(nestedJSON)
        ])
        let id = try requireFixture(db).insert(record)

        // Decoding as NestedModel should still succeed via legacy fallback
        let fetched = try requireFixture(db).fetch(NestedModel.self, id: id)
        XCTAssertNotNil(fetched, "Legacy .string(json) nested objects must still decode")
        XCTAssertEqual(fetched?.payload.key, "legacy")
        XCTAssertEqual(fetched?.payload.values, [1, 2, 3])
    }

    // MARK: - Encode representation verification

    func testPlainStringEncodesToStringField() throws {
        let model = ConfigModel(jsonPayload: "just text")
        let record = try model.toBlazeRecord()
        guard case .string(let stored) = record.storage["jsonPayload"] else {
            XCTFail("Plain string should encode to .string, got: \(String(describing: record.storage["jsonPayload"]))")
            return
        }
        XCTAssertEqual(stored, "just text")
    }

    func testJSONLookingStringEncodesToStringField() throws {
        let model = ConfigModel(jsonPayload: "{\"key\":\"value\"}")
        let record = try model.toBlazeRecord()
        guard case .string(let stored) = record.storage["jsonPayload"] else {
            XCTFail("JSON-looking string should encode to .string, got: \(String(describing: record.storage["jsonPayload"]))")
            return
        }
        XCTAssertEqual(stored, "{\"key\":\"value\"}")
    }

    func testNestedStructEncodesToDictionary() throws {
        let model = NestedModel(payload: NestedPayload(key: "k", values: [1]))
        let record = try model.toBlazeRecord()
        guard case .dictionary = record.storage["payload"] else {
            XCTFail("Nested struct should encode to .dictionary, got: \(String(describing: record.storage["payload"]))")
            return
        }
    }
}
