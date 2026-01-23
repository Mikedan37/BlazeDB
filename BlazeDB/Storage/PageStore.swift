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
#endif

// Import logger for centralized logging
#if canImport(BlazeDBCore)
import BlazeDBCore
#elseif canImport(BlazeDB)
import BlazeDB
#endif

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

// Swift 6: Thread-safe via internal DispatchQueue synchronization
public final class PageStore: @unchecked Sendable {
    public let fileURL: URL
    internal let fileHandle: FileHandle  // Made internal for PageStore+Overflow access
    internal let key: SymmetricKey  // ✅ ENCRYPTION KEY STORED - Made internal for PageStore+Overflow access
    internal let pageSize = 4096  // Made internal for DynamicCollection access
    
    // MARK: - Concurrency Invariants
    // Invariants:
    // - All public methods entering queue.sync must not already be on `queue`
    // - Re-entrancy is guarded via dispatchPrecondition in DEBUG builds
    // - Internal helpers (_writePageLocked, _writePageLockedUnsynchronized) assume caller holds barrier or queue context
    internal let queue = DispatchQueue(label: "com.yourorg.blazedb.pagestore", attributes: .concurrent)  // Made internal for PageStore+Overflow access
    internal let pageCache = PageCache(maxSize: 1000)  // Made internal for DynamicCollection access
    private var isLocked: Bool = false  // Track lock state for cleanup

    public init(fileURL: URL, key: SymmetricKey) throws {
        self.fileURL = fileURL
        
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
        
        // CRITICAL: Acquire exclusive file lock to prevent multi-process corruption
        try acquireExclusiveLock()
        
        BlazeLogger.debug("🔐 PageStore initialized with \(bitCount)-bit encryption and exclusive file lock")
    }
    
    // MARK: - File Locking
    
    /// Acquire exclusive file lock using POSIX flock()
    /// This prevents multiple processes from writing to the same database file simultaneously.
    /// Lock is automatically released when the file descriptor is closed (process exit or deinit).
    /// 
    /// - Throws: BlazeDBError.databaseLocked if lock cannot be acquired (another process holds it)
    /// - Throws: BlazeDBError.permissionDenied if system error occurs (not a lock conflict)
    /// - Precondition: fileHandle must be initialized before calling this method
    /// - Postcondition: If this method returns, isLocked is true and lock is held
    private func acquireExclusiveLock() throws {
        #if canImport(Darwin) || canImport(Glibc)
        let fd = fileHandle.fileDescriptor
        let result = flock(fd, LOCK_EX | LOCK_NB)
        
        if result != 0 {
            // Lock acquisition failed
            let errnoValue = errno
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
            
            // Lock conflict - another process holds the lock
            // Close the file handle since we failed to acquire lock
            fileHandle.compatClose()
            
            throw BlazeDBError.databaseLocked(
                operation: "open database",
                timeout: nil,
                path: fileURL
            )
        }
        
        isLocked = true
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
        if result != 0 {
            // Log but don't throw - deinit cannot throw
            // Lock will be released by OS when file descriptor closes
            BlazeLogger.warn("⚠️ Failed to release file lock: \(String(cString: strerror(errno)))")
        }
        isLocked = false
        BlazeLogger.debug("🔓 Released file lock on \(fileURL.lastPathComponent)")
        #endif
    }
    
