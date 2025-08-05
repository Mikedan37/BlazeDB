//  BlockGraph.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

struct BlockGraph: Codable, Equatable {
    var blocks: [Block] = []

    func block(with id: UUID) -> Block? {
        return blocks.first { $0.id == id }
    }

    func linkedBlocks(for block: Block) -> [Block] {
        return block.linkedBlockIDs.compactMap { id in
            self.block(with: id)
        }
    }

    mutating func connect(from: UUID, to: UUID) {
        guard let fromIndex = blocks.firstIndex(where: { $0.id == from }),
              !blocks[fromIndex].linkedBlockIDs.contains(to) else { return }
        blocks[fromIndex].linkedBlockIDs.append(to)
    }

    var connections: [UUID: [UUID]] {
        var map = [UUID: [UUID]]()
        for block in blocks {
            for linkedID in block.linkedBlockIDs {
                map[block.id, default: []].append(linkedID)
            }
        }
        return map
    }
}
