//  BlazeDBService.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.
import Foundation
import BlazeDB

final class BlazeDBService {
    private let client: BlazeDBClient

    init(fileURL: URL, password: String) throws {
        self.client = try BlazeDBClient(name: "blocks", fileURL: fileURL, password: password)
    }

    func fetchBlocks() throws -> [Block] {
        let records = try client.fetchAll()
        return records.compactMap { record in
            guard
                case let .string(idStr) = record.storage["id"],
                let id = UUID(uuidString: idStr),
                case let .string(title) = record.storage["title"],
                case let .string(typeRaw) = record.storage["type"],
                let type = BlockType.decode(from: typeRaw),
                case let .string(description) = record.storage["description"]
            else {
                return nil
            }

            return Block(id: id, title: title, type: type, description: description)
        }
    }

    func persistBlocks(_ blocks: [Block]) throws {
        for block in blocks {
            let record = BlazeDataRecord([
                "id": .string(block.id.uuidString),
                "title": .string(block.title),
                "type": .string(block.type.encode()),
                "description": .string(block.description)
            ])
            _ = try client.insert(record)
        }
    }

    func clearBlocks() throws {
        let records = try client.fetchAll()
        for record in records {
            if case let .string(idStr) = record.storage["id"], let id = UUID(uuidString: idStr) {
                try client.delete(id: id)
            }
        }
    }
}
