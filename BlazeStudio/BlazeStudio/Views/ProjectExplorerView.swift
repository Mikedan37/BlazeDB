//  ProjectExplorerView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct ProjectExplorerView: View {
    @State private var projectName: String = "Untitled Project"
    @State private var blocks: [Block] = []
    @State private var selectedBlock: Block? = nil
    @State private var wireStartBlockID: UUID? = nil

    var body: some View {
        List {
            Section(header: Text("Project")) {
                TextField("Project Name", text: $projectName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            Section(header: Text("Block Templates")) {
                DisclosureGroup("Add Block") {
                    Text("Block")
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(6)
                        .onDrag {
                            let provider = NSItemProvider(object: "Block" as NSString)
                            provider.suggestedName = "Block"
                            return provider
                        }

                    Text("Wire")
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                        .onDrag {
                            let provider = NSItemProvider(object: "Wire" as NSString)
                            provider.suggestedName = "Wire"
                            return provider
                        }
                }
            }

            Section(header: Text("Views")) {
                NavigationLink("Canvas View") {
                    CanvasView(selectedBlock: $selectedBlock, blocks: $blocks, wireStartBlockID: $wireStartBlockID)
                }
                NavigationLink("AI Toolbar View") {
                    AIToolbarView()
                }
                NavigationLink("Introspector Panel") {
                    IntrospectorPanel(selectedBlock: .constant(nil))
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
}

#Preview {
    ProjectExplorerView()
}
