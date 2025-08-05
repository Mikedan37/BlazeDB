//  Block.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

struct Block: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var type: BlockType
    var description: String
    var localVariables: [Variable] = []
    var linkedBlockIDs: [UUID] = []
    
    var aiContext: String = ""
    var codePreview: String = ""
    var position: CGPoint? = nil
    
    var subgraph: BlockGraph? = nil
}
