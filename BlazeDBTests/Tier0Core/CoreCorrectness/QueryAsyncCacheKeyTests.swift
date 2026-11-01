import XCTest
@testable import BlazeDBCore

/// `queryAsync` used to key its result cache with `serializedString()`.
/// That string drops the value type and payload, so distinct predicates
/// shared one entry. These cases are the collisions that returned the wrong rows.
final class QueryAsyncCacheKeyTests: XCTestCase {
    func testIntAndDigitStringDoNotShareAKey() {
        let intKey = cacheKey(field: "kind", value: .int(1))
        let stringKey = cacheKey(field: "kind", value: .string("1"))
        XCTAssertNotEqual(intKey, stringKey)
    }

    func testSameSizeDataAndVectorsDoNotShareAKey() {
        let dataA = cacheKey(field: "blob", value: .data(Data([0x01, 0x02])))
        let dataB = cacheKey(field: "blob", value: .data(Data([0x03, 0x04])))
        XCTAssertNotEqual(dataA, dataB)

        let vecA = cacheKey(field: "embedding", value: .vector([1.0, 0.0]))
        let vecB = cacheKey(field: "embedding", value: .vector([0.0, 1.0]))
        XCTAssertNotEqual(vecA, vecB)
    }

    func testColonInValueDoesNotCollideWithColonInField() {
        let valueHasColon = cacheKey(field: "a", value: .string("b:c"), orderBy: "name")
        let fieldHasColon = cacheKey(field: "a:b", value: .string("c"), orderBy: "name")
        XCTAssertNotEqual(valueHasColon, fieldHasColon)
    }

    func testNullAndNullStringDoNotShareAKey() {
        XCTAssertNotEqual(
            cacheKey(field: "flag", value: .null),
            cacheKey(field: "flag", value: .string("null"))
        )
    }

    func testAbsentFieldIsNotTheSentinelString() {
        XCTAssertNotEqual(
            cacheKey(field: nil, value: .string("open"), orderBy: nil),
            cacheKey(field: "none", value: .string("open"), orderBy: "none")
        )
        XCTAssertNotEqual(
            cacheKey(field: "status", value: nil, orderBy: nil),
            cacheKey(field: "status", value: .string("none"), orderBy: nil)
        )
    }

    func testIdenticalPredicatesKeepOneKey() {
        let first = cacheKey(field: "status", value: .string("open"), orderBy: "priority", descending: true, limit: 10)
        let second = cacheKey(field: "status", value: .string("open"), orderBy: "priority", descending: true, limit: 10)
        XCTAssertEqual(first, second)
    }

    private func cacheKey(
        field: String?,
        value: BlazeDocumentField?,
        orderBy: String? = nil,
        descending: Bool = false,
        limit: Int? = nil
    ) -> String {
        queryAsyncCacheKey(
            field: field,
            value: value,
            orderBy: orderBy,
            descending: descending,
            limit: limit
        )
    }
}
