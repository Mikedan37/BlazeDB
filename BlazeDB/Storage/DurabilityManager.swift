import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Owns WAL file I/O, monotonic LSN allocation, and checkpoint metadata.
///
/// Replay policy:
/// - Uncommitted transaction on recovery → discarded (no .commit record)
/// - Committed transaction after crash before page flush → replayed by RecoveryManager
/// - Partial trailing WAL entry → ignored (torn write)
/// - Corruption in middle of WAL → hard failure (WALError.midLogCorruption)
public final class DurabilityManager: @unchecked Sendable {

    // MARK: - State

    private var _currentLSN: UInt64 = 0
    private var _lastCheckpointLSN: UInt64 = 0
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private let walURL: URL

    /// Minimum entry size: header (37) + trailer (4) = 41 bytes, with zero-length payload.
    private static let minEntrySize: Int = WALEntry.headerSize + WALEntry.trailerSize

    // MARK: - Checkpoint thresholds

    public var checkpointEntryThreshold: Int = 10_000
    public var checkpointSizeThreshold: Int64 = 64 * 1024 * 1024
    private var entriesSinceCheckpoint: Int = 0

    // MARK: - Init

    /// Create or open a WAL file. Scans existing entries to recover LSN state.
    /// Also reads the sibling `.wal-meta` file to recover `lastCheckpointLSN`.
    public init(walURL: URL) throws {
        self.walURL = walURL

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: walURL.path) {
            FileManager.default.createFile(atPath: walURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forUpdating: walURL)

        // Recover lastCheckpointLSN from .wal-meta sibling file
        let metaURL = Self.metaURL(for: walURL)
        if let metaData = try? Data(contentsOf: metaURL), metaData.count >= 8 {
            _lastCheckpointLSN = metaData.withUnsafeBytes { buf in
                buf.loadUnaligned(fromByteOffset: 0, as: UInt64.self).littleEndian
            }
            _currentLSN = _lastCheckpointLSN
        }

        // Scan existing WAL entries to find the highest LSN
        let entries = try Self.scanEntries(from: walURL)
        if let lastEntry = entries.last {
            _currentLSN = lastEntry.lsn
        }
        entriesSinceCheckpoint = entries.count
    }

    // MARK: - Append methods

    /// Append a `.begin` entry. No fsync (buffered to kernel).
    @discardableResult
    public func appendBegin(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .begin, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    /// Append a `.write` entry. No fsync (buffered to kernel).
    @discardableResult
    public func appendWrite(transactionID: UUID, pageIndex: UInt32, data: Data) throws -> UInt64 {
        try appendEntry(operation: .write, transactionID: transactionID, pageIndex: pageIndex, payload: data)
    }

    /// Append a `.delete` entry. No fsync (buffered to kernel).
    @discardableResult
    public func appendDelete(transactionID: UUID, pageIndex: UInt32) throws -> UInt64 {
        try appendEntry(operation: .delete, transactionID: transactionID, pageIndex: pageIndex, payload: Data())
    }

    /// Append a `.commit` entry. FSYNC HERE — this is the durability guarantee.
    @discardableResult
    public func appendCommit(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .commit, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    /// Append an `.abort` entry. FSYNC HERE.
    @discardableResult
    public func appendAbort(transactionID: UUID) throws -> UInt64 {
        try appendEntry(operation: .abort, transactionID: transactionID, pageIndex: 0, payload: Data())
    }

    // MARK: - Core append

    /// Central append path. Locks, increments LSN, serializes, writes, and optionally fsyncs.
    ///
    /// Fsync is performed ONLY for `.commit`, `.abort`, and `.checkpoint` operations.
    /// Begin/write/delete go to kernel buffers without fsync. If a crash happens
    /// mid-transaction, the incomplete transaction has no .commit record and recovery
    /// discards it. This is the batch commit optimization.
    private func appendEntry(
        operation: WALOperation,
        transactionID: UUID,
        pageIndex: UInt32,
        payload: Data
    ) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        guard let fh = fileHandle else {
            throw WALError.recoveryFailed("WAL file handle is closed")
        }

        // Increment LSN — strictly monotonically increasing
        _currentLSN += 1
        let newLSN = _currentLSN

        let entry = WALEntry(
            lsn: newLSN,
            transactionID: transactionID,
            operation: operation,
            pageIndex: pageIndex,
            payload: payload
        )

        let data = entry.serialize()

        // Append with positional write to avoid mutating shared file offset state.
        let fd = fh.fileDescriptor
        var st = stat()
        if fstat(fd, &st) != 0 {
            throw WALError.recoveryFailed("fstat failed while appending WAL entry")
        }
        let appendOffset = off_t(st.st_size)

        let written = data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return -1 }
            return pwrite(fd, base, data.count, appendOffset)
        }
        guard written == data.count else {
            throw WALError.recoveryFailed("pwrite failed while appending WAL entry")
        }

        // Fsync only on commit, abort, or checkpoint
        if operation == .commit || operation == .abort || operation == .checkpoint {
            fh.synchronizeFile()
        }

