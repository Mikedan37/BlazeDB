import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI
import Combine

@MainActor
final class BlazeQueryObservationIntegrationTests: LinuxTier1NonCryptoKDFHarness {
    private var db: BlazeDBClient?
    private var dbURL: URL?

    override func setUp() async throws {
        continueAfterFailure = false
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeQueryObs-\(UUID().uuidString).blazedb")
        db = try BlazeDBClient(
            name: "BlazeQueryObservationIntegrationTests",
            fileURL: try requireFixture(dbURL),
            password: "SecureObsPass-123!"
        )
    }

    override func tearDown() async throws {
        if let db {
            try? db.close()
        }
        db = nil

        if let baseURL = dbURL {
            try? FileManager.default.removeItem(at: baseURL)
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("meta"))
            try? FileManager.default.removeItem(at: baseURL.appendingPathExtension("wal"))
        }
        dbURL = nil
    }

    func testBlazeQueryObserverRefreshesAfterInsertWithoutManualRefresh() async throws {
        let observer = BlazeQueryObserver(
            db: try requireFixture(db),
            filters: [("status", .equals, .string("open"))],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        )

        // Initial state should be empty.
        try await waitUntil(timeout: 2.0) {
            observer.results.isEmpty && !observer.isLoading
        }

        _ = try await requireFixture(db).insert(
            BlazeDataRecord(["status": .string("open"), "title": .string("auto refresh")])
        )

        // Expect automatic observer-driven refresh (no manual refresh, no timer).
        try await waitUntil(timeout: 2.0) {
            observer.results.count == 1
        }
    }

    func testBlazeQueryTypedObserverRefreshesAfterInsertWithoutManualRefresh() async throws {
        let observer = BlazeQueryTypedObserver<QueryObsDoc>(
            db: try requireFixture(db),
            filters: [("status", .equals, .string("open"))],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        )

        try await waitUntil(timeout: 2.0) {
            observer.results.isEmpty && !observer.isLoading
        }

        _ = try await requireFixture(db).insert(
            BlazeDataRecord([
                "id": .uuid(UUID()),
                "status": .string("open"),
                "title": .string("typed auto refresh")
            ])
        )

        // Expect automatic observer-driven refresh (no manual refresh, no timer).
        try await waitUntil(timeout: 2.0) {
            observer.results.count == 1 && observer.results[0].status == "open"
        }
    }

    /// Typed observer with `db: nil` matches env-only `@BlazeQuery` until the client is bound.
    func testBlazeQueryTypedObserverBindsDatabaseLazily() async throws {
        let client = try requireFixture(db)
        let observer = BlazeQueryTypedObserver<QueryObsDoc>(
            db: nil,
            filters: [],
            sortField: nil,
            sortDescending: false,
            limitCount: nil
        )

        XCTAssertTrue(observer.results.isEmpty)

        observer.bindDatabaseIfNeeded(client)
        try await waitUntil(timeout: 2.0) {
            !observer.isLoading
        }

        let id = UUID()
        _ = try await client.insert(
            BlazeDataRecord([
                "id": .uuid(id),
                "status": .string("open"),
                "title": .string("lazy bind")
            ])
        )

        try await waitUntil(timeout: 2.0) {
            observer.results.count == 1 && observer.results[0].title == "lazy bind"
        }
    }

    /// `BlazeQueryTyped` remains a typealias for `BlazeQuery` (source compatibility).
    func testBlazeQueryTypedTypealiasMatchesBlazeQuery() {
        let _: BlazeQuery<QueryObsDoc>.Type = BlazeQueryTyped<QueryObsDoc>.self
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Condition was not met within \(timeout) seconds")
    }
}

private struct QueryObsDoc: BlazeDocument {
    var id: UUID
    var status: String
    var title: String

    init(id: UUID, status: String, title: String) {
        self.id = id
        self.status = status
        self.title = title
    }

    init(from storage: BlazeDataRecord) throws {
        guard
            let id = storage.storage["id"]?.uuidValue,
            let status = storage.storage["status"]?.stringValue,
            let title = storage.storage["title"]?.stringValue
        else {
            throw BlazeDBError.invalidData(reason: "Missing required QueryObsDoc fields")
        }
        self.id = id
        self.status = status
        self.title = title
    }

    func toStorage() throws -> BlazeDataRecord {
        BlazeDataRecord([
            "id": .uuid(id),
            "status": .string(status),
            "title": .string(title)
        ])
    }
}
#endif
