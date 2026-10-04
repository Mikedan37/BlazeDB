//
//  WriteAheadLog.swift
//  BlazeDB
//
//  Write-Ahead Log providing crash-safety for page writes.
//
//  V1.5 rewrite: framed entries with CRC32, fsync on every append, replay on open.
//
//  Page record:
//    [magic 4B "WALE"] [pageIndex UInt32 LE] [dataLen UInt32 LE] [crc32 UInt32 LE] [data …]
//  Commit record (20 bytes), written after the page records it covers:
//    [magic 4B "WALC"] [txnId UInt32 LE] [pageCount UInt32 LE] [chainCRC UInt32 LE] [recordCRC UInt32 LE]
//  chainCRC is the CRC32 of those page records' on-disk bytes, in order.
//  recordCRC is the CRC32 of the first 16 bytes of the commit record.
//  Recovery applies a group only when its commit record is complete and matches.
//
//  Created by Michael Danylchuk.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#endif

// MARK: - WAL Entry Format

/// On-disk WAL entry header (16 bytes)
///
/// Layout:
///   [0..3]   magic    "WALE" (0x57414C45)
///   [4..7]   pageIndex  UInt32 little-endian
///   [8..11]  dataLen    UInt32 little-endian
///   [12..15] crc32      UInt32 little-endian (CRC of the *data* bytes only)
private let walEntryMagic: UInt32 = 0x57414C45  // "WALE" in ASCII (big-endian reading)
private let walCommitMagic: UInt32 = 0x57414C43  // "WALC" in ASCII (big-endian reading)
private let walEntryHeaderSize = 16
private let walCommitRecordSize = 20

// MARK: - WriteAheadLog

/// Synchronous, crash-safe Write-Ahead Log.
///
/// Design:
///  - `append()` writes a framed entry and fsyncs (immediate durability).
///  - `appendDeferred()` + `sync()` batch multiple entries with one fsync (caller must sync before commit returns).
///  - On open, `replay()` reads all valid entries and returns them for the caller
///    to apply to the PageStore.
///  - After the caller confirms all entries are applied (and the main file is fsynced),
///    call `clear()` to truncate the WAL. Clearing earlier can hide recoverable commits.
///  - NOT an actor: all callers must serialize externally (PageStore's barrier queue).
///  - This type does not take the DB file flock; PageStore owns process exclusivity.
internal final class WriteAheadLog: @unchecked Sendable {
    let logURL: URL
    private var fd: Int32 = -1
    private var currentOffset: off_t = 0  // tracks append position
    private var needsFsync = false
    /// On-disk bytes of page records not yet covered by a commit record.
    private var openGroupRaw: [Data] = []
    private var nextTransactionID: UInt32 = 1

    /// Fixed size of a commit record. Tests use this to locate records.
    internal static let commitRecordSize = 20

