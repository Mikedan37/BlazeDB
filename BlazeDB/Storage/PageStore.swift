//  PageStore.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
// import CryptoKit

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
    
    public func deletePage(index: Int) throws {
        try queue.sync(flags: .barrier) {
            let offset = UInt64(index * pageSize)
            try fileHandle.seek(toOffset: offset)
            let zeroed = Data(repeating: 0, count: pageSize)
            try fileHandle.write(contentsOf: zeroed)
        }
    }
    
    public func writePage(index: Int, plaintext: Data) throws {
        try queue.sync(flags: .barrier) {
            print("💾 Writing plaintext page at index \(index) with size \(plaintext.count)")
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
            try fileHandle.seek(toOffset: offset)
            try fileHandle.write(contentsOf: buffer)
        }
    }

    public func readPage(index: Int) throws -> Data {
        return try queue.sync {
            let offset = UInt64(index * pageSize)
            try fileHandle.seek(toOffset: offset)
            let data = try fileHandle.read(upToCount: pageSize) ?? Data()

            print("📖 Reading plaintext page at index \(index)")
            print("📏 Data size: \(data.count)")

            guard data.count > 5 else {
                throw NSError(domain: "PageStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid page size"])
            }

            guard data.starts(with: "BZDB".data(using: .utf8)!) else {
                throw NSError(domain: "PageStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid or missing page header"])
            }

            let plaintext = data.advanced(by: 5)
            return plaintext
        }
    }

    // Returns (totalPages, orphanedPages, estimatedSize)
    public func getStorageStats() throws -> (totalPages: Int, orphanedPages: Int, estimatedSize: Int) {
        return try queue.sync {
            // Get file size
            let fileSize = try FileManager.default.attributesOfItem(atPath: fileHandle.availableData.base64EncodedString()).reduce(0) { $0 + (($1.value as? Int) ?? 0) }
            let totalPages = Int(fileSize / pageSize)

            var orphanedPages = 0
            let expectedHeader = "BZDB".data(using: .utf8)! + [0x01]
            for i in 0..<totalPages {
                try fileHandle.seek(toOffset: UInt64(i * pageSize))
                let header = try fileHandle.read(upToCount: 5) ?? Data()
                if header != expectedHeader {
                    orphanedPages += 1
                }
            }

            return (totalPages, orphanedPages, fileSize)
        }
    }

    deinit {
        try? fileHandle.close()
    }
}
