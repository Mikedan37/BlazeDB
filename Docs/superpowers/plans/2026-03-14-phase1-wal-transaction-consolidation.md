# Phase 1: Transaction & WAL Consolidation — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate to one WAL, one transaction model. Delete TransactionLog. Delete file-copy transactions. Single authoritative durability path.

**Architecture:** `BlazeTransaction` → `TransactionContext` (in-memory staging) → `DurabilityManager` (WAL append + fsync + page mutation) → `RecoveryManager` (on open: scan WAL, redo committed entries only). The ordering invariant WAL-append → fsync → page-mutate is the single most important rule in the engine.

**Tech Stack:** Swift 6, POSIX file I/O (pread/pwrite/fsync), CRC32 (zlib)

**Spec:** `docs/superpowers/specs/2026-03-14-blazedb-oss-cleanup-design.md` — Phase 1

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `BlazeDB/Storage/WALEntry.swift` | WALEntry struct, WALOperation enum, binary serialization/deserialization |
| `BlazeDB/Storage/DurabilityManager.swift` | WAL append with LSN tracking, fsync, page mutation, checkpoint, batch commit |
| `BlazeDB/Storage/RecoveryManager.swift` | WAL scan, committed-entry detection, redo, torn-write handling |
| `BlazeDBTests/Tier0Core/Durability/DurabilityManagerTests.swift` | Unit tests for DurabilityManager |
| `BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift` | Crash recovery tests |
| `BlazeDBTests/Tier0Core/Durability/WALEntryTests.swift` | Serialization round-trip tests |

### Modified Files
| File | Change |
|------|--------|
| `BlazeDB/Storage/WriteAheadLog.swift` | Refactor: becomes internal to DurabilityManager, new entry format |
| `BlazeDB/Storage/PageStore.swift` | Replace WAL init/replay with DurabilityManager; remove direct WAL dependency |
| `BlazeDB/Transactions/BlazeTransaction.swift` | Use DurabilityManager instead of TransactionLog |
| `BlazeDB/Transactions/TransactionContext.swift` | Remove TransactionLog dependency; work with DurabilityManager |
| `BlazeDB/Exports/BlazeDBClient.swift` | Delete file-copy transaction methods; delegate to BlazeTransaction |

### Deleted Files
| File | Reason |
|------|--------|
| `BlazeDB/Transactions/TransactionLog.swift` | Replaced by DurabilityManager — confirmed as durability scaffolding only |

---

## Chunk 1: WAL Entry Schema & Serialization

### Task 1: WALEntry binary format

**Files:**
- Create: `BlazeDB/Storage/WALEntry.swift`
- Create: `BlazeDBTests/Tier0Core/Durability/WALEntryTests.swift`

- [ ] **Step 1: Write the failing test for WALEntry round-trip serialization**

```swift
// BlazeDBTests/Tier0Core/Durability/WALEntryTests.swift
import XCTest
@testable import BlazeDBCore

final class WALEntryTests: XCTestCase {

    func testWriteEntryRoundTrip() throws {
        let entry = WALEntry(
            lsn: 42,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 7,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let data = entry.serialize()
        let decoded = try WALEntry.deserialize(from: data)

        XCTAssertEqual(decoded.lsn, entry.lsn)
        XCTAssertEqual(decoded.transactionID, entry.transactionID)
        XCTAssertEqual(decoded.operation, entry.operation)
        XCTAssertEqual(decoded.pageIndex, entry.pageIndex)
        XCTAssertEqual(decoded.payload, entry.payload)
    }

    func testBeginCommitAbortCheckpointRoundTrip() throws {
        for op in [WALOperation.begin, .commit, .abort, .checkpoint] {
            let entry = WALEntry(
                lsn: 1,
                transactionID: UUID(),
                operation: op,
                pageIndex: 0,
                payload: Data()
            )
            let data = entry.serialize()
            let decoded = try WALEntry.deserialize(from: data)
            XCTAssertEqual(decoded.operation, op, "Failed for operation: \(op)")
        }
    }

    func testCRC32Validation() throws {
        let entry = WALEntry(
            lsn: 1,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 0,
            payload: Data([0x01, 0x02])
        )
        var data = entry.serialize()
        // Corrupt one byte in the payload region
        data[data.count - 3] ^= 0xFF

        XCTAssertThrowsError(try WALEntry.deserialize(from: data)) { error in
            XCTAssertTrue("\(error)".contains("crc"), "Expected CRC error, got: \(error)")
        }
    }

    func testTruncatedDataFails() {
        let entry = WALEntry(
            lsn: 1,
            transactionID: UUID(),
            operation: .write,
            pageIndex: 0,
            payload: Data([0x01])
        )
        let data = entry.serialize()
        let truncated = data.prefix(data.count - 5)

        XCTAssertThrowsError(try WALEntry.deserialize(from: truncated))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WALEntryTests 2>&1 | tail -5`
Expected: FAIL — `WALEntry` type does not exist

- [ ] **Step 3: Implement WALEntry**

```swift
// BlazeDB/Storage/WALEntry.swift
import Foundation
import zlib

/// Operations that can appear in the WAL.
/// Recovery depends on explicit transaction boundaries: a transaction is committed
/// if and only if a .commit record with matching transactionID exists.
public enum WALOperation: UInt8, Sendable, Equatable {
    case begin      = 0
    case write      = 1
    case delete     = 2
    case commit     = 3
    case abort      = 4
    case checkpoint = 5
}

/// A single entry in the Write-Ahead Log.
///
/// Binary format (little-endian):
/// ```
/// [magic 4B "WALV"] [lsn UInt64] [txID 16B UUID] [operation UInt8]
/// [pageIndex UInt32] [payloadLen UInt32] [payload N bytes] [crc32 UInt32]
/// ```
///
/// Total header: 4 + 8 + 16 + 1 + 4 + 4 = 37 bytes + payload + 4 byte CRC = 41 + payload
public struct WALEntry: Sendable, Equatable {
    public static let magic: [UInt8] = [0x57, 0x41, 0x4C, 0x56] // "WALV"
    static let headerSize = 37 // magic(4) + lsn(8) + uuid(16) + op(1) + pageIdx(4) + payloadLen(4)

