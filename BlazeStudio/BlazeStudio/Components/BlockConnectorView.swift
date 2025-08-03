//  BlockConnectorView.swift
//  BlazeStudio
//  Created by Michael Danylchuk on 7/5/25.

import SwiftUI

struct BlockConnectorView: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            let midX = (from.x + to.x) / 2
            path.move(to: from)
            path.addCurve(to: to,
                          control1: CGPoint(x: midX, y: from.y),
                          control2: CGPoint(x: midX, y: to.y))
        }
        .stroke(Color.accentColor, lineWidth: 2)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}
