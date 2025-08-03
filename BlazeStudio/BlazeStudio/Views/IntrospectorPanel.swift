//  IntrospectorPanel.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.
import SwiftUI

struct IntrospectorPanel: View {
    @Binding var selectedBlock: Block?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let block = selectedBlock {
                Text("🧱 \(block.title)").font(.headline)

                TextField("Block Title", text: Binding(
                    get: { block.title },
                    set: { selectedBlock?.title = $0 }
                ))
                TextField("Description", text: Binding(
                    get: { block.description },
                    set: { selectedBlock?.description = $0 }
                ))

                if case .logic(.function) = block.type {
                    Text("Function").font(.subheadline)
                    Text(block.codePreview)
                        .font(.system(.body, design: .monospaced))
                        .padding(.vertical, 4)
                }

                Divider()

                Button("🧠 Summarize") {
                    if let block = selectedBlock {
                        AIServices.shared.summarizeBlock(block) { _ in }
                    }
                }
                Button("✨ Regenerate") {
                    if let block = selectedBlock {
                        AIServices.shared.regenerateBlock(block) { _ in }
                    }
                }
                Button("🔎 Analyze Dependencies") {
                    if let block = selectedBlock {
                        AIServices.shared.analyzeProjectContext(block) { _ in }
                    }
                }
            } else {
                Text("No block selected")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
        .cornerRadius(12)
    }
}
