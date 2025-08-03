//  PageStore.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
import CryptoKit

final class PageStore {
    private let fileHandle: FileHandle
    private let key: SymmetricKey
    private let pageSize = 4096

    init(fileURL: URL, key: SymmetricKey) throws {
        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        self.fileHandle = try FileHandle(forUpdating: fileURL)
        self.key = key
    }

    func writePage(index: Int, plaintext: Data) throws {
        guard plaintext.count < (pageSize - 32) else {
            throw NSError(domain: "PageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Page too large"])
        }

        let iv = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: iv)

        var buffer = Data()
        buffer.append("BZDB".data(using: .utf8)!) // 4 bytes
        buffer.append(0x01)                       // version
        buffer.append(contentsOf: iv)             // 12 bytes
        buffer.append(sealed.ciphertext)          // variable
        buffer.append(sealed.tag)                 // 16 bytes

        let offset = UInt64(index * pageSize)
        try fileHandle.seek(toOffset: offset)
        try fileHandle.write(contentsOf: buffer)
    }

    func readPage(index: Int) throws -> Data {
        let offset = UInt64(index * pageSize)
        try fileHandle.seek(toOffset: offset)
        let data = try fileHandle.read(upToCount: pageSize) ?? Data()

        guard data.count > 33 else {
            throw NSError(domain: "PageStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid page size"])
        }

        let iv = try AES.GCM.Nonce(data: data[5..<17])
        let ciphertext = data[17..<(data.count - 16)]
        let tag = data[(data.count - 16)...]

        let sealed = try AES.GCM.SealedBox(nonce: iv, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealed, using: key)
    }

    deinit {
        try? fileHandle.close()
    }
}
