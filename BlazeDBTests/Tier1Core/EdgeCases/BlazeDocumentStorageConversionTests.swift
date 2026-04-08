//
//  BlazeDocumentStorageConversionTests.swift
//  BlazeDBTests
//
//  Regression tests for GitHub #37: BlazeDocument.storage must not hide conversion failures
//  without warning (typed APIs use toStorage() directly; the property logs and falls back).
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeDocumentStorageConversionTests: XCTestCase {

    /// Document whose toStorage() always fails — used for throwing APIs and .storage fallback behavior.
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

    func testDefaultStorageGetterMatchesToStorageWhenConversionSucceeds() throws {
        let bug = TestBug(title: "Storage parity", priority: 2, status: "closed", assignee: "a")
        let fromGetter = bug.storage
        let fromMethod = try bug.toStorage()
        XCTAssertEqual(fromGetter, fromMethod)
        XCTAssertFalse(fromGetter.storage.isEmpty)
    }

    /// When toStorage() fails, the default ``storage`` getter returns an empty record but must log so the failure is visible if logging is enabled.
    func testStorageGetterReturnsEmptyAndLogsWhenConversionFails() {
        var captured: [(String, BlazeLogLevel)] = []
        BlazeLogger.reset()
        BlazeLogger.level = .warn
        BlazeLogger.handler = { message, level in
            captured.append((message, level))
        }
        defer {
            BlazeLogger.reset()
        }

        let doc = FailingToStorageDoc()
        XCTAssertTrue(doc.storage.storage.isEmpty)

        XCTAssertFalse(captured.isEmpty, "Expected warn/error logs when .storage is used after toStorage() failure")
        let levels = Set(captured.map(\.1))
        XCTAssertTrue(levels.contains(.warn) || levels.contains(.error))
    }
}
