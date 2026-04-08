//
//  BlazeDocumentStorageConversionTests.swift
//  BlazeDBTests
//
//  Regression tests for GitHub #37: default BlazeDocument.storage must not return an empty
//  BlazeDataRecord when toStorage() fails.
//

import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class BlazeDocumentStorageConversionTests: XCTestCase {

    /// Document whose toStorage() always fails — used to assert throwing paths (not .storage, which traps).
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

    /// GitHub #37: when encoding succeeds, the default ``storage`` getter must match ``toStorage()`` (no silent empty record).
    func testDefaultStorageGetterMatchesToStorageWhenConversionSucceeds() throws {
        let bug = TestBug(title: "Storage parity", priority: 2, status: "closed", assignee: "a")
        let fromGetter = bug.storage
        let fromMethod = try bug.toStorage()
        XCTAssertEqual(fromGetter, fromMethod)
        XCTAssertFalse(fromGetter.storage.isEmpty)
    }
}
