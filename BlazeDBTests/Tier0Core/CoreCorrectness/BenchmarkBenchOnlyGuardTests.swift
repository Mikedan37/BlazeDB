import XCTest

/// Regression: `BLAZEDB_BENCH_ONLY` smokes must not wipe published RESULTS when no rows were collected.
///
/// The harness lives in the `BlazeDBBenchmarks` executable (not importable from XCTest), so this
/// locks the persistence contract in-source and mirrors the empty-suite decision locally.
final class BenchmarkBenchOnlyGuardTests: XCTestCase {
    /// Mirrors `BlazeDBBenchmarks/main.swift` — write RESULTS only when the suite collected rows.
    static func shouldWritePublishedResults(resultCount: Int) -> Bool {
        resultCount > 0
    }

    func testEmptySuite_doesNotWritePublishedResults() {
        XCTAssertFalse(Self.shouldWritePublishedResults(resultCount: 0))
        XCTAssertTrue(Self.shouldWritePublishedResults(resultCount: 1))
    }

    func testMainContainsEmptySuiteGuardAgainstWipingResults() throws {
        let mainURL = try repoRoot()
            .appendingPathComponent("BlazeDBBenchmarks/main.swift")
        let main = try String(contentsOf: mainURL, encoding: .utf8)
        XCTAssertTrue(
            main.contains("guard !suite.results.isEmpty else"),
            "empty-suite guard missing — BLAZEDB_BENCH_ONLY smokes could wipe Docs/Benchmarks/RESULTS.md"
        )
        XCTAssertTrue(
            main.contains("not writing RESULTS.md/results.json"),
            "empty-suite early exit message missing"
        )
        XCTAssertTrue(
            main.contains("BLAZEDB_BENCH_ONLY"),
            "BLAZEDB_BENCH_ONLY handling missing from harness"
        )
    }

    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        let marker = url.appendingPathComponent("Package.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path),
            "expected Package.swift at \(marker.path)"
        )
        return url
    }
}
