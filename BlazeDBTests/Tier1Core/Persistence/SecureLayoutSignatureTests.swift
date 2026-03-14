import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

final class SecureLayoutSignatureTests: XCTestCase {
    private func tempMetaURL(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("secure-layout-\(name).meta")
    }

    private func makeLayout() -> StorageLayout {
        StorageLayout(
            indexMap: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000001")!: [1],
                UUID(uuidString: "00000000-0000-0000-0000-000000000002")!: [2],
                UUID(uuidString: "00000000-0000-0000-0000-000000000003")!: [3],
            ],
            nextPageIndex: 4,
            secondaryIndexes: [:],
            version: 1,
            encodingFormat: "blazeBinary",
            metaData: ["schemaVersion": .int(1)],
            fieldTypes: [:],
            secondaryIndexDefinitions: [:],
            searchIndex: nil,
            searchIndexedFields: []
        )
    }

    func testLoadSecureUsesVerifiedSignedPayloadAsSourceOfTruth() throws {
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let layout = makeLayout()
        let secure = try StorageLayout.SecureLayout.create(layout: layout, signingKey: key)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(secure)) as? [String: Any])
        var tamperedLayout = try XCTUnwrap(object["layout"] as? [String: Any])
        tamperedLayout["nextPageIndex"] = 0
        tamperedLayout["indexMap"] = []
        object["layout"] = tamperedLayout
        let tamperedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let url = tempMetaURL("signed-payload-source-of-truth")
        defer { try? FileManager.default.removeItem(at: url) }
        try tamperedData.write(to: url, options: .atomic)

        let loaded = try StorageLayout.loadSecure(from: url, signingKey: key)
        XCTAssertEqual(loaded.nextPageIndex, 4, "Verified signed payload must be authoritative over tampered wrapper layout.")
        XCTAssertEqual(loaded.indexMap.count, 3)
    }

    func testLoadSecureReadsLegacyV1WithoutSignedPayload() throws {
        let key = SymmetricKey(data: Data(repeating: 0x24, count: 32))
        // Keep v1 compatibility test deterministic by using an empty index map.
        let layout = StorageLayout(
            indexMap: [:],
            nextPageIndex: 0,
            secondaryIndexes: [:],
            version: 1,
            encodingFormat: "blazeBinary",
            metaData: [:],
            fieldTypes: [:],
            secondaryIndexDefinitions: [:],
            searchIndex: nil,
            searchIndexedFields: []
        )
        let unsignedV1 = StorageLayout.SecureLayout(
            secureLayoutVersion: 1,
            layout: layout,
            signedPayload: nil,
            signature: Data(),
            signedAt: Date()
        )
        let signature = try unsignedV1.expectedSignature(using: key)
        let secure = StorageLayout.SecureLayout(
            secureLayoutVersion: 1,
            layout: layout,
            signedPayload: nil,
            signature: signature,
            signedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(secure)) as? [String: Any])
        // Simulate true legacy v1 payload shape (no explicit version or payload fields).
        object.removeValue(forKey: "secureLayoutVersion")
        object.removeValue(forKey: "signedPayload")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let url = tempMetaURL("legacy-v1-compat")
        defer { try? FileManager.default.removeItem(at: url) }
        try legacyData.write(to: url, options: .atomic)

        let loaded = try StorageLayout.loadSecure(from: url, signingKey: key)
        XCTAssertEqual(loaded.nextPageIndex, layout.nextPageIndex)
        XCTAssertEqual(loaded.indexMap.count, layout.indexMap.count)
    }
}