    public let lsn: UInt64
    public let transactionID: UUID
    public let operation: WALOperation
    public let pageIndex: UInt32
    public let payload: Data
    // CRC32 is computed, not stored in the struct

    public init(lsn: UInt64, transactionID: UUID, operation: WALOperation, pageIndex: UInt32, payload: Data) {
        self.lsn = lsn
        self.transactionID = transactionID
        self.operation = operation
        self.pageIndex = pageIndex
        self.payload = payload
    }

    /// Serialize to binary format for on-disk storage.
    public func serialize() -> Data {
        var data = Data(capacity: Self.headerSize + payload.count + 4)

        // Magic
        data.append(contentsOf: Self.magic)

        // LSN (little-endian)
        var lsnLE = lsn.littleEndian
        data.append(Data(bytes: &lsnLE, count: 8))

        // Transaction ID (16 bytes, uuid_t)
        let uuid = transactionID.uuid
        data.append(contentsOf: [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11,
            uuid.12, uuid.13, uuid.14, uuid.15
        ])

        // Operation
        data.append(operation.rawValue)

        // Page index (little-endian)
        var pageLE = pageIndex.littleEndian
        data.append(Data(bytes: &pageLE, count: 4))

        // Payload length + payload
        var lenLE = UInt32(payload.count).littleEndian
        data.append(Data(bytes: &lenLE, count: 4))
        data.append(payload)

        // CRC32 over everything before this point
        let crc = Self.computeCRC32(data)
        var crcLE = crc.littleEndian
        data.append(Data(bytes: &crcLE, count: 4))

        return data
    }

    /// Deserialize from binary data. Validates magic, bounds, and CRC32.
    public static func deserialize(from data: Data) throws -> WALEntry {
        guard data.count >= headerSize + 4 else {
            throw WALError.truncatedEntry(expected: headerSize + 4, actual: data.count)
        }

        // Validate magic
        let magicBytes = [UInt8](data.prefix(4))
        guard magicBytes == magic else {
            throw WALError.invalidMagic(found: magicBytes)
        }

        // Read header fields
        let lsn = data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 4, as: UInt64.self).littleEndian
        }

        let uuidBytes = data.subdata(in: 12..<28)
        let uuid = uuidBytes.withUnsafeBytes { buf in
            let t = buf.bindMemory(to: uuid_t.self).baseAddress!.pointee
            return UUID(uuid: t)
        }

        guard let operation = WALOperation(rawValue: data[28]) else {
            throw WALError.unknownOperation(data[28])
        }

        let pageIndex = data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 29, as: UInt32.self).littleEndian
        }

        let payloadLen = data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 33, as: UInt32.self).littleEndian
        }

        let expectedSize = headerSize + Int(payloadLen) + 4
        guard data.count >= expectedSize else {
            throw WALError.truncatedEntry(expected: expectedSize, actual: data.count)
        }

        let payload = data.subdata(in: headerSize..<(headerSize + Int(payloadLen)))

        // Validate CRC32
        let crcOffset = headerSize + Int(payloadLen)
        let storedCRC = data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: crcOffset, as: UInt32.self).littleEndian
        }
        let computedCRC = computeCRC32(data.prefix(crcOffset))
        guard storedCRC == computedCRC else {
            throw WALError.crcMismatch(stored: storedCRC, computed: computedCRC)
        }

        return WALEntry(
            lsn: lsn,
            transactionID: uuid,
            operation: operation,
            pageIndex: pageIndex,
            payload: payload
        )
    }

    /// Total serialized size of this entry.
    public var serializedSize: Int {
        Self.headerSize + payload.count + 4
    }

    /// Read the next entry from a Data buffer starting at the given offset.
    /// Returns the entry and the offset of the next entry.
    public static func readNext(from data: Data, at offset: Int) throws -> (WALEntry, Int) {
        guard offset + headerSize + 4 <= data.count else {
            throw WALError.truncatedEntry(expected: headerSize + 4, actual: data.count - offset)
        }

        // Read payload length from the header to determine full entry size.
        // Use withUnsafeBytes on the original data with explicit offset — avoids
        // Data.suffix(from:) slice rebase issues with bridged NSData.
        let payloadLen = data.withUnsafeBytes { buf in
            buf.load(fromByteOffset: offset + 33, as: UInt32.self).littleEndian
        }

        let entrySize = headerSize + Int(payloadLen) + 4
        guard offset + entrySize <= data.count else {
            throw WALError.truncatedEntry(expected: entrySize, actual: data.count - offset)
        }

        let entryData = data.subdata(in: offset..<(offset + entrySize))
        let entry = try deserialize(from: entryData)
        return (entry, offset + entrySize)
    }

    static func computeCRC32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buf in
            let crc = zlib.crc32(0, buf.bindMemory(to: UInt8.self).baseAddress, uInt(buf.count))
            return UInt32(crc)
        }
    }
}

/// Errors from WAL entry parsing.
public enum WALError: Error, CustomStringConvertible {
    case invalidMagic(found: [UInt8])
    case truncatedEntry(expected: Int, actual: Int)
    case unknownOperation(UInt8)
    case crcMismatch(stored: UInt32, computed: UInt32)
    case midLogCorruption(atOffset: Int, lsn: UInt64)
    case recoveryFailed(reason: String, underlyingError: Error?)

    public var description: String {
        switch self {
        case .invalidMagic(let found): return "Invalid WAL magic: \(found)"
        case .truncatedEntry(let exp, let act): return "Truncated WAL entry: expected \(exp) bytes, got \(act)"
        case .unknownOperation(let op): return "Unknown WAL operation: \(op)"
        case .crcMismatch(let s, let c): return "WAL crc mismatch: stored=\(s) computed=\(c)"
        case .midLogCorruption(let off, let lsn): return "WAL corruption at offset \(off), last valid LSN \(lsn)"
        case .recoveryFailed(let r, let e): return "WAL recovery failed: \(r), underlying: \(String(describing: e))"
        }
    }
}
```

- [ ] **Step 4: Add WALEntryTests to Package.swift test target**

Add `WALEntryTests.swift` path to `BlazeDB_Tier0` test target sources (or ensure the `Tier0Core/Durability/` directory is included).

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter WALEntryTests 2>&1 | tail -10`
Expected: All 4 tests PASS

