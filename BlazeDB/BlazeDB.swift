// BlazeDB.swift
import Foundation
import CryptoKit

public final class BlazeDatabase {
    private let pageStore: PageStore

    public init(url: URL, key: SymmetricKey) throws {
        self.pageStore = try PageStore(fileURL: url, key: key)
    }

    public func beginTransaction() -> BlazeTransaction {
        return BlazeTransaction(store: pageStore)
    }
}
