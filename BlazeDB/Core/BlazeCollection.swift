//  BlazeCollection.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import CryptoKit

public final class BlazeCollection<Record: BlazeRecord> {
    private var indexMap: [UUID: Int] = [:] // maps record ID to page index
    private let store: PageStore
    private var nextPageIndex: Int = 0
    private let metaURL: URL
    private let key: SymmetricKey
    private let queue = DispatchQueue(label: "com.yourorg.blazedb.collection", attributes: .concurrent)

    init(store: PageStore, metaURL: URL, key: SymmetricKey) throws {
        self.store = store
        self.metaURL = metaURL
        self.key = key

        if FileManager.default.fileExists(atPath: metaURL.path) {
            let layout = try StorageLayout.load(from: metaURL)
            self.indexMap = layout.indexMap
            self.nextPageIndex = layout.nextPageIndex
        }
    }

    func insert(_ record: Record) throws {
        try queue.sync(flags: .barrier) {
            let encoded = try JSONCoder.encode(record)
            try store.writePage(index: nextPageIndex, plaintext: encoded)
            indexMap[record.id] = nextPageIndex
            nextPageIndex += 1
            try saveLayout()
        }
    }
    
    func insertMany(_ records: [Record]) throws {
        try queue.sync(flags: .barrier) {
            for record in records {
                let encoded = try JSONCoder.encode(record)
                try store.writePage(index: nextPageIndex, plaintext: encoded)
                indexMap[record.id] = nextPageIndex
                nextPageIndex += 1
            }
            try saveLayout()
        }
    }
    
    func fetch(matching filter: (Record) -> Bool) throws -> [Record] {
        try queue.sync {
            return try fetchAll().filter(filter)
        }
    }
    func fetch(id: UUID) throws -> Record? {
        try queue.sync {
            guard let index = indexMap[id] else { return nil }
            let data = try store.readPage(index: index)
            if data.allSatisfy({ $0 == 0 }) || data.isEmpty { return nil }
            let trimmed = data.prefix { $0 != 0 }
            guard !trimmed.isEmpty else { return nil }
            return try JSONCoder.decode(Data(trimmed), as: Record.self)
        }
    }

    func fetchAll() throws -> [Record] {
        try queue.sync {
            return try indexMap
                .sorted(by: { $0.value < $1.value })
                .compactMap { (_, index) in
                    let data = try store.readPage(index: index)
                    guard !data.isEmpty && !isDataAllZero(data) else { return nil } // Don't decode empty or all-zero data!
                    let trimmed = data.prefix { $0 != 0 }
                    guard !trimmed.isEmpty else { return nil }
                    return try JSONCoder.decode(Data(trimmed), as: Record.self)
                }
        }
    }
    
    func delete(id: UUID) throws {
        try queue.sync(flags: .barrier) {
            guard let index = indexMap[id] else { return }
            try store.writePage(index: index, plaintext: Data())
            indexMap.removeValue(forKey: id)
            try saveLayout()
        }
    }
    
    func update(id: UUID, with newRecord: Record) throws {
        try queue.sync(flags: .barrier) {
            guard let index = indexMap[id] else {
                throw NSError(domain: "BlazeCollection", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Record not found"
                ])
            }
            let encoded = try JSONCoder.encode(newRecord)
            try store.writePage(index: index, plaintext: encoded)
            try saveLayout()
        }
    }
    
    private func saveLayout() throws {
        let layout = StorageLayout(
            indexMap: indexMap,
            nextPageIndex: nextPageIndex,
            secondaryIndexes: [:]
        )
        try layout.save(to: metaURL)
    }
    
    private func isDataAllZero(_ data: Data) -> Bool {
        for byte in data {
            if byte != 0 {
                return false
            }
        }
        return true
    }
}