- [ ] **Step 6: Commit**

```bash
git add BlazeDB/Storage/WALEntry.swift BlazeDBTests/Tier0Core/Durability/WALEntryTests.swift Package.swift
git commit -m "feat: add WALEntry binary format with CRC32 validation

New WAL entry schema with LSN, transactionID, operation type,
pageIndex, and payload. Supports begin/write/delete/commit/abort/
checkpoint operations. CRC32 validated on deserialize.

Phase 1, Task 1 of WAL consolidation."
```

---

## Chunk 2: DurabilityManager

### Task 2: DurabilityManager core — append, LSN tracking, fsync

**Files:**
- Create: `BlazeDB/Storage/DurabilityManager.swift`
- Create: `BlazeDBTests/Tier0Core/Durability/DurabilityManagerTests.swift`

- [ ] **Step 1: Write the failing test for DurabilityManager append + read-back**

```swift
// BlazeDBTests/Tier0Core/Durability/DurabilityManagerTests.swift
import XCTest
@testable import BlazeDBCore

final class DurabilityManagerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-dm-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAppendAndReadBack() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        let lsn1 = try dm.appendBegin(transactionID: txID)
        let lsn2 = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xAA, 0xBB]))
        let lsn3 = try dm.appendCommit(transactionID: txID)

        XCTAssertEqual(lsn1, 1)
        XCTAssertEqual(lsn2, 2)
        XCTAssertEqual(lsn3, 3)
        XCTAssertEqual(dm.currentLSN, 3)

        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].operation, .begin)
        XCTAssertEqual(entries[1].operation, .write)
        XCTAssertEqual(entries[1].pageIndex, 5)
        XCTAssertEqual(entries[2].operation, .commit)
    }

    func testLSNMonotonicallyIncreases() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        var lastLSN: UInt64 = 0
        for _ in 0..<100 {
            let lsn = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
            XCTAssertGreaterThan(lsn, lastLSN)
            lastLSN = lsn
        }
    }

    func testBatchAppendSingleFsync() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        // Batch of writes followed by single commit — should be efficient
        _ = try dm.appendBegin(transactionID: txID)
        for i: UInt32 in 0..<10 {
            _ = try dm.appendWrite(transactionID: txID, pageIndex: i, data: Data(repeating: UInt8(i), count: 64))
        }
        _ = try dm.appendCommit(transactionID: txID)

        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 12) // 1 begin + 10 writes + 1 commit
    }

    func testAbortWritesAbortRecord() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: Data([0x01]))
        _ = try dm.appendAbort(transactionID: txID)

        let entries = try dm.readAllEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[2].operation, .abort)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DurabilityManagerTests 2>&1 | tail -5`
Expected: FAIL — `DurabilityManager` does not exist

- [ ] **Step 3: Implement DurabilityManager**

