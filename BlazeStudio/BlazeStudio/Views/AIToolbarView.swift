//  AIToolbarView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct AIToolbarView: View {
    var body: some View {
        HStack {
            Button(action: {
                AIActions.shared.generateProjectMap()
            }) {
                Label("Map Project", systemImage: "map")
            }

            Button(action: {
                AIActions.shared.regenerateCode()
            }) {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
            }

            Button(action: {
                AIActions.shared.summarizeCurrentFile()
            }) {
                Label("Summarize", systemImage: "doc.text.magnifyingglass")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
    }
}

struct AIToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        AIToolbarView()
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
