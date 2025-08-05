//  BlockHandleView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct BlockHandleView: View {
    var action: (() -> Void)? = nil

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 1)
            .onTapGesture {
                action?()
            }
            .accessibility(label: Text("Block Connector Handle"))
    }
}

struct BlockHandleView_Previews: PreviewProvider {
    static var previews: some View {
        BlockHandleView()
            .padding()
            .previewLayout(.sizeThatFits)
            .background(Color.black.opacity(0.1))
    }
}
