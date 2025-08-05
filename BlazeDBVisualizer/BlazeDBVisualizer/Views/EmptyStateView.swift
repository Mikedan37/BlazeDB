//  EmptyStateView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            // Cute little flame
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 84, height: 84)
                Image(systemName: "flame.fill")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.red, Color.pink.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.12), radius: 8, y: 4)
            }
            Text("No BlazeDB Databases Found")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("There are no databases to show yet. Once an app using BlazeDB stores data, you’ll see it here.\n\nTry launching AshPile or another app that uses BlazeDB, then come back!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .padding(.vertical, 42)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView()
}
