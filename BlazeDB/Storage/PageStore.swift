//  PageStore.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

// Note: Logger is available within the same module (BlazeDBCore)

internal extension FileHandle {
    func compatSeek(toOffset offset: UInt64) throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try self.seek(toOffset: offset)
        } else {
            self.seek(toFileOffset: offset)
        }
    }
    func compatRead(upToCount count: Int) throws -> Data {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            return try self.read(upToCount: count) ?? Data()
        } else {
            return self.readData(ofLength: count)
        }
    }
    func compatWrite(_ data: Data) throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try self.write(contentsOf: data)
        } else {
            self.write(data)
        }
    }
    func compatClose() {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try? self.close()
        } else {
            self.closeFile()
        }
    }
    func compatSynchronize() throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try self.synchronize()
        } else {
            self.synchronizeFile()
        }
    }
    func compatTruncate(atOffset offset: UInt64) throws {
        #if os(Linux)
        // Linux doesn't have truncate(atOffset:), use seek + truncate
        try self.seek(toOffset: offset)
        // Note: FileHandle on Linux may not support truncate directly
        // This is a limitation - truncate should be done at the file system level
        #else
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try self.truncate(atOffset: offset)
        } else {
            self.truncateFile(atOffset: offset)
        }
        #endif
    }
    func compatOffset() throws -> UInt64 {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            return try self.offset()
        } else {
            return self.offsetInFile
        }
    }
}

/// Controls which WAL implementation a `PageStore` instance uses. Each store picks one mode at initialization.
///
/// - `.legacy` — Binary `WriteAheadLog` entries are appended before corresponding main-file page writes (default for `PageStore(fileURL:key:)`).
/// - `.unified` — Uses `DurabilityManager` and `RecoveryManager` instead of the legacy binary WAL type.
///
/// The default `BlazeDBClient` path uses `.legacy`. High-level NDJSON `TransactionLog` is not the default document durability mechanism for the client API.
public enum WALMode: Sendable {
    case legacy
    case unified
}

/// **Advanced API:** low-level encrypted page file access and WAL integration. Typical application code
/// should use `BlazeDBClient` instead of talking to `PageStore` directly.
///
/// Application code should normally use `BlazeDBClient`. This type is public for benchmarks, tests, and tooling that need direct page-level control.
// Swift 6: Thread-safe via internal DispatchQueue synchronization
public final class PageStore: @unchecked Sendable {
    public let fileURL: URL
    internal let fileHandle: FileHandle  // Made internal for PageStore+Overflow access
    internal let fd: Int32  // POSIX file descriptor for pread/pwrite (no shared seek state)
    internal let key: SymmetricKey  // ENCRYPTION KEY STORED - Made internal for PageStore+Overflow access
    internal let pageSize = 4096  // Made internal for DynamicCollection access

    // MARK: - Write-Ahead Log for crash safety
    internal let wal: WriteAheadLog?
    private let walEnabled: Bool
    public let walMode: WALMode

    // MARK: - Unified WAL (DurabilityManager)
    /// Non-nil when walMode == .unified and WAL is enabled.
    internal private(set) var durabilityManager: DurabilityManager?
    /// Batches unsynchronized unified-mode writes into one auto-transaction.
    private var pendingUnifiedAutoTransactionID: UUID?
    /// Encrypted page buffers staged for unified unsynchronized writes.
    /// These are flushed to the main file only after a durable WAL commit.
    private var pendingUnifiedBufferedWrites: [(index: Int, buffer: Data)] = []
    
    // MARK: - Concurrency Invariants
    // Invariants:
    // - All reads use pread() — no shared file offset, safe for concurrent readers
    // - All writes use pwrite() under barrier — no shared file offset
    // - Re-entrancy is guarded via dispatchPrecondition in DEBUG builds
    // - Internal helpers (_writePageLocked, _writePageLockedUnsynchronized) assume caller holds barrier or queue context
    internal let queue = DispatchQueue(label: "com.yourorg.blazedb.pagestore", attributes: .concurrent)  // Made internal for PageStore+Overflow access
    internal let pageCache = PageCache(maxSize: 1000)  // Made internal for DynamicCollection access
    // Overflow corruption circuit-breaker state (guarded by lock).
    internal let overflowCorruptionLock = NSLock()
    internal var knownCorruptedOverflowMainPages: Set<Int> = []
    internal var overflowCorruptionIncidentCount: Int = 0
    internal var overflowReadDegradedMode: Bool = false
    internal let legacyOverflowPointerHeuristicCompatibilityMode: Bool
    private var isLocked: Bool = false  // Track lock state for cleanup
    private var closed: Bool = false
    // Compression is configured per PageStore instance.
    // Internal visibility is required for the same-module compression extension.
    internal let compressionStateLock = NSLock()
    internal var compressionEnabled = false

    internal enum IOError: Error, LocalizedError {
        case posix(
            operation: String,
            path: String,
            errnoValue: Int32,
            nonBlockingLock: Bool,
            ownerHint: String?,
            traceSummaryPath: String?
        )

