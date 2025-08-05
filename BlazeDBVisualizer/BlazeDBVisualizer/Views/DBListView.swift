//  DBListView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI

struct DBListView: View {
    var records: [DBRecord]
    var onSelect: (DBRecord) -> Void

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
                LazyVStack(spacing: 12) {
                    ForEach(records, id: \.id) { record in
                        Button(action: { onSelect(record) }) {
                            HStack(spacing: 14) {
                                Image(systemName: record.isEncrypted ? "lock.fill" : "archivebox")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(record.isEncrypted ? .red : .blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.appName)
                                        .font(.headline)
                                    Text(record.path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 8) {
                                        Text("\(record.sizeInBytes) bytes")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        Text(record.modifiedDate, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.7))
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
    }
}
