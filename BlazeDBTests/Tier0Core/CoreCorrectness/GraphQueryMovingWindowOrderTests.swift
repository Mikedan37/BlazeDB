//
//  GraphQueryMovingWindowOrderTests.swift
//  BlazeDBTests — #377: movingAverage/movingSum apply the window before sorting by X
//
//  A moving window must aggregate X-ordered neighbours. Graph points are built by
//  iterating a Swift Dictionary of groups, and that iteration order is unspecified
//  and seed-varying, so the window has to run over an X-ascending series no matter
//  what order the records were inserted in. The caller's requested presentation
//  direction still decides the order of the returned points, and the trailing
//  leading-edge window (partial windows at the start of the series) is unchanged.
//

import Foundation
import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class GraphQueryMovingWindowOrderTests: XCTestCase {
    private var dbURL: URL!
    private var db: BlazeDBClient!

    /// Y values are powers of two, so every window sum identifies its exact member
    /// set: any neighbour set other than the X-ordered one yields a different value.
    private let seriesValues: [Double] = [1, 2, 4, 8, 16, 32, 64, 128]

    /// Deliberately unrelated to X order, so the groups are never inserted in
    /// X order and the dictionary that carries them cannot be trusted to be sorted.
    private let insertionOrder = [4, 0, 6, 2, 7, 1, 5, 3]

    private let windowSize = 3

    override func setUp() {
        super.setUp()
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphMovingWindow-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "GraphMovingWindow",
            fileURL: dbURL,
            password: "GraphMovingWindow-Pass_123!"
        )
    }

    override func tearDown() {
        try? db.close()
        let base = dbURL.deletingPathExtension()
        for ext in ["blazedb", "meta", "wal", "salt", "indexes"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
        try? FileManager.default.removeItem(at: dbURL)
        db = nil
        dbURL = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// X labels in ascending order. Each test uses its own prefix so the group keys
    /// hash differently and the tests do not all observe one dictionary permutation.
    /// Indices are zero-padded so lexicographic X order is the intended series order.
    private func labels(prefix: String) -> [String] {
        (1...seriesValues.count).map { index in
            let padded = index < 10 ? "0\(index)" : "\(index)"
            return "\(prefix)-\(padded)"
        }
    }

    /// Insert exactly one record per group, in an order that is not X order.
    private func seedGroups(prefix: String) throws {
        let names = labels(prefix: prefix)
        for index in insertionOrder {
            _ = try db.insert(BlazeDataRecord([
                "bucket": .string(names[index]),
                "value": .double(seriesValues[index])
            ]))
        }
    }

    /// Trailing windows over the X-ascending series, including the partial
    /// leading-edge windows the current implementation produces.
    private func trailingWindows() -> [[Double]] {
        (0..<seriesValues.count).map { i in
            Array(seriesValues[Swift.max(0, i - windowSize + 1)...i])
        }
    }

    private func expectedMovingAverages() -> [Double] {
        trailingWindows().map { $0.reduce(0, +) / Double($0.count) }
    }

    private func expectedMovingSums() -> [Double] {
        trailingWindows().map { $0.reduce(0, +) }
    }

    private func assertSeries(
        _ points: [BlazeGraphPoint<any Sendable, any Sendable>],
        expectedLabels: [String],
        expectedValues: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(points.count, expectedValues.count, "point count", file: file, line: line)
        guard points.count == expectedValues.count else { return }

        XCTAssertEqual(
            points.map { $0.x as? String },
            expectedLabels as [String?],
            "X presentation order",
            file: file,
            line: line
        )

        for (index, expected) in expectedValues.enumerated() {
            guard let actual = points[index].y as? Double else {
                XCTFail("point \(index) has no Double Y value", file: file, line: line)
                continue
            }
            XCTAssertEqual(
                actual,
                expected,
                accuracy: 1e-9,
                "window value at \(expectedLabels[index]) must aggregate X-ordered neighbours",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Tests

    /// #377: the moving average must be the simple moving average of the X-sorted
    /// Y series, even though the groups were inserted out of X order.
    func testMovingAverage_AggregatesXOrderedNeighbours() throws {
        try seedGroups(prefix: "avg")

        let points = try db.graph()
            .x("bucket")
            .y(.sum("value"))
            .movingAverage(windowSize)
            .toPoints()

        assertSeries(
            points,
            expectedLabels: labels(prefix: "avg"),
            expectedValues: expectedMovingAverages()
        )
    }

    /// #377: same invariant for the moving sum.
    func testMovingSum_AggregatesXOrderedNeighbours() throws {
        try seedGroups(prefix: "sum")

        let points = try db.graph()
            .x("bucket")
            .y(.sum("value"))
            .movingSum(windowSize)
            .toPoints()

        assertSeries(
            points,
            expectedLabels: labels(prefix: "sum"),
            expectedValues: expectedMovingSums()
        )
    }

    /// A descending presentation must not change which neighbours the window
    /// aggregates: the window is still computed over the X-ascending series, and
    /// only the order in which the finished points are returned is reversed.
    func testMovingAverage_DescendingPresentationKeepsXOrderedWindows() throws {
        try seedGroups(prefix: "avgdesc")

        let points = try db.graph()
            .x("bucket")
            .y(.sum("value"))
            .movingAverage(windowSize)
            .sorted(ascending: false)
            .toPoints()

        assertSeries(
            points,
            expectedLabels: Array(labels(prefix: "avgdesc").reversed()),
            expectedValues: Array(expectedMovingAverages().reversed())
        )
    }

    /// Same descending check for the moving sum.
    func testMovingSum_DescendingPresentationKeepsXOrderedWindows() throws {
        try seedGroups(prefix: "sumdesc")

        let points = try db.graph()
            .x("bucket")
            .y(.sum("value"))
            .movingSum(windowSize)
            .sorted(ascending: false)
            .toPoints()

        assertSeries(
            points,
            expectedLabels: Array(labels(prefix: "sumdesc").reversed()),
            expectedValues: Array(expectedMovingSums().reversed())
        )
    }
}