        var errorDescription: String? {
            switch self {
            case let .posix(operation, path, errnoValue, nonBlockingLock, ownerHint, traceSummaryPath):
                var msg = "I/O operation failed"
                msg += " op=\(operation)"
                msg += " path=\(path)"
                msg += " errno=\(errnoValue) (\(String(cString: strerror(errnoValue))))"
                msg += " nonBlockingLock=\(nonBlockingLock)"
                if let ownerHint {
                    msg += " ownerHint=\(ownerHint)"
                }
                if let traceSummaryPath {
                    msg += " traceSummary=\(traceSummaryPath)"
                }
                return msg
            }
        }
    }
    
    internal enum RecoveryError: Error, LocalizedError {
        case walReplayShortWrite(entryIndex: Int, pageIndex: Int, expected: Int, actual: Int)
        case walReplayInvalidEntrySize(entryIndex: Int, pageIndex: Int, size: Int, expected: Int)
        case walReplayFsyncFailed(underlying: Error)
        case walReplayInjectedFailure(entryIndex: Int)
        case closeFsyncFailed(underlying: Error)
        
        var errorDescription: String? {
            switch self {
            case .walReplayShortWrite(let entryIndex, let pageIndex, let expected, let actual):
                return "WAL replay short write at entry \(entryIndex), page \(pageIndex): expected \(expected), wrote \(actual)"
            case .walReplayInvalidEntrySize(let entryIndex, let pageIndex, let size, let expected):
                return "WAL replay invalid entry size at entry \(entryIndex), page \(pageIndex): got \(size), expected \(expected)"
            case .walReplayFsyncFailed(let underlying):
                return "WAL replay fsync failed: \(underlying.localizedDescription)"
            case .walReplayInjectedFailure(let entryIndex):
                return "WAL replay injected failure at entry \(entryIndex)"
            case .closeFsyncFailed(let underlying):
                return "Close fsync failed: \(underlying.localizedDescription)"
            }
        }
    }
    
    #if DEBUG
    private static let replayFaultLock = NSLock()
    nonisolated(unsafe) private static var replayFailAtEntryIndex: Int? = nil
    nonisolated(unsafe) private static var replayForceFsyncFailure: Bool = false
    
    internal static func _setReplayFailureForTests(entryIndex: Int?) {
        replayFaultLock.lock()
        replayFailAtEntryIndex = entryIndex
        replayFaultLock.unlock()
    }
    
    internal static func _setReplayFsyncFailureForTests(_ enabled: Bool) {
        replayFaultLock.lock()
        replayForceFsyncFailure = enabled
        replayFaultLock.unlock()
    }
    
    private static func replayFailureEntryIndexForTests() -> Int? {
        replayFaultLock.lock()
        defer { replayFaultLock.unlock() }
        return replayFailAtEntryIndex
    }
    
    private static func replayFsyncFailureEnabledForTests() -> Bool {
        replayFaultLock.lock()
        defer { replayFaultLock.unlock() }
        return replayForceFsyncFailure
    }
    #endif

    public init(
        fileURL: URL,
        key: SymmetricKey,
        enableWAL: Bool = true,
        walMode: WALMode = .legacy,
        enableLegacyOverflowPointerHeuristicCompatibilityMode: Bool = false
    ) throws {
        self.fileURL = fileURL
        self.walEnabled = enableWAL
        self.walMode = walMode
        let envCompatEnabled = ProcessInfo.processInfo.environment["BLAZEDB_ENABLE_LEGACY_OVERFLOW_POINTER_HEURISTIC"] == "1"
        self.legacyOverflowPointerHeuristicCompatibilityMode = enableLegacyOverflowPointerHeuristicCompatibilityMode || envCompatEnabled
        IOTraceSink.record(operation: "open_begin", path: fileURL.path)

        // Validate key size for AES-GCM
        let bitCount = key.bitCount
        guard [128, 192, 256].contains(bitCount) else {
            throw NSError(domain: "PageStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid SymmetricKey bit count: \(bitCount). Expected 128, 192, or 256."
            ])
        }

