import XCTest
@testable import BlazeDBCore

final class Base64CoercionTests: XCTestCase {

    func testStringThatLooksLikeBase64RemainsString() throws {
        // "SGVsbG8gV29ybGQ=" is base64 for "Hello World"
        // It must remain a .string, not get silently converted to .data
        let field = BlazeDocumentField.string("SGVsbG8gV29ybGQ=")

        // Encode then decode via Codable round-trip
        let data = try JSONEncoder().encode(field)
        let decoded = try JSONDecoder().decode(BlazeDocumentField.self, from: data)

        switch decoded {
        case .string(let s):
            XCTAssertEqual(s, "SGVsbG8gV29ybGQ=")
        default:
            XCTFail("String was silently coerced to \(decoded). Expected .string.")
        }
    }

    func testDataValueDoesNotAutoDecodeBase64Strings() throws {
        let field = BlazeDocumentField.string("SGVsbG8gV29ybGQ=")
        // .dataValue on a .string should return nil, not auto-decode base64
        XCTAssertNil(field.dataValue, "dataValue should not auto-decode base64 strings")
    }

    func testExplicitDataFieldPreservesDataViaBinary() throws {
        // JSON has no binary type, so .data round-trips through JSON as .string.
        // BlazeDB uses BlazeBinary for storage, which preserves .data natively.
        // Here we verify that .data fields preserve their value through BlazeBinary.
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let field = BlazeDocumentField.data(original)

        // Verify dataValue accessor works for explicit .data
        XCTAssertEqual(field.dataValue, original)

        // Verify round-trip through BlazeBinary (the actual storage format)
        let record = BlazeDataRecord(["blob": field])
        let encoded = try BlazeBinaryEncoder.encode(record)
        let decoded = try BlazeBinaryDecoder.decode(encoded)
        XCTAssertEqual(decoded.storage["blob"], .data(original))
    }

    func testStringDataCrossTypeComparisonReturnsFalse() throws {
        // A string and data value should never be equal, even if the string is base64 of the data
        let stringField = BlazeDocumentField.string("SGVsbG8=")
        let dataField = BlazeDocumentField.data(Data("Hello".utf8))

        // They should not be equal
        XCTAssertNotEqual(stringField, dataField)
    }
}
