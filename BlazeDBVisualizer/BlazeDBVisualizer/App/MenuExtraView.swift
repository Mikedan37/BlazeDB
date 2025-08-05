//  MenuExtraView.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import SwiftUI
import BlazeDB

struct MenuExtraView: View {
    @State private var dbGroups: [DBFileGroup] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.red, .orange)
                    .symbolRenderingMode(.palette)
                    .font(.title3)
                Text("BlazeDB Visualizer")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }

            let totalDBs = dbGroups.reduce(0) { $0 + $1.files.filter { $0.pathExtension == "blaze" }.count }
            Text("Total Databases: \(totalDBs)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            if dbGroups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No BlazeDB files found.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(dbGroups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(group.app.capitalized)")
                                        .font(.headline)
                                    Text(group.component.capitalized)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(group.files, id: \.self) { file in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(file.lastPathComponent)
                                                .font(.callout)
                                                .bold()
                                            Text(file.path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if file.pathExtension == "blaze" {
                                            Text(ByteCountFormatter.string(fromByteCount: (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 ?? 0) ?? 0, countStyle: .file))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Button("Reveal") {
                                            NSWorkspace.shared.activateFileViewerSelecting([file])
                                        }
                                        .buttonStyle(.borderedProminent)
                                        Button("Delete", role: .destructive) {
                                            try? FileManager.default.removeItem(at: file)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(6)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding()
        .padding(.horizontal)
        .frame(width: 400, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onAppear {
            print("🔎 Scanning with terminal find…")
            findBlazeFilesAsync { urls in
                print("🔥 Found files: \(urls)")
                // Optional: Group by app/component like before
                let groups = ScanService.groupFiles(urls: urls)
                dbGroups = groups
            }
        }
    }
}
