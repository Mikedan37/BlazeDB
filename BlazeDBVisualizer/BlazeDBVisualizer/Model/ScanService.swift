//  ScanService.swift
//  BlazeDBVisualizer
//  Created by Michael Danylchuk on 6/29/25.
import Foundation

struct DBFileGroup: Identifiable, Hashable {
    let id = UUID()
    let app: String
    let component: String
    let files: [URL]
}

enum ScanService {
    static func scanAllBlazeDBs() -> [DBFileGroup] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        var results: [String: [String: Set<URL>]] = [:] // Use Set to dedupe
        
        // Recursively scan from the home directory
        let enumerator = fileManager.enumerator(
            at: homeDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "blaze" || fileURL.pathExtension == "meta" else { continue }
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let comps = baseName.components(separatedBy: ".")
            let app = comps.first ?? "Unknown"
            let component = comps.count > 1 ? comps[1] : "Main"
            
            results[app, default: [:]][component, default: Set()].insert(fileURL)
        }
        
        // Flatten for UI, sort files for prettiness
        var groups: [DBFileGroup] = []
        for (app, components) in results {
            for (component, files) in components {
                let sortedFiles = Array(files).sorted { $0.lastPathComponent < $1.lastPathComponent }
                groups.append(DBFileGroup(app: app, component: component, files: sortedFiles))
            }
        }
        return groups.sorted { $0.app < $1.app }
    }
}

extension ScanService {
    static func groupFiles(urls: [URL]) -> [DBFileGroup] {
        var results: [String: [String: [URL]]] = [:]
        for fileURL in urls {
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let comps = baseName.components(separatedBy: ".")
            let app = comps.first ?? "Unknown"
            let component = comps.count > 1 ? comps[1] : "Main"
            if results[app] == nil { results[app] = [:] }
            if results[app]![component] == nil { results[app]![component] = [] }
            results[app]![component]?.append(fileURL)
        }
        var groups: [DBFileGroup] = []
        for (app, components) in results {
            for (component, files) in components {
                groups.append(DBFileGroup(app: app, component: component, files: files))
            }
        }
        return groups.sorted { $0.app < $1.app }
    }
}
