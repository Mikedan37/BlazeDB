//  DBRowView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI

struct DBRowView: View {
    let db: DBRecord
    let onSelect: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: 16) {
                ZStack {
                    // Glow background for icon if encrypted
                    if db.isEncrypted {
                        Circle()
                            .fill(LinearGradient(colors: [Color.orange.opacity(0.65), .pink.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .blur(radius: isHovering ? 0 : 1.5)
                            .shadow(color: .pink.opacity(0.15), radius: 6, x: 0, y: 2)
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.11))
                            .frame(width: 36, height: 36)
                    }
                    Image(systemName: db.isEncrypted ? "lock.shield.fill" : "archivebox.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(db.isEncrypted ? Color.orange : Color.accentColor)
                        .shadow(color: .black.opacity(0.09), radius: 1, x: 0, y: 1)
                }
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.spring(duration: 0.3), value: isHovering)

                VStack(alignment: .leading, spacing: 2) {
                    Text(db.appName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(db.path)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.gray.opacity(0.7))
                        Text(Self.formatBytes(db.sizeInBytes))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(db.modifiedDate, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.gray)
                }
                if db.isEncrypted {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                        .padding(.leading, 6)
                        .shadow(color: .orange.opacity(0.23), radius: 1, x: 0, y: 1)
                        .transition(.scale)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovering ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.85))
                    .shadow(color: isHovering ? Color.orange.opacity(0.12) : .clear, radius: isHovering ? 8 : 1, x: 0, y: isHovering ? 5 : 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .onHover { hover in
            isHovering = hover
        }
    }

    static func formatBytes(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
