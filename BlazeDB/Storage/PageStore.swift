//  PageStore.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit

private extension FileHandle {
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
}

public final class PageStore {
    public let fileURL: URL
    private let fileHandle: FileHandle
    // private let key: SymmetricKey
    private let pageSize = 4096
    private let queue = DispatchQueue(label: "com.yourorg.blazedb.pagestore", attributes: .concurrent)

    public init(fileURL: URL/*, key: SymmetricKey*/) throws {
        self.fileURL = fileURL
        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        // Ensure the key bit count is valid for AES-GCM (128, 192, or 256 bits)
        /*
        let bitCount = key.bitCount
        guard [128, 192, 256].contains(bitCount) else {
            throw NSError(domain: "PageStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid SymmetricKey bit count: \(bitCount). Expected 128, 192, or 256."
            ])
        }
        */

        self.fileHandle = try FileHandle(forUpdating: fileURL)
        // self.key = key
    }

    public convenience init(fileURL: URL, key: SymmetricKey) throws {
        // Encryption is not enabled yet; accept the key for API compatibility.
        try self.init(fileURL: fileURL)
    }
    
    public func deletePage(index: Int) throws {
        try queue.sync(flags: .barrier) {
            let offset = UInt64(index * pageSize)
            print("[PAGE-TRACE] 🗑️ Deleting page at index \(index), zeroing bytes at offset \(offset)")
            try fileHandle.compatSeek(toOffset: offset)
            let zeroed = Data(repeating: 0, count: pageSize)
            try fileHandle.compatWrite(zeroed)
            try fileHandle.compatSynchronize()
            print("[PAGE-TRACE] ✅ Page \(index) deleted (zeroed)")
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
        return try queue.sync(flags: .barrier) {
            // Determine next page index from current file size.
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let nextIndex = max(0, fileSize / pageSize)
            print("[PAGE-TRACE] 💾 Appending plaintext page at index \(nextIndex) with size \(data.count)")
            try _writePageLocked(index: nextIndex, plaintext: data)
            return nextIndex
        }
    }

    /// Unlabeled read overload for convenience.
    public func read(_ index: Int) throws -> Data? {
        return try read(index: index)
    }

    // Performs a write assuming the caller already holds the barrier on `queue`
    private func _writePageLocked(index: Int, plaintext: Data) throws {
        if plaintext.isEmpty {
            print("[PAGE-TRACE] ⚙️ Writing header-only zero-length page at index \(index)")
            // Write only header + padding to pageSize
            var buffer = Data()
            buffer.append("BZDB".data(using: .utf8)!) // 4 bytes
            buffer.append(0x01)                       // version
            // no payload
            if buffer.count < pageSize {
                buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
            }
            let offset = UInt64(index * pageSize)
            print("[PAGE-TRACE] 🔢 Writing at byte offset \(offset) (header-only buffer size \(buffer.count))")
            try fileHandle.compatSeek(toOffset: offset)
            try fileHandle.compatWrite(buffer)
            try fileHandle.compatSynchronize()
            print("[PAGE-TRACE] ✅ Header-only page \(index) flushed to disk")
            return
        }
        print("[PAGE-TRACE] 💾 Writing plaintext page at index \(index) with size \(plaintext.count)")
        guard plaintext.count + 5 <= pageSize else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Page too large"])
        }

        var buffer = Data()
        buffer.append("BZDB".data(using: .utf8)!) // 4 bytes
        buffer.append(0x01)                       // version
        buffer.append(plaintext)

        // Pad with zeros if buffer is smaller than pageSize
        if buffer.count < pageSize {
            buffer.append(Data(repeating: 0, count: pageSize - buffer.count))
        }

        let offset = UInt64(index * pageSize)
        print("[PAGE-TRACE] 🔢 Writing at byte offset \(offset) (buffer size \(buffer.count))")
        try fileHandle.compatSeek(toOffset: offset)
        try fileHandle.compatWrite(buffer)
        try fileHandle.compatSynchronize()
        print("[PAGE-TRACE] ✅ Page \(index) flushed to disk")
    }

    public func writePage(index: Int, plaintext: Data) throws {
        try queue.sync(flags: .barrier) {
            try _writePageLocked(index: index, plaintext: plaintext)
        }
    }

    // MARK: - Back-compatibility shim for tests
    @inlinable
    public func writePage(index: Int, data: Data) throws {
        try writePage(index: index, plaintext: data)
    }

    public func readPage(index: Int) throws -> Data? {
        return try queue.sync {
            let offset = UInt64(index * pageSize)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[PAGE-TRACE] ⚠️ File missing during read(page \(index)) — returning nil")
                return nil
            }
            // Check file size before seeking
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSizeNum = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if offset >= fileSizeNum {
                print("[PAGE-TRACE] ⚠️ Offset out of range for page \(index) — returning nil")
                return nil
            }
            try fileHandle.compatSeek(toOffset: offset)
            var page = try fileHandle.compatRead(upToCount: pageSize)
            if page.count < pageSize {
                let padding = Data(repeating: 0, count: pageSize - page.count)
                page.append(padding)
            }

            if page.allSatisfy({ $0 == 0 }) {
                print("[PAGE-TRACE] ⚠️ Page \(index) empty after delete/rollback — returning nil")
                return nil
            }

            guard page.count >= 5 else {
                print("[PAGE-TRACE] ❌ Throwing read error for page \(index) (too short for header)")
                throw NSError(domain: "PageStore", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty page at index \(index)"])
            }

            let isValidHeader = page[0] == 0x42 && page[1] == 0x5A && page[2] == 0x44 && page[3] == 0x42 && page[4] == 0x01
            if !isValidHeader {
                print("[PAGE-TRACE] ⚠️ Invalid header for page \(index) — returning nil")
                return nil
            }

            let payloadPadded = page.subdata(in: 5..<page.count)
            if let lastNonZero = payloadPadded.lastIndex(where: { $0 != 0 }) {
                let trimmed = payloadPadded.prefix(through: lastNonZero)
                print("[PAGE-TRACE] 📖 Read valid page \(index) with payload \(trimmed.count) bytes")
                return trimmed
            } else {
                print("[PAGE-TRACE] 📖 Read zero-length valid page \(index)")
                // For valid page header but zero-length data, still return Data()
                return Data()
            }
        }
    }

    // Returns (totalPages, orphanedPages, estimatedSize)
    public func getStorageStats() throws -> (totalPages: Int, orphanedPages: Int, estimatedSize: Int) {
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

    public func delete(index: Int) throws {
        try deletePage(index: index)
    }

    deinit {
        fileHandle.compatClose()
    }
}
