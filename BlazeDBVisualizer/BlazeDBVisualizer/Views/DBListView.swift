//  DBListView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI

struct DBListView: View {
    var records: [DBRecord]
    var onSelect: (DBRecord) -> Void
    
    @State private var hoveredRecord: UUID?

    var body: some View {
        if records.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.system(size: 40))
                    .foregroundColor(.gray.opacity(0.6))
                Text("No BlazeDB files found.")
                    .foregroundColor(.gray.opacity(0.7))
                    .font(.title3)
                    .bold()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Button(action: { 
                            withAnimation(BlazeAnimation.quick) {
                                onSelect(record)
                            }
                        }) {
                            HStack(spacing: 12) {
                                // Icon with health indicator
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: record.isEncrypted ? "lock.shield.fill" : "archivebox")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.orange.gradient)
                                    
                                    // Health status badge
                                    Circle()
                                        .fill(healthColor(record.healthStatus))
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.5)
                                        )
                                        .offset(x: 3, y: -3)
                                }
                                .frame(width: 36, height: 36)
                                
                                // Database info
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(record.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        if record.needsMaintenance {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    
                                    Text(record.appName)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 8) {
                                        Label("\(record.recordCount)", systemImage: "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray)
                                        
                                        Label(record.sizeFormatted, systemImage: "chart.bar")
                                            .font(.system(size: 11))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                Spacer(minLength: 8)
                                
                                // Health status badge
                                VStack(spacing: 3) {
                                    Image(systemName: healthIcon(record.healthStatus))
                                        .font(.system(size: 16))
                                        .foregroundColor(healthColor(record.healthStatus))
                                    Text(record.healthStatus)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(healthColor(record.healthStatus))
                                        .textCase(.uppercase)
                                }
                                .frame(width: 60)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(height: 85)  // Fixed height for uniformity!
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(hoveredRecord == record.id ? 0.15 : 0.08))
                            )
                            .scaleEffect(hoveredRecord == record.id ? 1.02 : 1.0)
                            .shadow(
                                color: healthColor(record.healthStatus).opacity(hoveredRecord == record.id ? 0.3 : 0),
                                radius: hoveredRecord == record.id ? 8 : 0,
                                y: hoveredRecord == record.id ? 4 : 0
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            withAnimation(BlazeAnimation.quick) {
                                hoveredRecord = hovering ? record.id : nil
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity).animation(BlazeAnimation.smooth.delay(BlazeAnimation.staggerDelay(index: index))),
                            removal: .opacity.animation(BlazeAnimation.quick)
                        ))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .animation(.default, value: records.count)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
    }
    
    // MARK: - Helper Functions
    
    private func healthColor(_ status: String) -> Color {
        switch status {
        case "healthy": return .green
        case "ready": return .green
        case "active": return .blue
        case "empty": return .gray
        case "large": return .purple
        case "warning": return .orange
        case "critical": return .red
        case "unknown": return .gray
        default: return .gray
        }
    }
    
    private func healthIcon(_ status: String) -> String {
        switch status {
        case "healthy": return "checkmark.circle.fill"
        case "ready": return "checkmark.circle.fill"
        case "active": return "bolt.circle.fill"
        case "empty": return "circle"
        case "large": return "database.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "critical": return "xmark.octagon.fill"
        case "unknown": return "questionmark.circle"
        default: return "questionmark.circle"
        }
    }
}
