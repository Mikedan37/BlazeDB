import XCTest
@testable import BlazeDBCore

/// Keeps benchmark honesty claims about the *standard* harness row size honest.
/// Mirrors `BlazeDBBenchmarks/BenchPayload.standardRecord` without depending on the bench target.
final class BenchmarkStandardRecordSizeTests: XCTestCase {
    func testStandardHarnessShape_encodesAsTensOfBytes_notMegabytes() throws {
        var sizes: [Int] = []
        for i in 0..<32 {
            let record = BlazeDataRecord([
                "id": .uuid(UUID()),
                "index": .int(i),
                "data": .string("Record \(i)"),
            ])
            let encoded = try BlazeBinaryEncoder.encode(record)
            sizes.append(encoded.count)
        }
        sizes.sort()
        let median = sizes[sizes.count / 2]
        XCTAssertGreaterThanOrEqual(median, 40, "standard row should include UUID+index+string overhead")
        XCTAssertLessThanOrEqual(median, 200, "standard harness row must not be conflated with 1 MB growth profile; median=\(median)")
    }

    func testOneMegabyteGrowthShape_isOrdersOfMagnitudeLarger() throws {
        let body = String(repeating: "x", count: 1_000_000)
        let record = BlazeDataRecord([
            "id": .uuid(UUID()),
            "index": .int(0),
            "payload": .string(body),
        ])
        let encoded = try BlazeBinaryEncoder.encode(record)
        XCTAssertGreaterThan(encoded.count, 1_000_000)
    }
}