```swift
// BlazeDB/Storage/DurabilityManager.swift
import Foundation
import zlib

/// Manages WAL durability: append, fsync, checkpoint, LSN tracking.
///
/// The ordering invariant is enforced here:
///   1. WAL append
///   2. fsync
///   3. Page mutation (caller responsibility after appendWrite returns)
///
/// This is the SINGLE source of durability in BlazeDB.
public final class DurabilityManager: @unchecked Sendable {

    private let walURL: URL
    private let fileHandle: FileHandle
    private var _currentLSN: UInt64 = 0
    private var _lastCheckpointLSN: UInt64 = 0
    private let lock = NSLock()

    // Checkpoint trigger thresholds
    private var entriesSinceCheckpoint: Int = 0
    public var checkpointEntryThreshold: Int = 10_000
    public var checkpointSizeThreshold: Int64 = 64 * 1024 * 1024 // 64 MB

    /// Current LSN (monotonically increasing).
    public var currentLSN: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _currentLSN
    }

    /// LSN of the last successful checkpoint.
    public var lastCheckpointLSN: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _lastCheckpointLSN
    }

    /// Initialize DurabilityManager, creating WAL file if needed.
    /// Scans existing WAL to recover currentLSN.
    public init(walURL: URL) throws {
        self.walURL = walURL

        if !FileManager.default.fileExists(atPath: walURL.path) {
            FileManager.default.createFile(atPath: walURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forUpdating: walURL)

        // Recover LSN from existing entries
        let entries = try Self.scanEntries(from: walURL)
        if let lastEntry = entries.last {
            _currentLSN = lastEntry.lsn
        }

        // Find last checkpoint LSN
        for entry in entries.reversed() {
            if entry.operation == .checkpoint {
                _lastCheckpointLSN = entry.lsn
                break
            }
        }
    }

    deinit {
        try? fileHandle.close()
    }

    // MARK: - Append Operations

    @discardableResult
    public func appendBegin(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .begin, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    @discardableResult
    public func appendWrite(transactionID: UUID, pageIndex: UInt32, data: Data) throws -> UInt64 {
        try appendEntry(operation: .write, transactionID: transactionID, pageIndex: pageIndex, payload: data)
    }

    @discardableResult
    public func appendDelete(transactionID: UUID, pageIndex: UInt32) throws -> UInt64 {
        try appendEntry(operation: .delete, transactionID: transactionID, pageIndex: pageIndex, payload: Data())
    }

    @discardableResult
    public func appendCommit(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .commit, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    @discardableResult
    public func appendAbort(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .abort, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    // MARK: - Core Append (enforces WAL-before-mutate)

    /// Append a WAL entry. Fsyncs only on commit, abort, or checkpoint —
    /// begin/write/delete are buffered to disk without fsync. This groups
    /// multiple writes behind a single fsync on commit (batch optimization).
    private func appendEntry(operation: WALOperation, transactionID: UUID, pageIndex: UInt32, payload: Data) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        _currentLSN += 1
        let entry = WALEntry(
            lsn: _currentLSN,
            transactionID: transactionID,
            operation: operation,
            pageIndex: pageIndex,
            payload: payload
        )

        let data = entry.serialize()

        // Seek to end and write (kernel buffer, not yet durable)
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)

        // fsync only on transaction boundary operations.
        // begin/write/delete are written to kernel buffers but not fsynced —
        // if we crash mid-transaction, the incomplete transaction is discarded
        // during recovery (no .commit record). This is correct and fast.
        let needsFsync = (operation == .commit || operation == .abort || operation == .checkpoint)
        if needsFsync {
            try fileHandle.synchronize()
        }

        entriesSinceCheckpoint += 1

        return _currentLSN
    }

    // MARK: - Read

    /// Read all entries from the WAL file.
    public func readAllEntries() throws -> [WALEntry] {
        try Self.scanEntries(from: walURL)
    }

    /// Scan WAL file and return all valid entries.
    /// Stops at first invalid trailing entry (torn write).
    /// Throws on mid-log corruption.
    public static func scanEntries(from url: URL) throws -> [WALEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        var entries: [WALEntry] = []
        var offset = 0
        var lastValidLSN: UInt64 = 0

        while offset < data.count {
            // Check if remaining data is too small for even a header
            if offset + WALEntry.headerSize + 4 > data.count {
                // Trailing partial entry — truncated write, safe to ignore
                break
            }

            do {
                let (entry, nextOffset) = try WALEntry.readNext(from: data, at: offset)

                // Verify LSN monotonicity
                if entry.lsn <= lastValidLSN && lastValidLSN > 0 {
                    throw WALError.midLogCorruption(atOffset: offset, lsn: lastValidLSN)
                }

                entries.append(entry)
                lastValidLSN = entry.lsn
                offset = nextOffset
            } catch let error as WALError {
                switch error {
                case .truncatedEntry, .invalidMagic, .crcMismatch:
                    // Determine if this is a torn trailing write or mid-log corruption.
                    // Rule: if there are enough remaining bytes for another full minimum-size
                    // entry after this failed parse, treat as mid-log corruption (not a torn tail).
                    // A torn tail is only the last few bytes of the file.
                    let remainingAfterOffset = data.count - offset
                    let minEntrySize = WALEntry.headerSize + 4 // header + CRC, zero payload
                    if remainingAfterOffset > minEntrySize * 2 {
                        // Significant data remains — this is mid-log corruption
                        throw WALError.midLogCorruption(atOffset: offset, lsn: lastValidLSN)
                    }
                    // Small trailing fragment — torn write, safe to ignore
                    break
                default:
                    throw error
                }
                break
            }
        }

        return entries
    }

    // MARK: - Checkpoint

    /// Whether a checkpoint should be triggered based on configured thresholds.
    public var shouldCheckpoint: Bool {
        lock.lock()
        defer { lock.unlock() }

        if entriesSinceCheckpoint >= checkpointEntryThreshold {
            return true
        }

        if let fileSize = try? FileManager.default.attributesOfItem(atPath: walURL.path)[.size] as? Int64,
           fileSize >= checkpointSizeThreshold {
            return true
        }

        return false
    }

    /// Record a checkpoint at the current LSN and truncate the WAL.
    /// Caller MUST ensure all pages up to currentLSN are durable on disk before calling.
    ///
    /// Checkpoint strategy: persist lastCheckpointLSN to a sibling metadata file,
    /// then truncate the WAL. The checkpoint record is NOT written into the WAL
    /// being truncated — it would be immediately destroyed. The metadata file is
    /// the durable record of the checkpoint LSN.
    public func checkpoint() throws {
        lock.lock()
        let lsn = _currentLSN
        lock.unlock()

        // Persist checkpoint LSN to metadata file (sibling of WAL)
        let metaURL = walURL.deletingPathExtension().appendingPathExtension("wal-meta")
        let metaData = withUnsafeBytes(of: lsn.littleEndian) { Data($0) }
        try metaData.write(to: metaURL, options: .atomic)

        // Truncate WAL — all entries are now durable in the main file
        fileHandle.truncateFile(atOffset: 0)
        try fileHandle.synchronize()

        lock.lock()
        _lastCheckpointLSN = lsn
        entriesSinceCheckpoint = 0
        lock.unlock()
    }

    /// Close the WAL file handle.
    public func close() throws {
        try fileHandle.close()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DurabilityManagerTests 2>&1 | tail -10`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add BlazeDB/Storage/DurabilityManager.swift BlazeDBTests/Tier0Core/Durability/DurabilityManagerTests.swift
git commit -m "feat: add DurabilityManager with LSN tracking and checkpoint

Single WAL append path with fsync guarantee. Monotonic LSN.
Configurable checkpoint thresholds (entry count + file size).
Batch-friendly: multiple appends share fsync on commit.

Phase 1, Task 2 of WAL consolidation."
```

---

### Task 3: RecoveryManager — committed-entry redo

**Files:**
- Create: `BlazeDB/Storage/RecoveryManager.swift`
- Create: `BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift`

- [ ] **Step 1: Write the failing tests for RecoveryManager**

```swift
// BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift
import XCTest
@testable import BlazeDBCore