    /// Open (or create) the WAL file.
    init(logURL: URL) throws {
        self.logURL = logURL
        IOTraceSink.record(operation: "wal_open_begin", path: logURL.path)

        // Open with O_CREAT | O_RDWR so we can both replay (read) and append (write).
        // Owner-only mode on create (#357); existing files keep prior mode.
        let flags: Int32 = O_RDWR | O_CREAT
        let mode: mode_t = 0o600
        let opened = logURL.path.withCString { path in
            #if canImport(Darwin)
            Darwin.open(path, flags, mode)
            #elseif canImport(Glibc)
            Glibc.open(path, flags, mode)
            #else
            open(path, flags, mode)
            #endif
        }
        guard opened >= 0 else {
            let err = errno
            IOTraceSink.record(operation: "wal_open", path: logURL.path, resultCode: opened, errnoValue: err)
            throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "Failed to open WAL at \(logURL.path): \(String(cString: strerror(err)))"
            ])
        }
        self.fd = opened
        IOTraceSink.record(operation: "wal_open", path: logURL.path, fd: fd, resultCode: 0)

        // Seek to end so appends go to the right place
        self.currentOffset = lseek(fd, 0, SEEK_END)
    }

    // MARK: - Append

    /// Append a page write to the WAL without fsync. Call `sync()` before treating the write as durable.
    func appendDeferred(pageIndex: Int, data: Data) throws {
        try WriteProfileCollector.measure("wal.append") {
            let raw = try appendEntry(pageIndex: pageIndex, data: data)
            openGroupRaw.append(raw)
            // Header (16) + payload — approximate bytes leaving the process.
            WriteProfileCollector.addBytes(walEntryHeaderSize + data.count)
            WriteProfileCollector.addSyscall(kind: .write)
        }
        needsFsync = true
    }

    /// Drop page records that were appended but not committed.
    /// Their bytes may already be in the file. A later commit does not cover them.
    func abortPendingGroup() {
        openGroupRaw.removeAll()
    }

    /// Append a commit record for the current page group. Does not fsync.
    func commitPendingGroup() throws {
        guard !openGroupRaw.isEmpty else { return }
        let pageCount = openGroupRaw.count
        guard pageCount <= Int(UInt32.max) else {
            throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "WAL transaction page count exceeds UInt32"
            ])
        }
        var chainInput = Data()
        for raw in openGroupRaw {
            chainInput.append(raw)
        }
        let chainCRC = crc32Checksum(chainInput)
        let txnID = nextTransactionID

        var record = Data(capacity: walCommitRecordSize)
        var magic = walCommitMagic.littleEndian
        record.append(Data(bytes: &magic, count: 4))
        var txn = txnID.littleEndian
        record.append(Data(bytes: &txn, count: 4))
        var count = UInt32(pageCount).littleEndian
        record.append(Data(bytes: &count, count: 4))
        var chain = chainCRC.littleEndian
        record.append(Data(bytes: &chain, count: 4))
        let recordCRC = crc32Checksum(record)
        var crc = recordCRC.littleEndian
        record.append(Data(bytes: &crc, count: 4))

        try WriteProfileCollector.measure("wal.commit") {
            try pwriteAll(record)
            WriteProfileCollector.addBytes(record.count)
            WriteProfileCollector.addSyscall(kind: .write)
        }
        openGroupRaw.removeAll()
        nextTransactionID &+= 1
        needsFsync = true
    }

    /// Fsync pending WAL appends from `appendDeferred`.
    func sync() throws {
        guard fd >= 0, needsFsync else { return }
        try WriteProfileCollector.measure("wal.fsync") {
            if fsync(fd) != 0 {
                let err = errno
                IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: -1, errnoValue: err)
                throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                    NSLocalizedDescriptionKey: "WAL fsync failed: \(String(cString: strerror(err)))"
                ])
            }
            IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: 0)
            WriteProfileCollector.addSyscall(kind: .fsync)
            needsFsync = false
        }
    }

    /// Append a page write to the WAL. Fsyncs before returning.
    ///
    /// - Parameters:
    ///   - pageIndex: The page index being written
    ///   - data: The encrypted page data (already encrypted by PageStore)
    func append(pageIndex: Int, data: Data) throws {
        try appendDeferred(pageIndex: pageIndex, data: data)
        try commitPendingGroup()
        try sync()
    }

    @discardableResult
    private func appendEntry(pageIndex: Int, data: Data) throws -> Data {
        guard fd >= 0 else {
            throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "WAL file not open"
            ])
        }
        guard pageIndex >= 0, pageIndex <= Int(UInt32.max) else {
            throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Page index \(pageIndex) out of UInt32 range"
            ])
        }

        // Build header
        var header = Data(capacity: walEntryHeaderSize)

        // Magic bytes "WALE"
        var magic = walEntryMagic.littleEndian
        header.append(Data(bytes: &magic, count: 4))

        // Page index
        var idx = UInt32(pageIndex).littleEndian
        header.append(Data(bytes: &idx, count: 4))

        // Data length
        var len = UInt32(data.count).littleEndian
        header.append(Data(bytes: &len, count: 4))

        // CRC32 of data
        let checksum = crc32Checksum(data)
        var crc = checksum.littleEndian
        header.append(Data(bytes: &crc, count: 4))

        // Write header + data as a single pwrite for atomicity
        var combined = header
        combined.append(data)
        try pwriteAll(combined)
        return combined
    }

    private func pwriteAll(_ bytes: Data) throws {
        try bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "WAL pwrite source buffer was empty"
                ])
            }
            let written = pwrite(fd, base, bytes.count, currentOffset)
            IOTraceSink.record(
                operation: "wal_pwrite",
                path: logURL.path,
                fd: fd,
                resultCode: Int32(written),
                errnoValue: written < 0 ? errno : nil,
                context: ["offset": "\(currentOffset)", "count": "\(bytes.count)"]
            )
            if written < 0 {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    let ownerHint = IOTraceSink.ownerHint(for: logURL.path)
                    let summary = IOTraceSink.dumpTailSummary(
                        reason: "posix_eagain",
                        operation: "wal_pwrite",
                        path: logURL.path,
                        errnoValue: err
                    )
                    throw PageStore.IOError.posix(
                        operation: "wal_pwrite",
                        path: logURL.path,
                        errnoValue: err,
                        nonBlockingLock: false,
                        ownerHint: ownerHint,
                        traceSummaryPath: summary?.path
                    )
                }
                throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                    NSLocalizedDescriptionKey: "WAL pwrite failed: \(String(cString: strerror(err)))"
                ])
            }
            if written != bytes.count {
                throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "WAL short write: \(written)/\(bytes.count)"
                ])
            }
        }
        currentOffset += off_t(bytes.count)
    }

    // MARK: - Replay

    /// Replay page records whose transaction has a complete, matching commit record.
    ///
    /// A torn tail, a corrupt commit record, or page records with no commit record
    /// are not recovered. A CRC or magic failure with another page record after it
    /// is mid-log corruption: throw `WALError.midLogCorruption` so the caller does
    /// not apply a prefix and then `clear()` the unread tail.
    func replay() throws -> [(pageIndex: Int, data: Data)] {
        guard fd >= 0 else { return [] }

        var st = stat()
        guard fstat(fd, &st) == 0 else { return [] }
        let fileSize = Int(st.st_size)
        guard fileSize > 0 else { return [] }

        struct PendingPage {
            let pageIndex: Int
            let data: Data
            let raw: Data
        }

        var committed: [(pageIndex: Int, data: Data)] = []
        var pending: [PendingPage] = []
        var offset = 0

        while offset + 4 <= fileSize {
            guard let magicBytes = readExact(count: 4, at: off_t(offset), operation: "wal_pread_magic") else {
                break
            }
            let magic = magicBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }

            if magic == walCommitMagic.littleEndian {
                guard offset + walCommitRecordSize <= fileSize else {
                    BlazeLogger.warn("WAL replay: torn commit record at offset \(offset), discarding open group")
                    break
                }
                guard let record = readExact(count: walCommitRecordSize, at: off_t(offset), operation: "wal_pread_commit") else {
                    break
                }
                let recordCRC = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self).littleEndian }
                let computedRecordCRC = crc32Checksum(Data(record.prefix(16)))
                let nextOffset = offset + walCommitRecordSize
                guard computedRecordCRC == recordCRC else {
                    try stopOrThrowMidLog(fileSize: fileSize, after: nextOffset, reason: "commit CRC mismatch at offset \(offset)")
                    break
                }
                let pageCount = Int(record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian })
                let chainCRC = record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian }
                guard pageCount > 0, pageCount <= pending.count else {
                    try stopOrThrowMidLog(fileSize: fileSize, after: nextOffset, reason: "commit page count \(pageCount) does not match \(pending.count) open records")
                    break
                }
                let group = pending.suffix(pageCount)
                var chainInput = Data()
                for page in group {
                    chainInput.append(page.raw)
                }
                guard crc32Checksum(chainInput) == chainCRC else {
                    try stopOrThrowMidLog(fileSize: fileSize, after: nextOffset, reason: "commit chain CRC mismatch at offset \(offset)")
                    break
                }
                committed.append(contentsOf: group.map { (pageIndex: $0.pageIndex, data: $0.data) })
                pending.removeAll()
                offset = nextOffset
                continue
            }

            guard magic == walEntryMagic.littleEndian else {
                let remaining = fileSize - offset
                if remaining > walEntryHeaderSize {
                    BlazeLogger.error("WAL replay: invalid magic at offset \(offset) with \(remaining) bytes remaining")
                    throw WALError.midLogCorruption
                }
                BlazeLogger.warn("WAL replay: invalid magic at offset \(offset), stopping")
                break
            }

            guard let header = readExact(count: walEntryHeaderSize, at: off_t(offset), operation: "wal_pread_header") else {
                break
            }
            let pageIndex = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian })
            let dataLen = Int(header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian })
            let storedCRC = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian }
            let entryEnd = offset + walEntryHeaderSize + dataLen
            guard entryEnd <= fileSize else {
                BlazeLogger.warn("WAL replay: entry at offset \(offset) truncated, discarding open group")
                break
            }
            guard let entryData = readExact(count: dataLen, at: off_t(offset + walEntryHeaderSize), operation: "wal_pread_data") else {
                break
            }
            guard crc32Checksum(entryData) == storedCRC else {
                try stopOrThrowMidLog(fileSize: fileSize, after: entryEnd, reason: "CRC mismatch at offset \(offset)")
                break
            }
            var raw = header
            raw.append(entryData)
            pending.append(PendingPage(pageIndex: pageIndex, data: entryData, raw: raw))
            offset = entryEnd
        }

        if !committed.isEmpty {
            BlazeLogger.info("WAL replay: recovered \(committed.count) committed page records")
        }
        return committed
    }

    /// A failure is a torn tail when no later page record exists. A later page record
    /// means the failure is in the middle of the log.
    private func stopOrThrowMidLog(fileSize: Int, after offset: Int, reason: String) throws {
        if containsLaterPageRecord(fileSize: fileSize, from: offset) {
            BlazeLogger.error("WAL replay: \(reason) with later page records")
            throw WALError.midLogCorruption
        }
        BlazeLogger.warn("WAL replay: \(reason), stopping")
    }

    private func containsLaterPageRecord(fileSize: Int, from offset: Int) -> Bool {
        var cursor = offset
        while cursor + 4 <= fileSize {
            guard let magicBytes = readExact(count: 4, at: off_t(cursor), operation: "wal_pread_magic") else {
                return false
            }
            let magic = magicBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if magic == walCommitMagic.littleEndian {
                guard cursor + walCommitRecordSize <= fileSize else { return false }
                cursor += walCommitRecordSize
                continue
            }
            if magic == walEntryMagic.littleEndian {
                return true
            }
            return false
        }
        return false
    }

    private func readExact(count: Int, at offset: off_t, operation: String) -> Data? {
        guard count > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: count)
        let readCount = pread(fd, &buffer, count, offset)
        IOTraceSink.record(
            operation: operation,
            path: logURL.path,
            fd: fd,
            resultCode: Int32(readCount),
            errnoValue: readCount < 0 ? errno : nil,
            context: ["offset": "\(offset)", "count": "\(count)"]
        )
        guard readCount == count else { return nil }
        return Data(buffer)
    }

    // MARK: - Clear

    /// Truncate the WAL to zero after a successful checkpoint.
    func clear() throws {
        guard fd >= 0 else { return }
        if ftruncate(fd, 0) != 0 {
            let err = errno
            IOTraceSink.record(operation: "wal_truncate", path: logURL.path, fd: fd, resultCode: -1, errnoValue: err)
            throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "WAL ftruncate failed: \(String(cString: strerror(err)))"
            ])
        }
        IOTraceSink.record(operation: "wal_truncate", path: logURL.path, fd: fd, resultCode: 0)
        if fsync(fd) != 0 {
            let err = errno
            IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: -1, errnoValue: err, context: ["phase": "clear"])
            throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "WAL fsync after clear failed: \(String(cString: strerror(err)))"
            ])
        }
        IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: 0, context: ["phase": "clear"])
        currentOffset = 0
        needsFsync = false
        openGroupRaw.removeAll()
    }

    // MARK: - Stats

    func getStats() -> WALStats {
        var st = stat()
        let size: Int64 = (fstat(fd, &st) == 0) ? Int64(st.st_size) : 0
        return WALStats(
            pendingWrites: 0,  // No in-memory buffering — everything is fsynced
            lastCheckpoint: Date(),
            logFileSize: size
        )
    }

    // MARK: - Lifecycle

    func close() {
        guard fd >= 0 else { return }
        IOTraceSink.record(operation: "wal_close_begin", path: logURL.path, fd: fd)
        #if canImport(Darwin)
        Darwin.close(fd)
        #elseif canImport(Glibc)
        Glibc.close(fd)
        #elseif canImport(Android)
        Android.close(fd)
        #else
        _ = Foundation.close(fd)
        #endif
        IOTraceSink.record(operation: "wal_close_end", path: logURL.path, fd: fd, resultCode: 0)
        fd = -1
    }

    deinit {
        close()
    }

    // MARK: - CRC32

    private func crc32Checksum(_ data: Data) -> UInt32 {
        // Must match zlib CRC32 / BlazeBinary paths; use shared implementation so Linux CI builds without Swift `zlib` module.
        BlazeBinaryEncoder.calculateCRC32(data)
    }
}

/// WAL statistics (public — used by observability layer)
public struct WALStats: Sendable, Codable {
    public let pendingWrites: Int
    public let lastCheckpoint: Date
    public let logFileSize: Int64
}
