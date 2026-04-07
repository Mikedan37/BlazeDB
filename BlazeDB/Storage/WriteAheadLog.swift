//
//  WriteAheadLog.swift
//  BlazeDB
//
//  Write-Ahead Log providing crash-safety for page writes.
//
//  V1.5 rewrite: framed entries with CRC32, fsync on every append, replay on open.
//
//  Entry format (on disk):
//    [magic 4B "WALE"] [pageIndex UInt32 LE] [dataLen UInt32 LE] [crc32 UInt32 LE] [data …]
//  Total header = 16 bytes, followed by `dataLen` bytes of payload.
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
private let walEntryHeaderSize = 16

// MARK: - WriteAheadLog

/// Synchronous, crash-safe Write-Ahead Log.
///
/// Design:
///  - Every `append()` writes a framed entry and calls `fsync` before returning.
///  - On open, `replay()` reads all valid entries and returns them for the caller
///    to apply to the PageStore.
///  - After the caller confirms all entries are applied (and the main file is fsynced),
///    call `clear()` to truncate the WAL.
///  - NOT an actor: all callers must serialize externally (PageStore's barrier queue).
internal final class WriteAheadLog: @unchecked Sendable {
    let logURL: URL
    private var fd: Int32 = -1
    private var currentOffset: off_t = 0  // tracks append position

    /// Open (or create) the WAL file.
    init(logURL: URL) throws {
        self.logURL = logURL
        IOTraceSink.record(operation: "wal_open_begin", path: logURL.path)

        // Open with O_CREAT | O_RDWR so we can both replay (read) and append (write).
        let flags: Int32 = O_RDWR | O_CREAT
        let mode: mode_t = 0o644
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

    /// Append a page write to the WAL. Fsyncs before returning.
    ///
    /// - Parameters:
    ///   - pageIndex: The page index being written
    ///   - data: The encrypted page data (already encrypted by PageStore)
    func append(pageIndex: Int, data: Data) throws {
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

        try combined.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            let written = pwrite(fd, base, combined.count, currentOffset)
            IOTraceSink.record(
                operation: "wal_pwrite",
                path: logURL.path,
                fd: fd,
                resultCode: Int32(written),
                errnoValue: written < 0 ? errno : nil,
                context: ["offset": "\(currentOffset)", "count": "\(combined.count)"]
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
            if written != combined.count {
                throw NSError(domain: "WriteAheadLog", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "WAL short write: \(written)/\(combined.count)"
                ])
            }
        }

        currentOffset += off_t(combined.count)

        // fsync — the whole point of a WAL
        if fsync(fd) != 0 {
            let err = errno
            IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: -1, errnoValue: err)
            throw NSError(domain: "WriteAheadLog", code: Int(err), userInfo: [
                NSLocalizedDescriptionKey: "WAL fsync failed: \(String(cString: strerror(err)))"
            ])
        }
        IOTraceSink.record(operation: "wal_fsync", path: logURL.path, fd: fd, resultCode: 0)
    }

    // MARK: - Replay

    /// Replay all valid WAL entries from the beginning of the file.
    ///
    /// Stops at the first invalid/corrupt entry (torn write from crash).
    /// Returns entries in order — caller should apply them to PageStore.
    func replay() throws -> [(pageIndex: Int, data: Data)] {
        guard fd >= 0 else { return [] }

        // Get file size
        var st = stat()
        guard fstat(fd, &st) == 0 else { return [] }
        let fileSize = Int(st.st_size)
        guard fileSize > 0 else { return [] }

        var entries: [(pageIndex: Int, data: Data)] = []
        var offset: off_t = 0

        while Int(offset) + walEntryHeaderSize <= fileSize {
            // Read header
            var headerBuf = [UInt8](repeating: 0, count: walEntryHeaderSize)
            let hRead = pread(fd, &headerBuf, walEntryHeaderSize, offset)
            IOTraceSink.record(
                operation: "wal_pread_header",
                path: logURL.path,
                fd: fd,
                resultCode: Int32(hRead),
                errnoValue: hRead < 0 ? errno : nil,
                context: ["offset": "\(offset)", "count": "\(walEntryHeaderSize)"]
            )
            guard hRead == walEntryHeaderSize else { break }

            let headerData = Data(headerBuf)

            // Validate magic
            let magic = headerData.withUnsafeBytes { buf in
                buf.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            }
            guard magic == walEntryMagic.littleEndian else {
                BlazeLogger.warn("WAL replay: invalid magic at offset \(offset), stopping")
                break
            }

            // Parse fields
            let pageIndex = Int(headerData.withUnsafeBytes { buf in
                buf.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
            })
            let dataLen = Int(headerData.withUnsafeBytes { buf in
                buf.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian
            })
            let storedCRC = headerData.withUnsafeBytes { buf in
                buf.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian
            }

            // Bounds check
            let entryEnd = Int(offset) + walEntryHeaderSize + dataLen
            guard entryEnd <= fileSize else {
                BlazeLogger.warn("WAL replay: entry at offset \(offset) truncated (needs \(entryEnd), file is \(fileSize)), stopping")
                break
            }

            // Read data
            var dataBuf = [UInt8](repeating: 0, count: dataLen)
            let dRead = pread(fd, &dataBuf, dataLen, offset + off_t(walEntryHeaderSize))
            IOTraceSink.record(
                operation: "wal_pread_data",
                path: logURL.path,
                fd: fd,
                resultCode: Int32(dRead),
                errnoValue: dRead < 0 ? errno : nil,
                context: ["offset": "\(offset + off_t(walEntryHeaderSize))", "count": "\(dataLen)"]
            )
            guard dRead == dataLen else {
                BlazeLogger.warn("WAL replay: short data read at offset \(offset), stopping")
                break
            }
            let entryData = Data(dataBuf)

            // Validate CRC
            let computedCRC = crc32Checksum(entryData)
            guard computedCRC == storedCRC else {
                BlazeLogger.warn("WAL replay: CRC mismatch at offset \(offset) (stored=\(storedCRC), computed=\(computedCRC)), stopping")
                break
            }

            entries.append((pageIndex: pageIndex, data: entryData))
            offset += off_t(walEntryHeaderSize + dataLen)
        }

        if !entries.isEmpty {
            BlazeLogger.info("WAL replay: recovered \(entries.count) entries")
        }

        return entries
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