        self.key = key  // ✅ STORE ENCRYPTION KEY

        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forUpdating: fileURL)
        self.fd = fileHandle.fileDescriptor
        IOTraceSink.record(operation: "open_handle", path: fileURL.path, fd: self.fd, resultCode: 0)

        // Initialize WAL based on mode
        let walURL = fileURL.deletingPathExtension().appendingPathExtension("wal")

        switch walMode {
        case .legacy:
            if enableWAL {
                self.wal = try WriteAheadLog(logURL: walURL)
                BlazeLogger.debug("📜 WAL enabled (legacy) at \(walURL.lastPathComponent)")
            } else {
                self.wal = nil
                BlazeLogger.debug("📜 WAL disabled")
            }
            self.durabilityManager = nil

        case .unified:
            self.wal = nil
            if enableWAL {
                self.durabilityManager = try DurabilityManager(walURL: walURL)
                BlazeLogger.debug("📜 WAL enabled (unified) at \(walURL.lastPathComponent)")
            } else {
                self.durabilityManager = nil
                BlazeLogger.debug("📜 WAL disabled")
            }
        }

        // CRITICAL: Acquire exclusive file lock to prevent multi-process corruption
        try acquireExclusiveLock()

        // Replay WAL entries if any exist (crash recovery).
        // Fail closed: never clear WAL unless full replay + fsync succeeds.
        do {
            switch walMode {
            case .legacy:
                try _replayLegacyWAL()

            case .unified:
                try _replayUnifiedWAL(walURL: walURL)
            }
        } catch {
            // Recovery failed: preserve WAL for retry/forensics and fail closed.
            BlazeLogger.error("📜 WAL recovery failed; WAL preserved: \(error)")
            switch walMode {
            case .legacy:
                if let wal = self.wal { wal.close() }
            case .unified:
                try? durabilityManager?.close()
            }
            releaseLock()
            fileHandle.compatClose()
            throw error
        }

        BlazeLogger.debug("🔐 PageStore initialized with \(bitCount)-bit encryption and exclusive file lock")
    }

    // MARK: - Legacy WAL Recovery

    private func _replayLegacyWAL() throws {
        guard let wal = self.wal else { return }
        let entries = try wal.replay()
        guard !entries.isEmpty else { return }

        BlazeLogger.info("📜 Replaying \(entries.count) WAL entries from crash recovery (legacy)")
        for (entryIndex, entry) in entries.enumerated() {
            #if DEBUG
            if let failAt = Self.replayFailureEntryIndexForTests(), failAt == entryIndex {
                throw RecoveryError.walReplayInjectedFailure(entryIndex: entryIndex)
            }
            #endif

            guard entry.data.count == pageSize else {
                throw RecoveryError.walReplayInvalidEntrySize(
                    entryIndex: entryIndex,
                    pageIndex: entry.pageIndex,
                    size: entry.data.count,
                    expected: pageSize
                )
            }

            let offset = off_t(entry.pageIndex * pageSize)
            let actualWritten: Int = entry.data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return 0 }
                return pwrite(fd, base, entry.data.count, offset)
            }
            IOTraceSink.record(
                operation: "wal_replay_pwrite",
                path: fileURL.path,
                fd: fd,
                resultCode: Int32(actualWritten),
                errnoValue: actualWritten < 0 ? errno : nil,
                context: [
                    "entryIndex": "\(entryIndex)",
                    "pageIndex": "\(entry.pageIndex)"
                ]
            )

            guard actualWritten == entry.data.count else {
                throw RecoveryError.walReplayShortWrite(
                    entryIndex: entryIndex,
                    pageIndex: entry.pageIndex,
                    expected: entry.data.count,
                    actual: actualWritten
                )
            }
        }

        #if DEBUG
        if Self.replayFsyncFailureEnabledForTests() {
            throw RecoveryError.walReplayFsyncFailed(
                underlying: NSError(
                    domain: "PageStore",
                    code: 99001,
                    userInfo: [NSLocalizedDescriptionKey: "Injected replay fsync failure"]
                )
            )
        }
        #endif

        do {
            try fileHandle.compatSynchronize()
            IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: 0)
        } catch {
            IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: -1)
            throw RecoveryError.walReplayFsyncFailed(underlying: error)
        }

        try wal.clear()
        BlazeLogger.info("📜 WAL recovery complete, checkpoint cleared (legacy)")
    }

    // MARK: - Unified WAL Recovery

    private func _replayUnifiedWAL(walURL: URL) throws {
        guard durabilityManager != nil else { return }

        let result = try RecoveryManager.recover(walURL: walURL)
        guard !result.committedWrites.isEmpty else { return }

        BlazeLogger.info("📜 Replaying \(result.committedWrites.count) committed writes from crash recovery (unified), \(result.uncommittedTransactions) uncommitted transactions discarded")

        for (entryIndex, entry) in result.committedWrites.enumerated() {
            #if DEBUG
            if let failAt = Self.replayFailureEntryIndexForTests(), failAt == entryIndex {
                throw RecoveryError.walReplayInjectedFailure(entryIndex: entryIndex)
            }
            #endif

            let offset = off_t(Int(entry.pageIndex) * pageSize)

            // Unified WAL can contain committed delete records with empty payload.
            // Replaying delete means zeroing the target page in the main file.
            let bytesToWrite: Data
            switch entry.operation {
            case .write:
                guard entry.payload.count == pageSize else {
                    throw RecoveryError.walReplayInvalidEntrySize(
                        entryIndex: entryIndex,
                        pageIndex: Int(entry.pageIndex),
                        size: entry.payload.count,
                        expected: pageSize
                    )
                }
                bytesToWrite = entry.payload
            case .delete:
                bytesToWrite = Data(repeating: 0, count: pageSize)
            default:
                // RecoveryManager currently only returns committed write/delete entries.
                continue
            }

            let actualWritten: Int = bytesToWrite.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return 0 }
                return pwrite(fd, base, bytesToWrite.count, offset)
            }
            IOTraceSink.record(
                operation: "wal_replay_pwrite",
                path: fileURL.path,
                fd: fd,
                resultCode: Int32(actualWritten),
                errnoValue: actualWritten < 0 ? errno : nil,
                context: [
                    "entryIndex": "\(entryIndex)",
                    "pageIndex": "\(entry.pageIndex)"
                ]
            )

            guard actualWritten == bytesToWrite.count else {
                throw RecoveryError.walReplayShortWrite(
                    entryIndex: entryIndex,
                    pageIndex: Int(entry.pageIndex),
                    expected: bytesToWrite.count,
                    actual: actualWritten
                )
            }
        }

        #if DEBUG
        if Self.replayFsyncFailureEnabledForTests() {
            throw RecoveryError.walReplayFsyncFailed(
                underlying: NSError(
                    domain: "PageStore",
                    code: 99001,
                    userInfo: [NSLocalizedDescriptionKey: "Injected replay fsync failure"]
                )
            )
        }
        #endif

        do {
            try fileHandle.compatSynchronize()
            IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: 0)
        } catch {
            IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: -1)
            throw RecoveryError.walReplayFsyncFailed(underlying: error)
        }

        // Checkpoint: truncate WAL now that all committed writes are durable in the main file
        try durabilityManager?.checkpoint()
        BlazeLogger.info("📜 WAL recovery complete, checkpoint cleared (unified)")
    }
    
    // MARK: - File Locking
    
    /// Acquire exclusive file lock using POSIX flock()
    /// This prevents multiple processes from writing to the same database file simultaneously.
    /// Lock is automatically released when the file descriptor is closed (process exit or deinit).
    /// 
    /// - Throws: BlazeDBError.concurrentProcessAccessNotSupported if lock cannot be acquired (single-process only)
    /// - Throws: BlazeDBError.permissionDenied if system error occurs (not a lock conflict)
    /// - Precondition: fileHandle must be initialized before calling this method
    /// - Postcondition: If this method returns, isLocked is true and lock is held
    private func acquireExclusiveLock() throws {
        #if canImport(Darwin) || canImport(Glibc)
        let fd = fileHandle.fileDescriptor
        IOTraceSink.record(
            operation: "lock_attempt",
            path: fileURL.path,
            fd: fd,
            context: ["type": "LOCK_EX|LOCK_NB", "nonBlocking": "true"]
        )
        let result = flock(fd, LOCK_EX | LOCK_NB)
        
        if result != 0 {
            // Lock acquisition failed
            let errnoValue = errno
            IOTraceSink.record(
                operation: "lock_attempt",
                path: fileURL.path,
                fd: fd,
                resultCode: result,
                errnoValue: errnoValue,
                context: ["type": "LOCK_EX|LOCK_NB", "nonBlocking": "true"]
            )
            // Verify this is actually a lock conflict (EWOULDBLOCK/EAGAIN), not a system error
            // EWOULDBLOCK and EAGAIN are the same value on most systems, but we check both for portability
            let isLockConflict = (errnoValue == EWOULDBLOCK) || (errnoValue == EAGAIN)
            
            guard isLockConflict else {
                // System error (not a lock conflict) - close handle and throw
                // Log the system error for debugging
                let _ = String(cString: strerror(errnoValue))  // Capture errno before close
                fileHandle.compatClose()
                throw BlazeDBError.permissionDenied(
                    operation: "acquire file lock",
                    path: fileURL.path
                )
            }
            
            // Lock conflict - another process or handle holds the lock (single-process only)
            // Close the file handle since we failed to acquire lock
            fileHandle.compatClose()
            
            throw BlazeDBError.concurrentProcessAccessNotSupported(
                operation: "open database",
                path: fileURL
            )
        }
        
        isLocked = true
        IOTraceSink.record(operation: "lock_acquired", path: fileURL.path, fd: fd, resultCode: result)
        BlazeLogger.debug("🔒 Acquired exclusive file lock on \(fileURL.lastPathComponent)")
        #else
        // Platform doesn't support flock() - log warning but continue
        // This should not happen on supported platforms (macOS, iOS, Linux)
        BlazeLogger.warn("⚠️ File locking not available on this platform - multi-process safety not guaranteed")
        isLocked = false
        #endif
    }
    
    /// Release file lock (called automatically on deinit, but can be called explicitly)
    /// Lock is automatically released by OS when file descriptor is closed, but we
    /// explicitly release it here for clarity and immediate release.
    private func releaseLock() {
        guard isLocked else { return }
        
        #if canImport(Darwin) || canImport(Glibc)
        let fd = fileHandle.fileDescriptor
        let result = flock(fd, LOCK_UN)
        IOTraceSink.record(
            operation: "lock_released",
            path: fileURL.path,
            fd: fd,
            resultCode: result,
            errnoValue: result != 0 ? errno : nil
        )
        if result != 0 {
            // Log but don't throw - deinit cannot throw
            // Lock will be released by OS when file descriptor closes
            BlazeLogger.warn("⚠️ Failed to release file lock: \(String(cString: strerror(errno)))")
        }
        isLocked = false
        BlazeLogger.debug("🔓 Released file lock on \(fileURL.lastPathComponent)")
        #endif
    }
    
    // MARK: - Atomic I/O (pread/pwrite)
    // These combine seek+read/write into a single atomic syscall.
    // No shared file offset — safe for concurrent readers without any lock.

    /// Read `count` bytes at `offset` using pread(). Thread-safe without locking.
    internal func atomicRead(offset: off_t, count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        let bytesRead = pread(fd, &buffer, count, offset)
        IOTraceSink.record(
            operation: "pread",
            path: fileURL.path,
            fd: fd,
            resultCode: Int32(bytesRead),
            errnoValue: bytesRead < 0 ? errno : nil,
            context: ["offset": "\(offset)", "count": "\(count)"]
        )
        if bytesRead < 0 {
            let err = errno
            throw NSError(domain: "PageStore", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "pread failed at offset \(offset): \(String(cString: strerror(err)))"
            ])
        }
        return Data(buffer.prefix(bytesRead))
    }

    /// Write `data` at `offset` using pwrite(). Caller must hold barrier.
    internal func atomicWrite(offset: off_t, data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bytesWritten = pwrite(fd, baseAddress, data.count, offset)
            IOTraceSink.record(
                operation: "pwrite",
                path: fileURL.path,
                fd: fd,
                resultCode: Int32(bytesWritten),
                errnoValue: bytesWritten < 0 ? errno : nil,
                context: ["offset": "\(offset)", "count": "\(data.count)"]
            )
            if bytesWritten < 0 {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    let ownerHint = IOTraceSink.ownerHint(for: fileURL.path)
                    let summary = IOTraceSink.dumpTailSummary(
                        reason: "posix_eagain",
                        operation: "pwrite",
                        path: fileURL.path,
                        errnoValue: err
                    )
                    throw IOError.posix(
                        operation: "pwrite",
                        path: fileURL.path,
                        errnoValue: err,
                        nonBlockingLock: false,
                        ownerHint: ownerHint,
                        traceSummaryPath: summary?.path
                    )
                }
                throw NSError(domain: "PageStore", code: Int(err), userInfo: [
                    NSLocalizedDescriptionKey: "pwrite failed at offset \(offset): \(String(cString: strerror(err)))"
                ])
            }
            if bytesWritten != data.count {
                throw NSError(domain: "PageStore", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "pwrite short write: wrote \(bytesWritten) of \(data.count) bytes"
                ])
            }
        }
    }

    /// Get current file size using fstat(). No seek needed.
    internal func fileSize() throws -> Int {
        var stat = stat()
        if fstat(fd, &stat) != 0 {
            let err = errno
            throw NSError(domain: "PageStore", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "fstat failed: \(String(cString: strerror(err)))"
            ])
        }
        return Int(stat.st_size)
    }

    public func deletePage(index: Int) throws {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        try queue.sync(flags: .barrier) {
            // Invalidate cache on delete
            pageCache.remove(index)
            
            let offset = off_t(index * pageSize)
            BlazeLogger.trace("Deleting page at index \(index), zeroing bytes at offset \(offset)")
            let zeroed = Data(repeating: 0, count: pageSize)
            try atomicWrite(offset: offset, data: zeroed)
            try fileHandle.compatSynchronize()
            BlazeLogger.trace("Page \(index) deleted (zeroed)")
        }
    }

    // MARK: - Compatibility shims for tests (non-encrypted API names)
    @inline(__always)
    public func write(index: Int, data: Data) throws {
        try writePage(index: index, plaintext: data)
    }

    @inline(__always)
    public func read(index: Int) throws -> Data? {
        return try readPage(index: index)
    }
    
    // MARK: - Friendlier shims used by tests (append + unlabeled read)

    /// Appends a page to the end of the file and returns the assigned page index.
    @discardableResult
    public func write(_ data: Data) throws -> Int {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        return try queue.sync(flags: .barrier) {
            // Determine next page index from current file size.
            let currentSize = try self.fileSize()
            let nextIndex = max(0, currentSize / pageSize)
            BlazeLogger.trace("Appending plaintext page at index \(nextIndex) with size \(data.count)")
            try _writePageLocked(index: nextIndex, plaintext: data)
            return nextIndex
        }
    }

    /// Unlabeled read overload for convenience.
    public func read(_ index: Int) throws -> Data? {
        return try read(index: index)
    }

    // Performs a write assuming the caller already holds the barrier on `queue`
    internal func _writePageLocked(index: Int, plaintext: Data) throws {
        BlazeLogger.trace("Writing encrypted page at index \(index) with size \(plaintext.count)")
        let buffer = try _encryptPageBuffer(plaintext: plaintext)
        try _writeEncryptedBufferDurablyLocked(index: index, buffer: buffer)
        BlazeLogger.trace("✅ Page \(index) encrypted and flushed to disk")
    }

    /// Encrypt plaintext into a full page-size buffer ready for WAL or pwrite.
    /// Does NOT write to disk or WAL — caller is responsible for both.
    /// Must be called under barrier on `queue`.
    internal func _encryptPageBuffer(plaintext: Data) throws -> Data {
        var buffer = Data()
        guard let magicBytes = "BZDB".data(using: .utf8) else {
            throw NSError(domain: "PageStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode page header magic"
            ])
        }
        buffer.append(magicBytes)

        #if BLAZEDB_BENCHMARK_NO_ENCRYPTION
        let totalSize = 9 + plaintext.count
        guard totalSize <= pageSize else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Page too large (max: \(pageSize - 9) bytes for plaintext benchmark mode)"
            ])
        }
        buffer.append(0x01)
        var length = UInt32(plaintext.count).bigEndian
        buffer.append(Data(bytes: &length, count: 4))
        buffer.append(contentsOf: plaintext)
        #else
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag

        let totalSize = 9 + 12 + 16 + ciphertext.count
        guard totalSize <= pageSize else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Page too large (max: \(pageSize - 37) bytes for encrypted data)"
            ])
        }
        buffer.append(0x02)
        var length = UInt32(plaintext.count).bigEndian
        buffer.append(Data(bytes: &length, count: 4))
        buffer.append(contentsOf: nonce)
        buffer.append(contentsOf: tag)
        buffer.append(contentsOf: ciphertext)
        #endif

        if buffer.count < pageSize {
            buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
        }

        return buffer
    }

    /// pwrite an already-encrypted page buffer to the main file. No WAL, no fsync.
    /// Must be called under barrier on `queue`.
    internal func _writeEncryptedBuffer(index: Int, buffer: Data) throws {
        pageCache.remove(index)
        let offset = off_t(index * pageSize)
        try atomicWrite(offset: offset, data: buffer)
    }

    /// Append durable WAL entries, write encrypted buffer to main file, then fsync.
    /// Must be called under barrier on `queue`.
    internal func _writeEncryptedBufferDurablyLocked(index: Int, buffer: Data) throws {
        // Ensure previously staged unified unsynchronized writes are durably committed
        // and applied before issuing an immediate synchronized write.
        try _commitPendingUnifiedAutoTransactionIfNeededLocked()
        try _flushPendingUnifiedBufferedWritesLocked()

        if let wal = wal {
            // Legacy mode: append WAL entry first, then apply to main file.
            try wal.append(pageIndex: index, data: buffer)
        } else if let dm = durabilityManager {
            // Unified mode: durable WAL commit before writing main file.
            let txID = UUID()
            try dm.appendBegin(transactionID: txID)
            guard index >= 0, index <= Int(UInt32.max) else {
                throw NSError(domain: "PageStore", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Page index \(index) out of UInt32 range for WAL entry"
                ])
            }
            try dm.appendWrite(transactionID: txID, pageIndex: UInt32(index), data: buffer)
            try dm.appendCommit(transactionID: txID)
        }

        try _writeEncryptedBuffer(index: index, buffer: buffer)
        try fileHandle.compatSynchronize()
    }

    private func _commitPendingUnifiedAutoTransactionIfNeededLocked() throws {
        guard let dm = durabilityManager, let txID = pendingUnifiedAutoTransactionID else { return }
        try dm.appendCommit(transactionID: txID)
        pendingUnifiedAutoTransactionID = nil
    }

    internal func _flushPendingUnifiedBufferedWritesLocked() throws {
        guard pendingUnifiedBufferedWrites.isEmpty == false else { return }
        for entry in pendingUnifiedBufferedWrites {
            try _writeEncryptedBuffer(index: entry.index, buffer: entry.buffer)
        }
        pendingUnifiedBufferedWrites.removeAll(keepingCapacity: false)
    }

    // Write without fsyncing (for batch operations)
    internal func _writePageLockedUnsynchronized(index: Int, plaintext: Data) throws {
        pageCache.remove(index)
        BlazeLogger.trace("Writing encrypted page at index \(index) with size \(plaintext.count)")

        let buffer = try _encryptPageBuffer(plaintext: plaintext)

        // 📜 WAL: Append to Write-Ahead Log BEFORE writing to main file
        if let wal = wal {
            try wal.append(pageIndex: index, data: buffer)
        } else if let dm = durabilityManager {
            // Unified mode: group unsynchronized writes in a single auto-transaction.
            // IMPORTANT: We stage main-file writes in memory and flush only after
            // a durable commit to preserve crash atomicity boundaries.
            let txID: UUID
            if let existing = pendingUnifiedAutoTransactionID {
                txID = existing
            } else {
                let created = UUID()
                try dm.appendBegin(transactionID: created)
                pendingUnifiedAutoTransactionID = created
                txID = created
            }
            guard index >= 0, index <= Int(UInt32.max) else {
                throw NSError(domain: "PageStore", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Page index \(index) out of UInt32 range for WAL entry"
                ])
            }
            try dm.appendWrite(transactionID: txID, pageIndex: UInt32(index), data: buffer)
            pendingUnifiedBufferedWrites.append((index: index, buffer: buffer))
            return
        }

        let offset = off_t(index * pageSize)
        BlazeLogger.trace("Writing page at byte offset \(offset)")
        try atomicWrite(offset: offset, data: buffer)
    }

    public func writePage(index: Int, plaintext: Data) throws {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        try queue.sync(flags: .barrier) {
            try _writePageLocked(index: index, plaintext: plaintext)
        }
    }
    
    /// Write a page without synchronizing to disk (for batch operations)
    /// ⚠️ Must call `synchronize()` after batch is complete!
    public func writePageUnsynchronized(index: Int, plaintext: Data) throws {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        try queue.sync(flags: .barrier) {
            try _writePageLockedUnsynchronized(index: index, plaintext: plaintext)
        }
    }
    
    /// Flush all pending writes to disk
    public func synchronize() throws {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        try queue.sync(flags: .barrier) {
            try _commitPendingUnifiedAutoTransactionIfNeededLocked()
            try _flushPendingUnifiedBufferedWritesLocked()
            try fileHandle.compatSynchronize()
        }
    }

    // MARK: - Back-compatibility shim for tests
    @inlinable
    public func writePage(index: Int, data: Data) throws {
        try writePage(index: index, plaintext: data)
    }

    public func readPage(index: Int) throws -> Data? {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        return try queue.sync { () throws -> Data? in
            // Check cache first (MASSIVE speedup for repeated reads!)
            // Note: Cache stores decrypted data for maximum performance
            if let cached = pageCache.get(index) {
                return cached
            }

            let offset = off_t(index * pageSize)
            // Check file size using fstat (no seek, no shared state)
            let currentFileSize = try self.fileSize()
            if offset >= currentFileSize {
                BlazeLogger.warn("Offset out of range for page \(index) — returning nil")
                return nil
            }
            // pread: atomic seek+read, safe for concurrent readers
            var page = try atomicRead(offset: offset, count: pageSize)
            if page.count < pageSize {
                let padding = Data(repeating: 0, count: pageSize - page.count)
                page.append(padding)
            }

            if page.allSatisfy({ $0 == 0 }) {
                BlazeLogger.warn("Page \(index) empty after delete/rollback — returning nil")
                return nil
            }

            guard page.count >= 9 else {
                BlazeLogger.error("Throwing read error for page \(index) (too short for header+length)")
                throw NSError(domain: "PageStore", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty page at index \(index)"])
            }

            // Validate header magic bytes
            let isValidHeader = page[0] == 0x42 && page[1] == 0x5A && page[2] == 0x44 && page[3] == 0x42
            if !isValidHeader {
                BlazeLogger.warn("Invalid header for page \(index) — returning nil")
                return nil
            }
            
            // Check version to determine format
            let version = page[4]
            
            // VERSION 0x01: Plaintext (backward compatibility)
            if version == 0x01 {
                // Read payload length from bytes 5-8 (UInt32, big-endian)
                let lengthBytes = page.subdata(in: 5..<9)
                let payloadLength = lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                
                BlazeLogger.trace("Page \(index) plaintext, payload length: \(payloadLength) bytes")
                
                if payloadLength == 0 {
                    let empty = Data()
                    pageCache.set(index, data: empty)  // Cache empty result
                    return empty
                }
                
                guard payloadLength <= page.count - 9 else {
                    throw NSError(domain: "PageStore", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Corrupt page length at index \(index)"])
                }
                
                let payload = page.subdata(in: 9..<(9 + Int(payloadLength)))
                pageCache.set(index, data: payload)  // Cache decrypted payload
                return payload
            }
            
            // VERSION 0x02: Encrypted (AES-GCM)
            else if version == 0x02 {
                // ✅ DECRYPT DATA
                // Read original plaintext length
                let lengthBytes = page.subdata(in: 5..<9)
                let plaintextLength = Int(lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                
                // Extract nonce (12 bytes at offset 9)
                guard page.count >= 37 else {
                    throw NSError(domain: "PageStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Page too short for encrypted format"])
                }
                
                let nonceData = page.subdata(in: 9..<21)
                guard let nonce = try? AES.GCM.Nonce(data: nonceData) else {
                    throw NSError(domain: "PageStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid nonce for page \(index)"])
                }
                
                // Extract tag (16 bytes at offset 21)
                let tagData = page.subdata(in: 21..<37)
                
                // Extract ciphertext (starts at offset 37)
                // ✅ FIX: AES-GCM ciphertext is exactly plaintextLength (no padding needed)
                let ciphertextLength = plaintextLength
                let ciphertextEnd = min(37 + ciphertextLength, page.count)
                let ciphertext = page.subdata(in: 37..<ciphertextEnd)
                
                // Reconstruct sealed box
                guard let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData) else {
                    throw NSError(domain: "PageStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Corrupted encryption data for page \(index)"])
                }
                
                // Decrypt and authenticate
                let decrypted = try AES.GCM.open(sealedBox, using: key)
                
                // Cache the decrypted data for future reads (instant return!)
                pageCache.set(index, data: decrypted)
                
                BlazeLogger.trace("✅ Page \(index) decrypted: \(decrypted.count) bytes")
                return decrypted
            }
            
            // VERSION 0x03: Compressed page marker.
            // Compression APIs are conditionally compiled, so on unsupported platforms
            // this must fail with an explicit portability message.
            else if version == 0x03 {
                #if canImport(Compression)
                let decompressed = try _decodeCompressedPageV03(storedPage: page, index: index)
                pageCache.set(index, data: decompressed)
                return decompressed
                #else
                throw NSError(domain: "PageStore", code: 6, userInfo: [
                    NSLocalizedDescriptionKey: "Page \(index) uses compression (version 0x03) that is not available on this platform"
                ])
                #endif
            }
            
            // Unknown version
            else {
                BlazeLogger.error("Unsupported page version \(version) for page \(index)")
                throw NSError(domain: "PageStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unsupported page version: \(version)"])
            }
        }
    }

    // Returns (totalPages, orphanedPages, estimatedSize)
    public func getStorageStats() throws -> (totalPages: Int, orphanedPages: Int, estimatedSize: Int) {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        return try queue.sync {
            let currentFileSize = try self.fileSize()
            let totalPages = max(0, currentFileSize / pageSize)

            var orphanedPages = 0
            let expectedHeaderV1 = ("BZDB".data(using: .utf8) ?? Data()) + Data([0x01])
            let expectedHeaderV2 = ("BZDB".data(using: .utf8) ?? Data()) + Data([0x02])
            for i in 0..<totalPages {
                let header = try atomicRead(offset: off_t(i * pageSize), count: 5)
                if header != expectedHeaderV1 && header != expectedHeaderV2 {
                    orphanedPages += 1
                }
            }
            return (totalPages, orphanedPages, currentFileSize)
        }
    }

    // MARK: - Compatibility aliases for tests
    public var url: URL { fileURL }

    /// Delete a page by zeroing it out (marks as deleted, can be reused)
    /// This is a safe operation that doesn't require exclusive access
    // MARK: - MVCC Support
    
    /// Get the next available page index for MVCC
    /// This calculates based on current file size
    public func nextAvailablePageIndex() throws -> Int {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        return try queue.sync {
            let currentSize = try self.fileSize()
            return currentSize / pageSize
        }
    }
    
    // MARK: - WAL Checkpoint
    
    /// Checkpoint the WAL - sync main file and clear WAL
    /// Call this periodically or after batches of writes to limit WAL size
    public func checkpoint() throws {
        try queue.sync(flags: .barrier) {
            try _commitPendingUnifiedAutoTransactionIfNeededLocked()
            try _flushPendingUnifiedBufferedWritesLocked()
            try fileHandle.compatSynchronize()

            switch walMode {
            case .legacy:
                guard let wal = wal else { return }
                try wal.clear()
            case .unified:
                guard let dm = durabilityManager else { return }
                try dm.checkpoint()
            }
            BlazeLogger.debug("📜 WAL checkpoint complete")
        }
    }
    
    /// Get WAL statistics
    public func walStats() -> WALStats? {
        return wal?.getStats()
    }

    public func close() {
        queue.sync(flags: .barrier) {
            guard !closed else { return }

            switch walMode {
            case .legacy:
                if let wal = wal {
                    var mainSyncSucceeded = false
                    do {
                        try fileHandle.compatSynchronize()
                        IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: 0, context: ["phase": "close"])
                        mainSyncSucceeded = true
                    } catch {
                        IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: -1, errnoValue: errno, context: ["phase": "close"])
                        BlazeLogger.error("📜 Close fsync failed; preserving WAL: \(RecoveryError.closeFsyncFailed(underlying: error).localizedDescription)")
                    }

                    if mainSyncSucceeded {
                        do {
                            try wal.clear()
                        } catch {
                            BlazeLogger.error("📜 WAL clear failed during close: \(error.localizedDescription)")
                        }
                    } else {
                        BlazeLogger.warn("📜 WAL preserved because close fsync did not succeed")
                    }
                    wal.close()
                }

            case .unified:
                if let dm = durabilityManager {
                    do {
                        try _commitPendingUnifiedAutoTransactionIfNeededLocked()
                        try _flushPendingUnifiedBufferedWritesLocked()
                    } catch {
                        BlazeLogger.error("📜 Failed to commit pending unified auto-transaction during close: \(error.localizedDescription)")
                    }
                    var mainSyncSucceeded = false
                    do {
                        try fileHandle.compatSynchronize()
                        IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: 0, context: ["phase": "close"])
                        mainSyncSucceeded = true
                    } catch {
                        IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: -1, errnoValue: errno, context: ["phase": "close"])
                        BlazeLogger.error("📜 Close fsync failed; preserving WAL: \(RecoveryError.closeFsyncFailed(underlying: error).localizedDescription)")
                    }

                    if mainSyncSucceeded {
                        do {
                            try dm.checkpoint()
                        } catch {
                            BlazeLogger.error("📜 WAL checkpoint failed during close: \(error.localizedDescription)")
                        }
                    } else {
                        BlazeLogger.warn("📜 WAL preserved because close fsync did not succeed")
                    }
                    try? dm.close()
                }
            }

            // Flush while lock is still held to avoid races with immediate reopen.
            try? fileHandle.compatSynchronize()
            IOTraceSink.record(operation: "fsync_main", path: fileURL.path, fd: fd, resultCode: 0, context: ["phase": "close_final"])

            // Release lock and close descriptor deterministically.
            releaseLock()
            fileHandle.compatClose()
            IOTraceSink.record(operation: "close_handle", path: fileURL.path, fd: fd, resultCode: 0)
            closed = true
        }
    }
    
    deinit {
        close()
    }
}

extension PageStore {
    internal func overflowReadDegradedModeEnabled() -> Bool {
        overflowCorruptionLock.lock()
        defer { overflowCorruptionLock.unlock() }
        return overflowReadDegradedMode
    }

    internal func overflowCorruptionIncidentSnapshot() -> Int {
        overflowCorruptionLock.lock()
        defer { overflowCorruptionLock.unlock() }
        return overflowCorruptionIncidentCount
    }
}