    public func deletePage(index: Int) throws {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        try queue.sync(flags: .barrier) {
            // Invalidate cache on delete
            pageCache.remove(index)
            
            let offset = UInt64(index * pageSize)
            BlazeLogger.trace("Deleting page at index \(index), zeroing bytes at offset \(offset)")
            try fileHandle.compatSeek(toOffset: offset)
            let zeroed = Data(repeating: 0, count: pageSize)
            try fileHandle.compatWrite(zeroed)
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
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let nextIndex = max(0, fileSize / pageSize)
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
        try _writePageLockedUnsynchronized(index: index, plaintext: plaintext)
        try fileHandle.compatSynchronize()
        BlazeLogger.trace("✅ Page \(index) encrypted and flushed to disk")
    }
    
    // Write without fsyncing (for batch operations)
    internal func _writePageLockedUnsynchronized(index: Int, plaintext: Data) throws {
        // Invalidate cache on write
        pageCache.remove(index)
        BlazeLogger.trace("Writing encrypted page at index \(index) with size \(plaintext.count)")
        
        // ✅ ENCRYPT DATA with AES-GCM-256
        // Generate random nonce (12 bytes)
        let nonce = try AES.GCM.Nonce()
        
        // Encrypt plaintext
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        
        // Extract ciphertext and tag
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag
        
        // Calculate total size: header(4) + version(1) + length(4) + nonce(12) + tag(16) + ciphertext
        let totalSize = 9 + 12 + 16 + ciphertext.count
        guard totalSize <= pageSize else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Page too large (max: \(pageSize - 37) bytes for encrypted data)"
            ])
        }

        // Build encrypted page format:
        // [BZDB][0x02][length][nonce][tag][ciphertext][padding]
        var buffer = Data()
        guard let magicBytes = "BZDB".data(using: .utf8) else {
            throw NSError(domain: "PageStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode page header magic"
            ])
        }
        buffer.append(magicBytes)  // 4 bytes: header magic
        buffer.append(0x02)                        // 1 byte: version 0x02 = encrypted
        
        // 4 bytes: original plaintext length (UInt32, big-endian)
        var length = UInt32(plaintext.count).bigEndian
        buffer.append(Data(bytes: &length, count: 4))
        
        // Encryption components
        buffer.append(contentsOf: nonce)           // 12 bytes: nonce (IV)
        buffer.append(contentsOf: tag)             // 16 bytes: authentication tag
        buffer.append(contentsOf: ciphertext)      // Variable: encrypted data

        // Pad with zeros to reach pageSize
        if buffer.count < pageSize {
            buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
        }

        // Write encrypted page to disk (NO fsync yet!)
        let offset = UInt64(index * pageSize)
        BlazeLogger.trace("Writing encrypted at byte offset \(offset) (nonce: \(nonce.withUnsafeBytes { Data($0).prefix(4).map { String(format: "%02x", $0) }.joined() })...)")
        try fileHandle.compatSeek(toOffset: offset)
        try fileHandle.compatWrite(buffer)
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
        return try queue.sync {
            // Check cache first (MASSIVE speedup for repeated reads!)
            // Note: Cache stores decrypted data for maximum performance
            if let cached = pageCache.get(index) {
                return cached
            }
            
            let offset = UInt64(index * pageSize)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                BlazeLogger.warn("File missing during read(page \(index)) — returning nil")
                return nil
            }
            // Check file size before seeking
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSizeNum = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if offset >= fileSizeNum {
                BlazeLogger.warn("Offset out of range for page \(index) — returning nil")
                return nil
            }
            try fileHandle.compatSeek(toOffset: offset)
            var page = try fileHandle.compatRead(upToCount: pageSize)
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
                let payloadLength = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                
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
                let plaintextLength = Int(lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                
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
            // Correctly fetch file size from the fileURL
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSizeNum = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let totalPages = max(0, fileSizeNum / pageSize)

            var orphanedPages = 0
            let expectedHeader = ("BZDB".data(using: .utf8) ?? Data()) + Data([0x01])
            for i in 0..<totalPages {
                try fileHandle.compatSeek(toOffset: UInt64(i * pageSize))
                let header = try fileHandle.compatRead(upToCount: 5)
                if header != expectedHeader {
                    orphanedPages += 1
                }
            }
            return (totalPages, orphanedPages, fileSizeNum)
        }
    }

    // MARK: - Compatibility aliases for tests
    public var url: URL { fileURL }

    /// Delete a page by zeroing it out (marks as deleted, can be reused)
    /// This is a safe operation that doesn't require exclusive access
    // MARK: - MVCC Support
    
    /// Get the next available page index for MVCC
    /// This calculates based on current file size
    public func nextAvailablePageIndex() -> Int {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(queue))
        #endif
        return queue.sync {
            do {
                let fileSize = try fileHandle.seekToEnd()
                let pageIndex = Int(fileSize) / pageSize
                return pageIndex
            } catch {
                // Fallback: return 0 and let write handle it
                return 0
            }
        }
    }
    
    deinit {
        // Release file lock before closing file handle
        releaseLock()
        
        // Ensure final flush before closing
        try? fileHandle.compatSynchronize()
        fileHandle.compatClose()
    }
}
