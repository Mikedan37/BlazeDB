//  ResizableTextField.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

/// A multi-line text field that expands vertically with input.
struct ResizableTextField: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    @State private var dynamicHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray)
                    .padding(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }

            TextEditor(text: $text)
                .frame(minHeight: max(dynamicHeight, minHeight))
                .background(GeometryReader { geometry in
                    Color.clear
                        .preference(key: ViewHeightKey.self, value: geometry.size.height)
                })
                .onPreferenceChange(ViewHeightKey.self) { height in
                    dynamicHeight = height
                }
        }
        .padding(4)
        .background(Color.secondary)
        .cornerRadius(8)
    }
}

private struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
