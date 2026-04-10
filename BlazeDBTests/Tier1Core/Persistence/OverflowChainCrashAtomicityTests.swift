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
    private var tempURL: URL?

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverflowAtomicity-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")
    }

    override func tearDownWithError() throws {
        guard let base = tempURL else {
            try super.tearDownWithError()
            return
        }
        let exts = ["", "meta", "wal", "backup", "txn_log.json"]
        for ext in exts {
            let target = ext.isEmpty ? base : base.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: target)
        }
        tempURL = nil
        try super.tearDownWithError()
    }

    func testPhase1_DeterministicMultiPageOverflowWrite() throws {
        let store = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))
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
        let store = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))
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
        let first = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))
        XCTAssertNotNil(first)

        XCTAssertThrowsError(try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))) { error in
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
        let store = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))
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

    func testLegacyOverflowHeuristic_IsCompatibilityModeOnly() throws {
        let dbURL = try requireFixture(tempURL)
        let key = SymmetricKey(size: .bits256)
        let storeDefault = try PageStore(fileURL: dbURL, key: key)

        var nextPage = 1
        _ = try storeDefault.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0xC1)) {
            defer { nextPage += 1 }
            return nextPage
        }

        var legacyMain = try XCTUnwrap(storeDefault.readPage(index: 0))
        let firstOverflow = try parseFirstOverflowIndexFromV2Trailer(legacyMain)
        try rewriteMainPageAsLegacyPointer(mainPageData: &legacyMain, firstOverflowIndex: firstOverflow)
        try storeDefault.writePage(index: 0, plaintext: legacyMain)
        storeDefault.close()

        let storeReadDefault = try PageStore(fileURL: dbURL, key: key)
        let readDefault = try storeReadDefault.readPageWithOverflow(index: 0)
        storeReadDefault.close()
        XCTAssertEqual(readDefault, legacyMain, "Default mode should not traverse legacy overflow pointer heuristic")

        let storeCompat = try PageStore(
            fileURL: dbURL,
            key: key,
            enableLegacyOverflowPointerHeuristicCompatibilityMode: true
        )
        let readCompat = try XCTUnwrap(storeCompat.readPageWithOverflow(index: 0))
        XCTAssertGreaterThan(readCompat.count, legacyMain.count, "Compatibility mode should traverse legacy overflow chain")
    }

    func testValidateOverflowChain_V2_MissingAndCircular() throws {
        let storeMissing = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))
        var nextMissing = 1
        let missingIndices = try storeMissing.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0x71)) {
            defer { nextMissing += 1 }
            return nextMissing
        }
        XCTAssertGreaterThan(missingIndices.count, 2)
        try storeMissing.deletePage(index: missingIndices[1])
        if case .truncatedChain = storeMissing.validateOverflowChain(rootPageID: 0) {
            // expected
        } else {
            XCTFail("Expected v2 missing-page validation failure")
        }

        let cycleURL = dbURL(named: "overflow-v2-cycle")
        let storeCycle = try PageStore(fileURL: cycleURL, key: SymmetricKey(size: .bits256))
        var nextCycle = 1
        let cycleIndices = try storeCycle.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0x72)) {
            defer { nextCycle += 1 }
            return nextCycle
        }
        XCTAssertGreaterThan(cycleIndices.count, 2)
        try overwriteOverflowNextPointer(fileURL: cycleURL, pageIndex: cycleIndices[1], nextPageIndex: UInt32(cycleIndices[1]))
        XCTAssertEqual(storeCycle.validateOverflowChain(rootPageID: 0), .cycleDetected(cycleIndices[1]))
    }

    func testValidateOverflowChain_Legacy_MissingAndCircular_WithCompatibilityMode() throws {
        let key = SymmetricKey(size: .bits256)

        let missingURL = dbURL(named: "overflow-legacy-missing")
        let storeLegacyMissing = try PageStore(
            fileURL: missingURL,
            key: key,
            enableLegacyOverflowPointerHeuristicCompatibilityMode: true
        )
        var nextMissing = 1
        let missingIndices = try storeLegacyMissing.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0x81)) {
            defer { nextMissing += 1 }
            return nextMissing
        }
        var legacyMainMissing = try XCTUnwrap(storeLegacyMissing.readPage(index: 0))
        let firstMissing = try parseFirstOverflowIndexFromV2Trailer(legacyMainMissing)
        try rewriteMainPageAsLegacyPointer(mainPageData: &legacyMainMissing, firstOverflowIndex: firstMissing)
        try storeLegacyMissing.writePage(index: 0, plaintext: legacyMainMissing)
        try storeLegacyMissing.deletePage(index: missingIndices[1])
        if case .truncatedChain = storeLegacyMissing.validateOverflowChain(rootPageID: 0) {
            // expected
        } else {
            XCTFail("Expected legacy missing-page validation failure")
        }

        let cycleURL = dbURL(named: "overflow-legacy-cycle")
        let storeLegacyCycle = try PageStore(
            fileURL: cycleURL,
            key: key,
            enableLegacyOverflowPointerHeuristicCompatibilityMode: true
        )
        var nextCycle = 1
        let cycleIndices = try storeLegacyCycle.writePageWithOverflow(index: 0, plaintext: deterministicData(size: 20_000, seed: 0x82)) {
            defer { nextCycle += 1 }
            return nextCycle
        }
        var legacyMainCycle = try XCTUnwrap(storeLegacyCycle.readPage(index: 0))
        let firstCycle = try parseFirstOverflowIndexFromV2Trailer(legacyMainCycle)
        try rewriteMainPageAsLegacyPointer(mainPageData: &legacyMainCycle, firstOverflowIndex: firstCycle)
        try storeLegacyCycle.writePage(index: 0, plaintext: legacyMainCycle)
        try overwriteOverflowNextPointer(fileURL: cycleURL, pageIndex: cycleIndices[1], nextPageIndex: UInt32(cycleIndices[1]))
        XCTAssertEqual(storeLegacyCycle.validateOverflowChain(rootPageID: 0), .cycleDetected(cycleIndices[1]))
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

        // Proves the subprocess actually hit this entrypoint (corelibs-xctest vs -XCTest argv debugging).
        let marker = "[OVERFLOW_CHILD] testChildOverflowCrashWriter hook=\(hook)\n"
        FileHandle.standardError.write(Data(marker.utf8))

        let store = try PageStore(fileURL: URL(fileURLWithPath: dbPath), key: SymmetricKey(size: .bits256))

        if hook == "afterWALAppendBeforeCommitMark" {
            let tx = BlazeTransaction(store: store)
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
        try? FileManager.default.removeItem(at: try requireFixture(tempURL))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        // macOS/iOS/etc.: keep Xcode-style `-XCTest` (unchanged from pre-portability fix — Tier1 macOS CI).
        // Linux/Android: corelibs-xctest rejects `-XCTest`; use one positional filter (see `xctest --help`).
        // Module prefix must match SPM test target name (`BlazeDB_Tier1` in Package.swift).
        #if os(Linux) || os(Android)
        process.arguments = ["BlazeDB_Tier1.OverflowChainCrashAtomicityTests/testChildOverflowCrashWriter"]
        #else
        process.arguments = ["-XCTest", "OverflowChainCrashAtomicityTests/testChildOverflowCrashWriter"]
        #endif

        var env = ProcessInfo.processInfo.environment
        env["BLAZEDB_OVERFLOW_CHILD"] = "1"
        env["BLAZEDB_OVERFLOW_DB_PATH"] = try requireFixture(tempURL).path
        env["BLAZEDB_OVERFLOW_CRASH_HOOK"] = hook
        env["BLAZEDB_OVERFLOW_CRASH_EXIT_CODE"] = "86"
        process.environment = env

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        try process.run()

        let waitResult = completion.wait(timeout: .now() + .seconds(60))
        if waitResult == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + .seconds(2))
            XCTFail("Crash scenario child process timed out after 60s for hook: \(hook)")
            return (status: "TIMEOUT", elapsed: 60.0)
        }

        let store = try PageStore(fileURL: try requireFixture(tempURL), key: SymmetricKey(size: .bits256))

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
                // Crash-injected WAL/page state on Linux often surfaces as swift-crypto decrypt/auth failures
                // (not always mapped to `corruptedData`); treat as an expected "bad read" outcome.
                let text = String(describing: error)
                if text.contains("CoreCrypto") || text.contains("CryptoKit") || text.contains("Crypto.")
                    || text.contains("underlyingCoreCryptoError") {
                    status = "CORRUPTION_DETECTED"
                } else {
                    XCTFail("Unexpected read error for hook \(hook): \(error)")
                    status = "CORRUPTION_DETECTED"
                }
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

    private func dbURL(named suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OverflowAtomicity-\(suffix)-\(UUID().uuidString)")
            .appendingPathExtension("blazedb")
    }

    private func parseFirstOverflowIndexFromV2Trailer(_ mainPageData: Data) throws -> UInt32 {
        let trailerSize = 32
        guard mainPageData.count >= trailerSize else {
            throw NSError(domain: "OverflowTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "main page too short for v2 trailer"])
        }
        let start = mainPageData.count - trailerSize
        return (UInt32(mainPageData[start + 8]) << 24)
            | (UInt32(mainPageData[start + 9]) << 16)
            | (UInt32(mainPageData[start + 10]) << 8)
            | UInt32(mainPageData[start + 11])
    }

    private func rewriteMainPageAsLegacyPointer(mainPageData: inout Data, firstOverflowIndex: UInt32) throws {
        let trailerSize = 32
        guard mainPageData.count >= trailerSize else {
            throw NSError(domain: "OverflowTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "main page too short for legacy rewrite"])
        }
        let trailerStart = mainPageData.count - trailerSize
        mainPageData.replaceSubrange(trailerStart..<(trailerStart + 4), with: [0, 0, 0, 0]) // disable v2 magic
        let pointerOffset = mainPageData.count - 4
        let bytes: [UInt8] = [
            UInt8((firstOverflowIndex >> 24) & 0xff),
            UInt8((firstOverflowIndex >> 16) & 0xff),
            UInt8((firstOverflowIndex >> 8) & 0xff),
            UInt8(firstOverflowIndex & 0xff)
        ]
        mainPageData.replaceSubrange(pointerOffset..<mainPageData.count, with: bytes)
    }

    private func overwriteOverflowNextPointer(fileURL: URL, pageIndex: Int, nextPageIndex: UInt32) throws {
        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }
        let pageOffset = UInt64(pageIndex * 4096)
        try fileHandle.seek(toOffset: pageOffset + 8)
        var nextBE = nextPageIndex.bigEndian
        try fileHandle.write(contentsOf: Data(bytes: &nextBE, count: 4))
    }
}
