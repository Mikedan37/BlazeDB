//  AIContextBuilder.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

struct AIContextBuilder {
    static func buildContext(for block: Block, in graph: BlockGraph) -> String {
        let linked = graph.linkedBlocks(for: block)
        var context = "Block: \(block.title)\nType: \(block.type.displayName)\nDescription: \(block.description)\n\n"
        
        for variable in block.localVariables {
            context += "- Variable: \(variable.name): \(variable.type)"
            if let defaultValue = variable.defaultValue {
                context += " = \(defaultValue)"
            }
            if let description = variable.description {
                context += " // \(description)"
            }
            context += "\n"
        }

        context += "\nLinked Blocks:\n"
        for linkedBlock in linked {
            context += "• \(linkedBlock.type.displayName) \(linkedBlock.title)\n"
        }

        return context
    }
}
