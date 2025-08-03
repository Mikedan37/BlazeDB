//  BlockStore.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.
import Foundation
import BlazeDB

final class BlockStore: ObservableObject, Identifiable {
    @Published var graph = BlockGraph()
    @Published var selectedBlockID: UUID?

    func load(from database: BlazeDBService) throws {
        let storedBlocks = try database.fetchBlocks()
        for block in storedBlocks {
            graph.blocks.append(block)
        }
    }

    func save(to database: BlazeDBService) throws {
        try database.persistBlocks(graph.blocks)
    }

    func reset() {
        graph.blocks.removeAll()
    }
    
    func deselectBlock() {
            selectedBlockID = nil
    }
}
