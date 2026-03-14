import Foundation
import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class OverflowChainCrashAtomicityTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverflowAtomicity-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")
    }

    override func tearDownWithError() throws {
        let exts = ["", "meta", "wal", "backup", "txn_log.json"]
        for ext in exts {
            let target = ext.isEmpty ? tempURL! : tempURL!.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: target)
        }
    }

    func testPhase1_DeterministicMultiPageOverflowWrite() throws {
        let store = try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))
        let originalData = deterministicData(size: 20_000, seed: 0x5A)
        var nextPage = 1

        _ = try store.writePageWithOverflow(index: 0, plaintext: originalData) {
            defer { nextPage += 1 }
            return nextPage
        }

        let validation = store.validateOverflowChain(rootPageID: 0)
        XCTAssertEqual(validation, .valid, "Overflow chain must be structurally valid")

        let readData = try store.readPageWithOverflow(index: 0)
        XCTAssertNotNil(readData)
        XCTAssertEqual(readData?.count, originalData.count)
        XCTAssertEqual(readData, originalData)
    }

    func testPhase2_CrashInjectionHooks_AllOrNothingVisibility() throws {
        let hooks = [
            "afterBasePageWrite",
            "afterFirstOverflowPageWrite",
            "afterLastOverflowPageWrite",
            "afterOverflowMetadataUpdate",
            "afterWALAppendBeforeCommitMark"
        ]

        for hook in hooks {
            let result = try runCrashScenario(hook: hook)
            print("[CRASH_TEST] hook=\(hook) result=\(result.status)")
            XCTAssertTrue(result.elapsed < 1.0, "Read path should fail/return quickly (no retry loop)")
            XCTAssertTrue(result.status == "NOT_VISIBLE" || result.status == "FULLY_VISIBLE" || result.status == "CORRUPTION_DETECTED")
        }
    }

    func testPhase4_RetryPolicyHardening_ThrowsOnTruncatedChain() throws {
        let store = try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))
        let originalData = deterministicData(size: 20_000, seed: 0x44)
        var nextPage = 1
        let indices = try store.writePageWithOverflow(index: 0, plaintext: originalData) {
            defer { nextPage += 1 }
            return nextPage
        }
        XCTAssertGreaterThan(indices.count, 3, "Expected a multi-page overflow chain")

        try store.deletePage(index: indices[1])

        let start = Date()
        XCTAssertThrowsError(try store.readPageWithOverflow(index: 0)) { error in
            if case BlazeDBError.corruptedData = error {
                return
            }
            XCTFail("Expected BlazeDBError.corruptedData, got: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "Must fail fast without retry spiral")
    }

    func testPhase5_SingleWriterLockEnforcement() throws {
        let first = try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))
        XCTAssertNotNil(first)

        XCTAssertThrowsError(try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))) { error in
            if case BlazeDBError.concurrentProcessAccessNotSupported = error {
                return
            }
            if case BlazeDBError.permissionDenied = error {
                return
            }
            XCTFail("Second writer should fail lock acquisition, got: \(error)")
        }
    }

    func testPhase6_OrphanOverflowDetection() throws {
        let store = try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))
        let originalData = deterministicData(size: 20_000, seed: 0x33)
        var nextPage = 1
        _ = try store.writePageWithOverflow(index: 0, plaintext: originalData) {
            defer { nextPage += 1 }
            return nextPage
        }

        // Make chain unreachable from root main page.
        try store.deletePage(index: 0)

        let orphans = store.scanForOrphanOverflowPages()
        XCTAssertFalse(orphans.isEmpty, "Expected unreachable overflow pages to be detected")
    }

    // Child-only test entrypoint used by parent Process harness.
    func testChildOverflowCrashWriter() throws {
        guard ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CHILD"] == "1" else { return }
        guard let dbPath = ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_DB_PATH"] else {
            XCTFail("Missing child DB path")
            return
        }
        guard let hook = ProcessInfo.processInfo.environment["BLAZEDB_OVERFLOW_CRASH_HOOK"] else {
            XCTFail("Missing crash hook")
            return
        }

        let store = try PageStore(fileURL: URL(fileURLWithPath: dbPath), key: SymmetricKey(size: .bits256))

        if hook == "afterWALAppendBeforeCommitMark" {
            var tx = BlazeTransaction(store: store)
            try tx.write(pageID: 0, data: deterministicData(size: 512, seed: 0x19))
            try tx.commit()
            return
        }

        var nextPage = 1
        _ = try store.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0xAB)) {
            defer { nextPage += 1 }
            return nextPage
        }
    }

    private func runCrashScenario(hook: String) throws -> (status: String, elapsed: TimeInterval) {
        try? FileManager.default.removeItem(at: tempURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        process.arguments = ["-XCTest", "OverflowChainCrashAtomicityTests/testChildOverflowCrashWriter"]

        var env = ProcessInfo.processInfo.environment
        env["BLAZEDB_OVERFLOW_CHILD"] = "1"
        env["BLAZEDB_OVERFLOW_DB_PATH"] = tempURL.path
        env["BLAZEDB_OVERFLOW_CRASH_HOOK"] = hook
        env["BLAZEDB_OVERFLOW_CRASH_EXIT_CODE"] = "86"
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let store = try PageStore(fileURL: tempURL, key: SymmetricKey(size: .bits256))

        let expectedData: Data = hook == "afterWALAppendBeforeCommitMark"
            ? deterministicData(size: 512, seed: 0x19)
            : deterministicData(size: 20_000, seed: 0xAB)

        let start = Date()
        let status: String
        do {
            let readData = try store.readPageWithOverflow(index: 0)
            if readData == nil {
                status = "NOT_VISIBLE"
            } else if readData == expectedData {
                status = "FULLY_VISIBLE"
            } else {
                XCTFail("Partial visibility detected for hook \(hook)")
                status = "CORRUPTION_DETECTED"
            }
        } catch {
            if case BlazeDBError.corruptedData = error {
                status = "CORRUPTION_DETECTED"
            } else {
                XCTFail("Unexpected read error for hook \(hook): \(error)")
                status = "CORRUPTION_DETECTED"
            }
        }

        _ = store.validateOverflowChain(rootPageID: 0)
        _ = store.scanForOrphanOverflowPages()
        return (status, Date().timeIntervalSince(start))
    }

    private func deterministicData(size: Int, seed: UInt8) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(size)
        var value = seed
        for _ in 0..<size {
            value = value &* 31 &+ 17
            bytes.append(value)
        }
        return Data(bytes)
    }
}
