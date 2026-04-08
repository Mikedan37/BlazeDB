//
//  BlazeDocumentStorageConversionTests.swift
//  BlazeDBTests
//
//  Regression tests for GitHub #37: BlazeDocument.storage logs on conversion failure and falls
//  back to an empty record; throwing APIs remain the correct persistence path.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeDocumentStorageConversionTests: XCTestCase {

    private struct FailingToStorageDoc: BlazeDocument {
        var id: UUID

        func toStorage() throws -> BlazeDataRecord {
            throw BlazeDBError.invalidData(reason: "intentional conversion failure")
        }

        init(from storage: BlazeDataRecord) throws {
            self.id = try storage.uuid("id")
        }

        init(id: UUID = UUID()) {
            self.id = id
        }
    }

    func testToStoragePropagatesConversionError() {
        let doc = FailingToStorageDoc()
        XCTAssertThrowsError(try doc.toStorage()) { error in
            guard case BlazeDBError.invalidData(let reason) = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
            XCTAssertTrue(reason.contains("intentional"))
        }
    }

    func testResolveStoragePropagatesSameErrorAsToStorage() {
        let doc = FailingToStorageDoc()
        XCTAssertThrowsError(try doc.resolveStorage()) { error in
            guard case BlazeDBError.invalidData(let reason) = error else {
                return XCTFail("Expected invalidData, got \(error)")
            }
            XCTAssertTrue(reason.contains("intentional"))
        }
    }

    func testResolveStorageMatchesToStorageForSuccessfulDocument() throws {
        let bug = TestBug(title: "t", priority: 1, status: "open")
        let viaToStorage = try bug.toStorage()
        let viaResolve = try bug.resolveStorage()
        XCTAssertEqual(viaToStorage, viaResolve)
    }

    /// Exercises the deprecated default `storage` getter; should match `toStorage()` when encoding succeeds.
    func testDefaultStorageGetterMatchesToStorageWhenConversionSucceeds() throws {
        let bug = TestBug(title: "Storage parity", priority: 2, status: "closed", assignee: "a")
        let fromGetter = bug.storage
        let fromMethod = try bug.toStorage()
        XCTAssertEqual(fromGetter, fromMethod)
        XCTAssertFalse(fromGetter.storage.isEmpty)
    }

    /// Fallback is still `[:]` for compatibility, but an error must be logged when the global level allows it.
    func testStorageReturnsEmptyOnConversionFailureAndLogsError() {
        var captured: [(String, BlazeLogLevel)] = []
        BlazeLogger.reset()
        BlazeLogger.level = .error
        BlazeLogger.handler = { message, level in
            captured.append((message, level))
        }
        defer {
            BlazeLogger.reset()
        }

        let doc = FailingToStorageDoc()
        XCTAssertTrue(doc.storage.storage.isEmpty)

        XCTAssertTrue(captured.contains { $0.1 == .error }, "Expected an error-level log when .storage fallback is used")
        XCTAssertTrue(
            captured.contains { $0.0.contains("BlazeDocument.storage fallback") },
            "Expected fallback log message; captured: \(captured.map(\.0))"
        )
    }
}
