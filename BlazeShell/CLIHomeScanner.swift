//
//  CLIHomeScanner.swift
//  BlazeCLICore
//

import Foundation

public struct CLIHomeScannerConfig: Sendable {
    public var maxHits: Int
    public var timeBudget: TimeInterval
    public var excludedDirectoryNames: Set<String>

    public init(
        maxHits: Int = 500,
        timeBudget: TimeInterval = 60,
        excludedDirectoryNames: Set<String> = CLIHomeScannerConfig.defaultExcludedDirectoryNames
    ) {
        self.maxHits = maxHits
        self.timeBudget = timeBudget
        self.excludedDirectoryNames = excludedDirectoryNames
    }

    public static let defaultExcludedDirectoryNames: Set<String> = [
        "node_modules", ".git", "DerivedData", "Pods", ".build", "Carthage",
        ".gradle", ".conda", ".venv", "venv", "__pypackages__", ".nox", ".tox",
        "Trash", ".Trash", "Caches", "build", "dist", ".cache"
    ]
}

/// Depth-first style enumeration with pruning; invokes `onHit` on a caller queue in small batches.
public enum CLIHomeScanner {
    public static func scan(
        home: URL,
        config: CLIHomeScannerConfig = CLIHomeScannerConfig(),
        onHit: @escaping @Sendable (URL) -> Void,
        completion: @escaping @Sendable () -> Void
    ) {
        let work = DispatchQueue(label: "com.blazedb.cli.homescan", qos: .userInitiated)
        work.async {
            let start = Date()
            var hits = 0
            var dirStack: [URL] = [home]
            let fm = FileManager.default
            let homePath = home.path

            outer: while let dir = dirStack.popLast() {
                if Date().timeIntervalSince(start) > config.timeBudget { break }
                if hits >= config.maxHits { break }

                let children: [URL]
                do {
                    children = try fm.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )
                } catch {
                    continue
                }

                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if Date().timeIntervalSince(start) > config.timeBudget { break outer }
                    if hits >= config.maxHits { break outer }

                    let name = child.lastPathComponent
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: child.path, isDirectory: &isDir) else { continue }

                    if isDir.boolValue {
                        if shouldSkipDirectory(url: child, name: name, homePath: homePath, excluded: config.excludedDirectoryNames) {
                            continue
                        }
                        dirStack.append(child)
                        continue
                    }

                    if child.pathExtension.lowercased() == "blazedb" {
                        // Skip auto-backup shards — they flood the picker and slow scans.
                        if name.hasPrefix("backup_v0_") { continue }
                        onHit(child)
                        hits += 1
                    }
                }
            }
            completion()
        }
    }

    static func shouldSkipDirectory(url: URL, name: String, homePath: String, excluded: Set<String>) -> Bool {
        if excluded.contains(name) { return true }
        let p = url.path
        if p.contains("/Library/Caches/") { return true }
        if p.hasSuffix("/Library/Caches") { return true }
        if p.contains("/.Trash/") || p.hasSuffix("/.Trash") { return true }
        if p.contains("/Trash/") && p.hasPrefix(homePath) { return true }
        return false
    }
}
