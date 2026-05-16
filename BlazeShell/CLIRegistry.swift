//
//  CLIRegistry.swift
//  BlazeCLICore
//

import Foundation

public struct CLIRegistryRecentEntry: Codable, Equatable, Sendable {
    public var path: String
    public var lastOpenedAt: Date

    public init(path: String, lastOpenedAt: Date = .init()) {
        self.path = path
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct CLIRegistry: Codable, Equatable, Sendable {
    public static let maxRecents = 15

    public var recents: [CLIRegistryRecentEntry]
    public var bookmarks: [String]

    public init(recents: [CLIRegistryRecentEntry] = [], bookmarks: [String] = []) {
        self.recents = recents
        self.bookmarks = bookmarks
    }

    public static func load(from url: URL) throws -> CLIRegistry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return CLIRegistry()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CLIRegistry.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// MRU: move path to front, cap list.
    public mutating func recordSuccessfulOpen(path: String) {
        let normalized = (path as NSString).standardizingPath
        recents.removeAll { ($0.path as NSString).standardizingPath == normalized }
        recents.insert(CLIRegistryRecentEntry(path: normalized), at: 0)
        if recents.count > Self.maxRecents {
            recents = Array(recents.prefix(Self.maxRecents))
        }
    }

    public mutating func addBookmark(path: String) {
        let normalized = (path as NSString).standardizingPath
        if !bookmarks.contains(where: { ($0 as NSString).standardizingPath == normalized }) {
            bookmarks.append(normalized)
        }
    }

    public mutating func removeBookmark(path: String) {
        let normalized = (path as NSString).standardizingPath
        bookmarks.removeAll { ($0 as NSString).standardizingPath == normalized }
    }
}
