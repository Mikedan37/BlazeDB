import XCTest

#if canImport(SwiftUI) && canImport(Combine) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI
@testable import BlazeDB

private struct StorableTask: BlazeStorable, Equatable {
    var id: UUID
    let title: String
    let priority: Int
}

@MainActor
final class BlazeStorableQueryTests: XCTestCase {
    func testSortWithoutFilter() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("storable-query-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")

        let db = try BlazeDBClient(
            name: "StorableQueryTests",
            fileURL: tempURL,
            password: "Test-Password-123"
        )

        defer {
            let extensions = ["", "meta", "indexes", "wal", "backup", "transaction_backup"]

            for ext in extensions {
                let url = ext.isEmpty
                    ? tempURL
                    : tempURL.deletingPathExtension().appendingPathExtension(ext)

                try? FileManager.default.removeItem(at: url)
            }
        }

        for priority in [3, 1, 5, 2, 4] {
            try await db.insert(
                StorableTask(
                    id: UUID(),
                    title: "Task \(priority)",
                    priority: priority
                )
            )
        }

        try await db.persist()

        let wrapper = BlazeStorableQuery<StorableTask>(
            db: db,
            kind: StorableTask.self,
            sortBy: "priority",
            descending: true
        )

        let observer = wrapper.projectedValue
        let deadline = Date().addingTimeInterval(2)

        while observer.isLoading && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(observer.isLoading, "Query timed out")
        XCTAssertNil(observer.error)
        XCTAssertEqual(observer.results.map(\.priority), [5, 4, 3, 2, 1])
    }
}
#endif
