import XCTest
@testable import BlazeDBCore

final class ActivePercentileBenchmarks: XCTestCase {
    private var tempURL: URL!
    private var db: BlazeDBClient!

    override func setUpWithError() throws {
        let id = UUID().uuidString
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivePercentiles-\(id).blazedb")
        db = try BlazeDBClient(
            name: "active_percentiles",
            fileURL: tempURL,
            password: "BenchmarkPassword-123!"
        )
    }

    override func tearDownWithError() throws {
        try? db?.persist()
        try? db?.close()
        db = nil
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: tempURL.deletingPathExtension().appendingPathExtension("wal"))
        }
    }

    func testActiveQueryPercentiles() throws {
        let records = (0..<1000).map { i in
            BlazeDataRecord([
                "bucket": .int(i % 10),
                "value": .int(i),
                "text": .string("record-\(i)")
            ])
        }
        _ = try db.insertMany(records)
        try db.persist()

        var durationsMs: [Double] = []
        durationsMs.reserveCapacity(500)

        let start = Date()
        for i in 0..<500 {
            let opStart = Date()
            _ = try db.query()
                .where("bucket", equals: .int(i % 10))
                .limit(20)
                .execute()
            durationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }
        let elapsed = Date().timeIntervalSince(start)
        let throughput = 500.0 / max(elapsed, 0.0001)

        let p50 = percentile(durationsMs, 0.50)
        let p95 = percentile(durationsMs, 0.95)
        let p99 = percentile(durationsMs, 0.99)

        print("ACTIVE_QUERY_P50_MS=\(String(format: "%.3f", p50))")
        print("ACTIVE_QUERY_P95_MS=\(String(format: "%.3f", p95))")
        print("ACTIVE_QUERY_P99_MS=\(String(format: "%.3f", p99))")
        print("ACTIVE_QUERY_THROUGHPUT_QPS=\(String(format: "%.1f", throughput))")

        XCTAssertGreaterThan(p50, 0)
        XCTAssertGreaterThan(p95, 0)
        XCTAssertGreaterThan(p99, 0)
    }

    func testActiveOperationPercentiles() throws {
        var ids: [UUID] = []
        var durationsMs: [Double] = []
        durationsMs.reserveCapacity(400)

        // Inserts
        for i in 0..<100 {
            let opStart = Date()
            let id = try db.insert(BlazeDataRecord([
                "i": .int(i),
                "payload": .string("payload-\(i)")
            ]))
            durationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
            ids.append(id)
        }

        // Fetches
        for id in ids {
            let opStart = Date()
            _ = try db.fetch(id: id)
            durationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }

        // Updates
        for (index, id) in ids.enumerated() {
            let opStart = Date()
            try db.update(id: id, with: BlazeDataRecord([
                "i": .int(index + 10_000),
                "payload": .string("updated-\(index)")
            ]))
            durationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }

        // Deletes (half)
        for id in ids.prefix(50) {
            let opStart = Date()
            try db.delete(id: id)
            durationsMs.append(Date().timeIntervalSince(opStart) * 1000.0)
        }

        let p50 = percentile(durationsMs, 0.50)
        let p95 = percentile(durationsMs, 0.95)
        let p99 = percentile(durationsMs, 0.99)
        let avg = durationsMs.reduce(0, +) / Double(max(durationsMs.count, 1))

        print("ACTIVE_TELEMETRY_AVG_MS=\(String(format: "%.3f", avg))")
        print("ACTIVE_TELEMETRY_P50_MS=\(String(format: "%.3f", p50))")
        print("ACTIVE_TELEMETRY_P95_MS=\(String(format: "%.3f", p95))")
        print("ACTIVE_TELEMETRY_P99_MS=\(String(format: "%.3f", p99))")

        XCTAssertGreaterThan(avg, 0)
        XCTAssertGreaterThan(p95, 0)
        XCTAssertGreaterThan(p99, 0)
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, Int(Double(sorted.count - 1) * p))
        return sorted[idx]
    }
}
