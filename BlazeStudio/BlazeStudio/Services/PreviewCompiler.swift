//  PreviewCompiler.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import Foundation

final class PreviewCompiler {
    func generatePreviewCode(from blocks: [Block]) -> String {
        var code = """
        import SwiftUI

        struct PreviewView: View {
            var body: some View {
        """

        for block in blocks {
            code += "\n                \(generateViewSnippet(for: block))"
        }

        code += """
        
            }
        }

        #Preview {
            PreviewView()
        }
        """

        return code
    }

    private func generateViewSnippet(for block: Block) -> String {
        switch block.type {
        case .structure(let type):
            switch type {
            case .connector:
                return "Spacer()"
            case .class:
                return "EmptyView()"
            }
        case .logic(let type):
            switch type {
            case .function:
                return "EmptyView()"
            case .variable:
                return "EmptyView()"
            case .constant:
                return "EmptyView()"
            case .condition:
                return "EmptyView()"
            case .loop:
                return "EmptyView()"
            }
        }
    }
}
