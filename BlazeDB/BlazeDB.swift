// BlazeDB.swift
import Foundation
import CryptoKit

public enum BlazeDBError: Error {
    case recordExists
    case recordNotFound
}

public final class BlazeDatabase {
    private let pageStore: PageStore

    public init(url: URL, key: SymmetricKey) throws {
        self.pageStore = try PageStore(fileURL: url, key: key)
    }

    public func beginTransaction() -> BlazeTransaction {
        return BlazeTransaction(store: pageStore)
    }
}

extension BlazeDatabase {
    public func insert<T: Codable>(_ record: T, forID id: String) throws {
        if try pageStore.read(forID: id) != nil {
            throw BlazeDBError.recordExists
        }
        let data = try JSONEncoder().encode(record)
        try pageStore.write(data: data, forID: id)
    }

    public func fetch<T: Codable>(forID id: String) throws -> T? {
        guard let data = try pageStore.read(forID: id) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func update<T: Codable>(_ record: T, forID id: String) throws {
        guard try pageStore.read(forID: id) != nil else {
            throw NSError(domain: "BlazeDatabase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Record not found"])
        }
        let data = try JSONEncoder().encode(record)
        try pageStore.write(data: data, forID: id)
    }

    public func delete(forID id: String) throws {
        try pageStore.delete(forID: id)
    }
}
