import Foundation
import XCTest
@testable import BlazeDBCore

#if DEBUG
final class TransactionRecoveryRequiredTests: XCTestCase {
    private struct Forced: Error {}
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("recovery.blazedb") }
    private func open() throws -> BlazeDBClient {
        try BlazeDBClient(name: "recovery-required", fileURL: file, password: "Recovery-Required-2026!")
    }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        PageStore._setSynchronizeFailureForTests(false)
        try FileManager.default.removeItem(at: directory)
    }
    func testFailedRollbackRejectsWritesUntilReopenAndPreservesBackup() throws {
        let db = try open()
        let id = try db.insert(BlazeDataRecord(["marker": .string("baseline")]))
        try db.beginTransaction()
        try db.update(id: id, with: BlazeDataRecord(["marker": .string("uncommitted")]))
        PageStore._setSynchronizeFailureForTests(true)
        XCTAssertThrowsError(try db.rollbackTransaction())
        PageStore._setSynchronizeFailureForTests(false)
        let backup = try Data(contentsOf: db.transactionBackupURL)
        XCTAssertThrowsError(try db.insert(BlazeDataRecord(["marker": .string("must-not-succeed")])))
        XCTAssertThrowsError(try db.update(id: id, with: BlazeDataRecord(["marker": .string("must-not-succeed")])))
        XCTAssertThrowsError(try db.delete(id: id))
        XCTAssertThrowsError(try db.persist())
        XCTAssertThrowsError(try db.createIndex(on: "marker"))
        XCTAssertThrowsError(try db.beginTransaction())
        XCTAssertEqual(try Data(contentsOf: db.transactionBackupURL), backup)
        try db.close()
        let recovered = try open()
        defer { try? recovered.close() }
        XCTAssertEqual(try recovered.fetch(id: id)?.storage["marker"]?.stringValue, "baseline")
        XCTAssertEqual(try recovered.fetchAll().count, 1)
        try recovered.transaction { _ = try recovered.insert(BlazeDataRecord(["marker": .string("after-recovery")])) }
        XCTAssertEqual(try recovered.fetchAll().count, 2)
    }
    func testTransactionReportsRollbackFailureInsteadOfOnlyBlockError() throws {
        let db = try open()
        defer { PageStore._setSynchronizeFailureForTests(false); try? db.close() }
        _ = try db.insert(BlazeDataRecord(["marker": .string("baseline")]))
        XCTAssertThrowsError(try db.transaction {
            _ = try db.insert(BlazeDataRecord(["marker": .string("uncommitted")]))
            PageStore._setSynchronizeFailureForTests(true)
            throw Forced()
        }) { error in
            let recovery = error as? BlazeTransactionRecoveryError
            XCTAssertTrue(recovery?.operationError is Forced)
            XCTAssertNotNil(recovery?.rollbackError)
        }
    }
    func testAsyncTransactionReportsRollbackFailureAndRejectsIndexWrites() async throws {
        let db = try open()
        defer { PageStore._setSynchronizeFailureForTests(false); try? db.close() }
        do {
            try await db.transaction {
                await Task.yield()
                PageStore._setSynchronizeFailureForTests(true)
                throw Forced()
            }
            XCTFail("expected transaction failure")
        } catch {
            let recovery = error as? BlazeTransactionRecoveryError
            XCTAssertTrue(recovery?.operationError is Forced)
            XCTAssertNotNil(recovery?.rollbackError)
        }
        PageStore._setSynchronizeFailureForTests(false)
        do { try await db.createIndex(on: "marker"); XCTFail("index write must be rejected") } catch {}
        do { try await db.createCompoundIndex(on: ["marker", "id"]); XCTFail("index write must be rejected") } catch {}
        do { _ = try await db.insert(BlazeDataRecord(["marker": .string("rejected")])); XCTFail("insert must be rejected") } catch {}
    }

    func testPerformTransactionReportsBothFailures() async throws {
        let db = try open()
        defer { PageStore._setSynchronizeFailureForTests(false); try? db.close() }
        do {
            try await db.performTransaction {
                PageStore._setSynchronizeFailureForTests(true)
                throw Forced()
            }
            XCTFail("expected transaction failure")
        } catch {
            let recovery = error as? BlazeTransactionRecoveryError
            XCTAssertTrue(recovery?.operationError is Forced)
            XCTAssertNotNil(recovery?.rollbackError)
        }
    }

}

#endif