        entriesSinceCheckpoint += 1

        return newLSN
    }

    // MARK: - Read

    /// Read all valid entries from the WAL file.
    public func readAllEntries() throws -> [WALEntry] {
        try Self.scanEntries(from: walURL)
    }

    // MARK: - Scanner

    /// Static scanner that reads WAL file data and parses entries sequentially.
    ///
    /// Handles:
    /// - Empty file → return `[]`
    /// - Valid entries → collect in array
    /// - Torn trailing entry (remaining bytes < 2 * minEntrySize after parse failure) → stop, return what we have
    /// - Mid-log corruption (significant data remains after parse failure) → throw `WALError.midLogCorruption`
    /// - LSN monotonicity violation → throw `WALError.midLogCorruption`
    public static func scanEntries(from url: URL) throws -> [WALEntry] {
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }

        var entries: [WALEntry] = []
        var offset = data.startIndex
        var lastLSN: UInt64 = 0

        while offset < data.endIndex {
            do {
                let (entry, nextOffset) = try WALEntry.readNext(from: data, at: offset)

                // Verify LSN monotonicity
                if entry.lsn <= lastLSN && lastLSN > 0 {
                    throw WALError.midLogCorruption
                }
                lastLSN = entry.lsn

                entries.append(entry)
                offset = nextOffset
            } catch {
                // How much data remains after this failed parse?
                let remaining = data.endIndex - offset
                if remaining < 2 * minEntrySize {
                    // Torn trailing entry — tolerate it
                    break
                } else {
                    // Significant data remains — this is mid-log corruption
                    throw WALError.midLogCorruption
                }
            }
        }

        return entries
    }

    // MARK: - Checkpoint

    /// Persist `_currentLSN` to a sibling `.wal-meta` file, then truncate the WAL to 0.
    ///
    /// The checkpoint does NOT write a checkpoint record into the WAL being truncated —
    /// it would be immediately destroyed. The LSN is persisted to a sibling `.wal-meta` file instead.
    public func checkpoint() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let fh = fileHandle else {
            throw WALError.recoveryFailed("WAL file handle is closed")
        }

        let checkpointLSN = _currentLSN

        // Persist checkpoint LSN to .wal-meta (8 bytes, UInt64 LE)
        var lsnLE = checkpointLSN.littleEndian
        let metaData = Data(bytes: &lsnLE, count: 8)
        let metaURL = Self.metaURL(for: walURL)
        try metaData.write(to: metaURL, options: .atomic)
        if let metaFH = FileHandle(forWritingAtPath: metaURL.path) {
            do {
                try metaFH.synchronize()
                try metaFH.close()
            } catch {
                BlazeLogger.warn("DurabilityManager.checkpoint: could not fsync/close wal-meta handle at \(metaURL.path): \(error.localizedDescription)")
            }
        }
        try Self.fsyncDirectory(at: metaURL.deletingLastPathComponent())

        // Truncate WAL file to 0
        fh.truncateFile(atOffset: 0)
        fh.synchronizeFile()

        _lastCheckpointLSN = checkpointLSN
        entriesSinceCheckpoint = 0
    }

    // MARK: - Properties

    /// True if entry count or file size exceeds checkpoint thresholds.
    public var shouldCheckpoint: Bool {
        lock.lock()
        defer { lock.unlock() }

        if entriesSinceCheckpoint >= checkpointEntryThreshold {
            return true
        }

        if let fh = fileHandle {
            var st = stat()
            if fstat(fh.fileDescriptor, &st) == 0 {
                let size = Int64(st.st_size)
                if size >= checkpointSizeThreshold {
                    return true
                }
            }
        }

        return false
    }

    /// Thread-safe current LSN getter.
    public var currentLSN: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _currentLSN
    }

    /// Thread-safe last checkpoint LSN getter.
    public var lastCheckpointLSN: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _lastCheckpointLSN
    }

    // MARK: - Sync

    /// Force fsync on the WAL file.
    /// Used by PageStore for standalone writes (outside a transaction) where
    /// there is no commit record to trigger the fsync.
    public func sync() {
        lock.lock()
        defer { lock.unlock() }
        fileHandle?.synchronizeFile()
    }

    // MARK: - Close

    /// Close the WAL file handle.
    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        if let fh = fileHandle {
            if #available(iOS 13.4, macOS 10.15.4, *) {
                try fh.close()
            } else {
                fh.closeFile()
            }
        }
        fileHandle = nil
    }

    // MARK: - Helpers

    private static func metaURL(for walURL: URL) -> URL {
        walURL.deletingPathExtension().appendingPathExtension("wal-meta")
    }

    private static func fsyncDirectory(at url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            throw WALError.recoveryFailed("Failed to open directory for fsync")
        }
        defer {
            #if canImport(Darwin)
            _ = Darwin.close(fd)
            #elseif canImport(Glibc)
            _ = Glibc.close(fd)
            #endif
        }
        if fsync(fd) != 0 {
            throw WALError.recoveryFailed("Directory fsync failed for WAL metadata")
        }
    }
}
