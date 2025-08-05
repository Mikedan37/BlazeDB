//
//  ContentView.swift
//  BlazeStudio
//
//  Created by Michael Danylchuk on 7/5/25.
//

import SwiftUI

struct ContentView: View {
    @State private var blocks: [Block] = []
    @State private var selectedBlock: Block? = nil
    @State private var wireStartBlockID: UUID? = nil
    var body: some View {
        HStack(spacing: 0) {
            ProjectExplorerView()
                .frame(width: 250)

            CanvasView(selectedBlock: $selectedBlock, blocks: $blocks, wireStartBlockID: $wireStartBlockID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(BlockStore())
    }
}

#Preview {
    ContentView()
}
