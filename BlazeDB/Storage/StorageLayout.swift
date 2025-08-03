//  StorageLayout.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.

import Foundation
import CryptoKit

struct StorageLayout: Codable {
    var indexMap: [UUID: Int]
    var nextPageIndex: Int

    static func load(from url: URL) throws -> StorageLayout {
        let data = try Data(contentsOf: url)
        return try CBORCoder.decode(data, as: StorageLayout.self)
    }

    func save(to url: URL) throws {
        let data = try CBORCoder.encode(self)
        try data.write(to: url)
    }
    
    static func loadEncrypted(from url: URL, using key: SymmetricKey) throws -> StorageLayout {
        let encryptedData = try Data(contentsOf: url)
        let decrypted = try AESGCM.decrypt(encryptedData, using: key)
        return try CBORCoder.decode(decrypted, as: StorageLayout.self)
    }

    func saveEncrypted(to url: URL, using key: SymmetricKey) throws {
        let encoded = try CBORCoder.encode(self)
        let encrypted = try AESGCM.encrypt(encoded, using: key)
        try encrypted.write(to: url)
    }
}

enum AESGCM {
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined!
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
