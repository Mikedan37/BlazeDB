//  DraggableBlockView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct DraggableBlockView: View {
    let block: Block

    var body: some View {
        Text(block.title)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(4)
            .onDrag {
                NSItemProvider(object: NSString(string: block.title))
            }
    }
}