final class RecoveryManagerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-recovery-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // Test spec item 1: begin → write → crash → reopen → WAL replay restores data
    func testCommittedTransactionIsReplayed() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        // Simulate recovery
        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 1)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 5)
        XCTAssertEqual(result.committedWrites[0].payload, Data([0xDE, 0xAD]))
        XCTAssertEqual(result.uncommittedTransactions, 0)
    }

    // Test spec item 4: transaction without .commit → recovery discards
    func testUncommittedTransactionIsDiscarded() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        // No commit — simulating crash
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 0)
        XCTAssertEqual(result.uncommittedTransactions, 1)
    }

    // Test spec item 2: crash mid-WAL-write → partial trailing record ignored
    func testTornTrailingEntryIgnored() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendCommit(transactionID: txID)
        try dm.close()

        // Append garbage to simulate torn write of next entry
        var walData = try Data(contentsOf: walURL)
        walData.append(Data([0x57, 0x41, 0x4C, 0x56, 0x00, 0x00])) // Partial magic + junk
        try walData.write(to: walURL)

        let result = try RecoveryManager.recover(walURL: walURL)

        // Committed transaction should still be recovered
        XCTAssertEqual(result.committedWrites.count, 1)
        XCTAssertEqual(result.committedWrites[0].pageIndex, 5)
    }

    // Test: aborted transaction is discarded same as uncommitted
    func testAbortedTransactionIsDiscarded() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        let txID = UUID()
        _ = try dm.appendBegin(transactionID: txID)
        _ = try dm.appendWrite(transactionID: txID, pageIndex: 5, data: Data([0xDE, 0xAD]))
        _ = try dm.appendAbort(transactionID: txID)
        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 0)
    }

    // Test: mid-log corruption fails loudly
    func testMidLogCorruptionFailsLoudly() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        // Write two committed transactions
        let tx1 = UUID()
        _ = try dm.appendBegin(transactionID: tx1)
        _ = try dm.appendWrite(transactionID: tx1, pageIndex: 1, data: Data([0x01]))
        _ = try dm.appendCommit(transactionID: tx1)

        let tx2 = UUID()
        _ = try dm.appendBegin(transactionID: tx2)
        _ = try dm.appendWrite(transactionID: tx2, pageIndex: 2, data: Data([0x02]))
        _ = try dm.appendCommit(transactionID: tx2)
        try dm.close()

        // Corrupt bytes in the MIDDLE of the WAL (between tx1 and tx2)
        var walData = try Data(contentsOf: walURL)
        let entries = try DurabilityManager.scanEntries(from: walURL)
        // tx1 has 3 entries, corrupt the start of entry 4 (tx2.begin)
        var offset = 0
        for i in 0..<3 {
            offset += entries[i].serializedSize
        }
        // Zero out the magic bytes of the 4th entry
        walData[offset] = 0x00
        walData[offset + 1] = 0x00
        try walData.write(to: walURL)

        // Recovery should fail loudly — valid entries exist after the corruption
        XCTAssertThrowsError(try RecoveryManager.recover(walURL: walURL)) { error in
            XCTAssertTrue("\(error)".contains("corruption") || "\(error)".contains("Corruption"),
                "Expected mid-log corruption error, got: \(error)")
        }
    }

    // Test: multiple transactions, only committed ones replayed
    func testMixedCommittedAndUncommitted() throws {
        let walURL = tempDir.appendingPathComponent("test.wal")
        let dm = try DurabilityManager(walURL: walURL)

        // TX1: committed
        let tx1 = UUID()
        _ = try dm.appendBegin(transactionID: tx1)
        _ = try dm.appendWrite(transactionID: tx1, pageIndex: 1, data: Data([0x01]))
        _ = try dm.appendCommit(transactionID: tx1)

        // TX2: uncommitted (crash)
        let tx2 = UUID()
        _ = try dm.appendBegin(transactionID: tx2)
        _ = try dm.appendWrite(transactionID: tx2, pageIndex: 2, data: Data([0x02]))

        // TX3: committed
        let tx3 = UUID()
        _ = try dm.appendBegin(transactionID: tx3)
        _ = try dm.appendWrite(transactionID: tx3, pageIndex: 3, data: Data([0x03]))
        _ = try dm.appendCommit(transactionID: tx3)

        try dm.close()

        let result = try RecoveryManager.recover(walURL: walURL)

        XCTAssertEqual(result.committedWrites.count, 2)
        XCTAssertEqual(result.uncommittedTransactions, 1)
        // Verify ordering: TX1 writes before TX3 writes
        XCTAssertEqual(result.committedWrites[0].pageIndex, 1)
        XCTAssertEqual(result.committedWrites[1].pageIndex, 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RecoveryManagerTests 2>&1 | tail -5`
Expected: FAIL — `RecoveryManager` does not exist

- [ ] **Step 3: Implement RecoveryManager**

```swift
// BlazeDB/Storage/RecoveryManager.swift
import Foundation

/// Result of WAL recovery.
public struct RecoveryResult: Sendable {
    /// Page writes from committed transactions, in LSN order.
    /// The caller should apply these to the page store.
    public let committedWrites: [WALEntry]

    /// Number of transactions that were not committed (discarded).
    public let uncommittedTransactions: Int

    /// The highest LSN seen during recovery.
    public let highestLSN: UInt64

    /// The last checkpoint LSN found, if any.
    public let lastCheckpointLSN: UInt64?
}

/// Recovers database state from a WAL file.
///
/// Recovery strategy:
/// 1. Scan all valid entries from WAL
/// 2. Group entries by transactionID
/// 3. A transaction is committed iff a .commit record exists for its ID
/// 4. Collect .write and .delete entries from committed transactions only
/// 5. Return them in LSN order for the caller to apply
///
/// Torn-write handling:
/// - Invalid trailing entry: ignore (torn write from crash)
/// - Invalid entry in the middle with valid entries after: fail loudly (corruption)
public enum RecoveryManager {

    /// Recover committed writes from a WAL file.
    public static func recover(walURL: URL) throws -> RecoveryResult {
        let entries = try DurabilityManager.scanEntries(from: walURL)
        return processEntries(entries)
    }

    /// Process a list of WAL entries and extract committed writes.
    public static func processEntries(_ entries: [WALEntry]) -> RecoveryResult {
        // Track which transactions are committed
        var committedTxIDs: Set<UUID> = []
        var abortedTxIDs: Set<UUID> = []
        var allTxIDs: Set<UUID> = []
        var lastCheckpointLSN: UInt64? = nil
        var highestLSN: UInt64 = 0

        for entry in entries {
            if entry.lsn > highestLSN {
                highestLSN = entry.lsn
            }

            switch entry.operation {
            case .begin:
                allTxIDs.insert(entry.transactionID)
            case .commit:
                committedTxIDs.insert(entry.transactionID)
            case .abort:
                abortedTxIDs.insert(entry.transactionID)
            case .checkpoint:
                lastCheckpointLSN = entry.lsn
            case .write, .delete:
                allTxIDs.insert(entry.transactionID)
            }
        }

        // Collect writes from committed transactions, in LSN order
        let committedWrites = entries.filter { entry in
            (entry.operation == .write || entry.operation == .delete)
            && committedTxIDs.contains(entry.transactionID)
        }

        // Count uncommitted (not committed and not aborted)
        let uncommitted = allTxIDs.subtracting(committedTxIDs).subtracting(abortedTxIDs)

        return RecoveryResult(
            committedWrites: committedWrites,
            uncommittedTransactions: uncommitted.count,
            highestLSN: highestLSN,
            lastCheckpointLSN: lastCheckpointLSN
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RecoveryManagerTests 2>&1 | tail -10`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add BlazeDB/Storage/RecoveryManager.swift BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift
git commit -m "feat: add RecoveryManager with committed-entry-only redo

Scans WAL, groups by transactionID, replays only committed
transactions. Handles torn trailing writes (ignored) and mid-log
corruption (fails loudly). Returns writes in LSN order.

Phase 1, Task 3 of WAL consolidation."
```

---

## Chunk 3: Wire DurabilityManager into PageStore and BlazeTransaction

### Task 4: PageStore uses DurabilityManager for crash recovery

**Files:**
- Modify: `BlazeDB/Storage/PageStore.swift:212-313` (WAL init and crash recovery)

- [ ] **Step 1: Write test for PageStore recovery via DurabilityManager**

```swift
// Add to BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift

func testPageStoreRecoveryViaDurabilityManager() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

    // Create a PageStore, write a page, close
    let store = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)
    let pageData = Data(repeating: 0xAA, count: store.pageSize)
    try store.writePage(index: 0, data: pageData)
    try store.close()

    // Verify the page survives reopen (WAL replay)
    let store2 = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)
    let recovered = try store2.readPage(index: 0)
    XCTAssertEqual(recovered, pageData)
    try store2.close()
}
```

- [ ] **Step 2: Run test — should pass with existing WAL (confirms current behavior)**

Run: `swift test --filter testPageStoreRecoveryViaDurabilityManager 2>&1 | tail -5`
Expected: PASS (existing WriteAheadLog path works)

- [ ] **Step 3: Replace PageStore's direct WriteAheadLog usage with DurabilityManager**

In `PageStore.swift`:
- Replace `private var wal: WriteAheadLog?` with `private var durabilityManager: DurabilityManager?`
- Update init to create `DurabilityManager` instead of `WriteAheadLog`
- Update crash recovery to use `RecoveryManager.recover()` instead of `wal.replay()`
- Update page write methods to call `durabilityManager.appendWrite()` before `pwrite()`
- Update checkpoint to use `durabilityManager.checkpoint()`
- Keep `WriteAheadLog.swift` as an internal implementation detail of `DurabilityManager` (or inline its POSIX I/O into `DurabilityManager`)

Key changes at `PageStore.swift:212-313`:
```swift
// Old:
// self.wal = try WriteAheadLog(logURL: walURL)
// New:
self.durabilityManager = try DurabilityManager(walURL: walURL)

// Old crash recovery:
// let entries = try wal.replay()
// for entry in entries { pwrite... }
// New:
let result = try RecoveryManager.recover(walURL: walURL)
for entry in result.committedWrites {
    // Apply to page file
    try applyWALEntry(entry)
}
if result.committedWrites.count > 0 {
    // fsync main file, then checkpoint (truncate WAL)
    try fsyncMainFile()
    try durabilityManager?.checkpoint()
}
```

- [ ] **Step 4: Run existing WAL/recovery tests to verify nothing broke**

Run: `swift test --filter "TransactionDurability\|TransactionRecovery\|CrashRecovery" 2>&1 | tail -15`
Expected: All existing tests PASS

- [ ] **Step 5: Commit**

```bash
git add BlazeDB/Storage/PageStore.swift
git commit -m "refactor: PageStore uses DurabilityManager for WAL and recovery

Replace direct WriteAheadLog usage with DurabilityManager.
Crash recovery now uses RecoveryManager to replay only committed
transactions. Existing recovery tests pass unchanged.

Phase 1, Task 4 of WAL consolidation."
```

---

### Task 5: BlazeTransaction uses DurabilityManager instead of TransactionLog

**Files:**
- Modify: `BlazeDB/Transactions/BlazeTransaction.swift`
- Modify: `BlazeDB/Transactions/TransactionContext.swift`

- [ ] **Step 1: Write test for BlazeTransaction commit/rollback via DurabilityManager**

```swift
// Add to DurabilityManagerTests.swift

func testBlazeTransactionCommitWritesWALEntries() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let store = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)

    let tx = BlazeTransaction(store: store)
    let pageData = Data(repeating: 0xBB, count: store.pageSize)
    try tx.write(pageID: 0, data: pageData)
    try tx.commit()

    // Verify WAL contains begin, write, commit
    let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")
    let entries = try DurabilityManager.scanEntries(from: walURL)

    let ops = entries.map { $0.operation }
    XCTAssertTrue(ops.contains(.begin))
    XCTAssertTrue(ops.contains(.write))
    XCTAssertTrue(ops.contains(.commit))

    try store.close()
}

func testBlazeTransactionRollbackWritesAbort() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let store = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)

    let tx = BlazeTransaction(store: store)
    let pageData = Data(repeating: 0xCC, count: store.pageSize)
    try tx.write(pageID: 0, data: pageData)
    try tx.rollback()

    let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")
    let entries = try DurabilityManager.scanEntries(from: walURL)

    let ops = entries.map { $0.operation }
    XCTAssertTrue(ops.contains(.abort))
    XCTAssertFalse(ops.contains(.commit))

    try store.close()
}
```

- [ ] **Step 2: Run tests — should fail (BlazeTransaction still uses TransactionLog)**

- [ ] **Step 3: Update BlazeTransaction to use DurabilityManager**

In `BlazeTransaction.swift`:
- Remove all `TransactionLog()` instantiations
- Get `DurabilityManager` from `store.durabilityManager`
- `init`: call `dm.appendBegin(transactionID: txID)`
- `write`: stage in context only (no WAL append yet — WAL gets all writes at commit time)
- `delete`: stage in context only
- `commit`: **CRITICAL ORDERING** — first append all staged writes to WAL via `dm.appendWrite()` for each staged page, then `dm.appendCommit()` (this fsyncs), THEN flush staged pages to the page file. This enforces WAL-before-mutate. The existing code does it backwards (pages first, then log).
- `rollback`: discard staged context (do NOT write pages to disk), call `dm.appendAbort(transactionID: txID)`

```swift
// Correct commit ordering:
func commit() throws {
    guard state == .open else { throw ... }

    // 1. Append all staged writes to WAL
    for (pageID, data) in context.stagedPages {
        _ = try dm.appendWrite(transactionID: txID, pageIndex: UInt32(pageID), data: data)
    }

    // 2. Append commit record (this fsyncs the WAL — durability guarantee)
    _ = try dm.appendCommit(transactionID: txID)

    // 3. NOW apply pages to the store (safe — WAL has the committed record)
    for (pageID, data) in context.stagedPages {
        try store.writePage(index: pageID, data: data)
    }

    state = .committed
}
```

In `TransactionContext.swift`:
- Remove `var log: TransactionLog` property
- Remove disk writes from `rollback()` — rollback simply discards the in-memory staged writes. Under the new model, uncommitted staged data was never written to the page file, so there is nothing to restore. The baseline snapshot mechanism is no longer needed.
- `commit()` no longer calls `log.flush(to: store)` — the caller (BlazeTransaction) handles the WAL-then-page ordering
- Context becomes a pure in-memory staging buffer: `stagedPages` dict + read-through to store

- [ ] **Step 4: Run tests**

Run: `swift test --filter "BlazeTransactionCommit\|BlazeTransactionRollback\|TransactionDurability\|TransactionRecovery" 2>&1 | tail -15`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add BlazeDB/Transactions/BlazeTransaction.swift BlazeDB/Transactions/TransactionContext.swift
git commit -m "refactor: BlazeTransaction uses DurabilityManager, not TransactionLog

Transaction operations (begin/write/delete/commit/rollback) now go
through DurabilityManager WAL path. TransactionContext is now a
pure in-memory staging buffer with no log dependency.

Phase 1, Task 5 of WAL consolidation."
```

---

## Chunk 4: Delete Legacy Systems, Update BlazeDBClient

### Task 6: BlazeDBClient uses BlazeTransaction instead of file-copy model

**Files:**
- Modify: `BlazeDB/Exports/BlazeDBClient.swift:1384-1498` (transaction methods)
- Modify: `BlazeDB/Exports/BlazeDBClient.swift:222-227` (snapshot properties)
- Modify: `BlazeDB/Exports/BlazeDBClient.swift:502-541` (transaction URLs, cleanup)

- [ ] **Step 1: Write test confirming BlazeDBClient transaction works end-to-end**

```swift
// Add to DurabilityManagerTests.swift

func testBlazeDBClientTransactionCommit() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test")

    try client.beginTransaction()
    let id = try client.insert(BlazeDataRecord(["key": .string("value")]))
    try client.commitTransaction()

    // Verify record persists after commit
    let record = try client.fetch(id: id)
    XCTAssertNotNil(record)

    try client.close()
}

func testBlazeDBClientTransactionRollback() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test")

    // Insert a record outside transaction
    let id1 = try client.insert(BlazeDataRecord(["key": .string("before")]))

    try client.beginTransaction()
    let id2 = try client.insert(BlazeDataRecord(["key": .string("during")]))
    try client.rollbackTransaction()

    // Record from before transaction should exist
    let r1 = try client.fetch(id: id1)
    XCTAssertNotNil(r1)

    // Record from rolled-back transaction should not
    let r2 = try? client.fetch(id: id2)
    XCTAssertNil(r2)

    try client.close()
}
```

- [ ] **Step 2: Run tests — should pass with current file-copy model**

- [ ] **Step 3: Replace file-copy transaction methods with BlazeTransaction delegation**

In `BlazeDBClient.swift`:
- Add `private var activeTransaction: BlazeTransaction?` property
- `beginTransaction()`: create `BlazeTransaction(store: collection.store)`, store as `activeTransaction`
- `commitTransaction()`: call `activeTransaction.commit()`, set to nil
- `rollbackTransaction()`: call `activeTransaction.rollback()`, set to nil
- Delete `transactionIndexMapSnapshot`, `transactionRecordSnapshot`, `transactionPagesWritten` properties
- Delete `transactionLogURL`, `transactionBackupURL`, `transactionMetaBackupURL` computed properties
- Delete `replayTransactionLogIfNeeded()` method
- Keep `BlazeTransaction` as the sole transaction mechanism

- [ ] **Step 4: Run full Tier0 test suite**

Run: `swift test --filter BlazeDB_Tier0 2>&1 | grep -E "passed|failed|error" | tail -10`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add BlazeDB/Exports/BlazeDBClient.swift
git commit -m "refactor: BlazeDBClient transactions use BlazeTransaction, not file copies

Delete indexMap/record snapshot model. Delete file-copy backup URLs.
Delete replayTransactionLogIfNeeded(). BlazeTransaction is now the
sole transaction mechanism.

Phase 1, Task 6 of WAL consolidation."
```

---

### Task 7: Delete TransactionLog.swift

**Files:**
- Delete: `BlazeDB/Transactions/TransactionLog.swift`
- Modify: `Package.swift` (if TransactionLog is referenced)
- Modify: any remaining references

- [ ] **Step 1: Search for all TransactionLog references**

Run: `grep -r "TransactionLog" BlazeDB/ BlazeDBTests/ --include="*.swift" -l`

Fix each reference:
- If it's a test that directly tests TransactionLog: delete or rewrite against DurabilityManager
- If it's production code: should already be removed by Tasks 5-6

- [ ] **Step 2: Delete TransactionLog.swift**

```bash
git rm BlazeDB/Transactions/TransactionLog.swift
```

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1 | grep "error:" | head -10`
Expected: Zero errors

Run: `swift test --filter BlazeDB_Tier0 2>&1 | grep -E "passed|failed" | tail -5`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "delete: remove TransactionLog.swift

TransactionLog (JSON-based durability scaffolding) is fully replaced
by DurabilityManager (binary WAL with CRC32 and LSN tracking).
All references updated or removed.

Phase 1, Task 7 of WAL consolidation."
```

---

### Task 8: Fix WriteAheadLog.lastCheckpoint to use LSN

**Files:**
- Modify: `BlazeDB/Storage/WriteAheadLog.swift:299-307` (WALStats)

- [ ] **Step 1: Update WALStats to use lastCheckpointLSN instead of Date()**

In `WriteAheadLog.swift`, change `WALStats`:
```swift
// Old:
public let lastCheckpoint: Date
// New:
public let lastCheckpointLSN: UInt64
```

Update `getStats()` to read `lastCheckpointLSN` from DurabilityManager.

- [ ] **Step 2: Fix all callers of `WALStats.lastCheckpoint`**

Run: `grep -r "lastCheckpoint" BlazeDB/ --include="*.swift" -l`

Update each caller to use the new LSN field. For display purposes (BlazeDoctor, stats output), show the LSN number, not a timestamp.

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1 | grep "error:" | head -5`
Expected: Zero errors

- [ ] **Step 4: Commit**

```bash
git add BlazeDB/Storage/WriteAheadLog.swift
git commit -m "fix: WALStats.lastCheckpointLSN replaces meaningless Date()

lastCheckpoint previously returned Date() (always current time).
Now tracks actual checkpoint LSN from DurabilityManager.

Phase 1, Task 8 of WAL consolidation."
```

---

## Chunk 5: Final Integration and Verification

### Task 9: End-to-end crash recovery integration test

**Files:**
- Create or extend: `BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift`

- [ ] **Step 1: Write the full integration crash recovery test**

```swift
// Test spec item 3: WAL write completes, crash before page flush → replay → page reconstructed

func testCrashAfterWALWriteBeforePageFlush() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let walURL = dbURL.deletingPathExtension().appendingPathExtension("wal")

    // Create DB with some initial data
    let store = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)
    let initialData = Data(repeating: 0x11, count: store.pageSize)
    try store.writePage(index: 0, data: initialData)
    try store.close()

    // Now simulate: WAL write succeeds, but page file NOT updated
    // (crash between WAL append and pwrite to main file)
    let dm = try DurabilityManager(walURL: walURL)
    let txID = UUID()
    let newData = Data(repeating: 0x22, count: store.pageSize)
    _ = try dm.appendBegin(transactionID: txID)
    _ = try dm.appendWrite(transactionID: txID, pageIndex: 0, data: newData)
    _ = try dm.appendCommit(transactionID: txID)
    try dm.close()
    // Main file still has 0x11, WAL has committed 0x22

    // Reopen — recovery should replay WAL and reconstruct the page
    let store2 = try PageStore(fileURL: dbURL, password: "test", enableWAL: true)
    let recovered = try store2.readPage(index: 0)
    XCTAssertEqual(recovered, newData, "Page should be reconstructed from WAL")
    try store2.close()
}

func testFullEndToEndTransactionRecovery() throws {
    let dbURL = tempDir.appendingPathComponent("test.db")
    let client = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test")

    // Insert records in a committed transaction
    try client.beginTransaction()
    let id1 = try client.insert(BlazeDataRecord(["name": .string("Alice")]))
    let id2 = try client.insert(BlazeDataRecord(["name": .string("Bob")]))
    try client.commitTransaction()

    try client.close()

    // Reopen — data should survive
    let client2 = try BlazeDBClient(name: "test", fileURL: dbURL, password: "test")
    let r1 = try client2.fetch(id: id1)
    let r2 = try client2.fetch(id: id2)
    XCTAssertNotNil(r1)
    XCTAssertNotNil(r2)
    try client2.close()
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter RecoveryManagerTests 2>&1 | tail -15`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add BlazeDBTests/Tier0Core/Durability/RecoveryManagerTests.swift
git commit -m "test: add end-to-end crash recovery integration tests

Covers: WAL write before page flush recovery, full transaction
commit/reopen cycle, mixed committed/uncommitted transactions.

Phase 1, Task 9 of WAL consolidation."
```

---

### Task 10: Run full test suite, verify no regressions

- [ ] **Step 1: Run Tier0 gate tests**

Run: `swift test --filter BlazeDB_Tier0 2>&1 | grep -E "passed|failed" | tail -10`
Expected: All PASS

- [ ] **Step 2: Run Tier1 tests**

Run: `swift test --filter BlazeDB_Tier1 2>&1 | grep -E "passed|failed" | tail -10`
Expected: All PASS (or pre-existing failures only)

- [ ] **Step 3: Verify build with strict concurrency**

Run: `swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep "error:" | head -5`
Expected: Zero errors (warnings acceptable)

- [ ] **Step 4: Final commit with phase completion**

```bash
git commit --allow-empty -m "milestone: Phase 1 complete — WAL/Transaction consolidation

Single WAL (DurabilityManager), single transaction model (BlazeTransaction).
TransactionLog deleted. File-copy transactions deleted.
RecoveryManager handles crash recovery with committed-entry-only redo.
All Tier0 and Tier1 tests pass."
```

---

## Summary

| Task | What | Risk |
|------|------|------|
| 1 | WALEntry binary format + serialization tests | Low |
| 2 | DurabilityManager (append, LSN, fsync, checkpoint) | Medium |
| 3 | RecoveryManager (committed-entry redo) | Medium |
| 4 | PageStore uses DurabilityManager | High — changes crash recovery path |
| 5 | BlazeTransaction uses DurabilityManager | High — changes transaction path |
| 6 | BlazeDBClient delegates to BlazeTransaction | High — changes public API behavior |
| 7 | Delete TransactionLog.swift | Medium — must verify no remaining refs |
| 8 | Fix WALStats.lastCheckpoint to use LSN | Low |
| 9 | End-to-end crash recovery tests | Low |
| 10 | Full regression test suite | Low |

Tasks 1-3 are additive (new files, no existing code changes). Tasks 4-7 are the dangerous ones — each modifies a critical path. Run tests after every task.
