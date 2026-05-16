//
//  CLIPickerModels.swift
//  BlazeCLICore
//

import Foundation

public enum PickerSection: Equatable, Sendable {
    case recent
    case found
}

public struct PickerRow: Equatable, Sendable {
    public var url: URL
    public var section: PickerSection
    public var isRecent: Bool
    public var isBookmarked: Bool
    /// Shown on every row until unlocked this process (plan).
    public var isLocked: Bool
    public var subtitle: String
    public var sizeLabel: String
    public var modifiedLabel: String
    public var createdAt: Date?

    public init(
        url: URL,
        section: PickerSection,
        isRecent: Bool,
        isBookmarked: Bool,
        isLocked: Bool,
        subtitle: String,
        sizeLabel: String,
        modifiedLabel: String,
        createdAt: Date? = nil
    ) {
        self.url = url
        self.section = section
        self.isRecent = isRecent
        self.isBookmarked = isBookmarked
        self.isLocked = isLocked
        self.subtitle = subtitle
        self.sizeLabel = sizeLabel
        self.modifiedLabel = modifiedLabel
        self.createdAt = createdAt
    }

    public var titleLine: String {
        let name = url.lastPathComponent
        var chips: [String] = []
        if isRecent { chips.append("[recent]") }
        if isBookmarked { chips.append("[bookmarked]") }
        if isLocked { chips.append("[locked]") }
        let chipStr = chips.isEmpty ? "" : " " + chips.joined(separator: " ")
        return name + chipStr
    }
}

public enum PickerLine: Equatable, Sendable {
    case header(String)
    case row(PickerRow)
}

public struct PickerQuery: Sendable, Equatable {
    public var filterText: String
    public var bookmarkedOnly: Bool
    /// Hide backup shards, daemon/CLI test DBs (recommended default).
    public var hideNoiseFiles: Bool
    public var page: Int
    public var pageSize: Int

    public init(
        filterText: String = "",
        bookmarkedOnly: Bool = false,
        hideNoiseFiles: Bool = true,
        page: Int = 0,
        pageSize: Int = CLIPickerRender.pageSize
    ) {
        self.filterText = filterText
        self.bookmarkedOnly = bookmarkedOnly
        self.hideNoiseFiles = hideNoiseFiles
        self.page = page
        self.pageSize = pageSize
    }
}

public enum CLIDatabaseFilter {
    public static func isNoiseFileName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.hasPrefix("backup_v0_") { return true }
        if n.hasPrefix("daemontest-") { return true }
        if n.hasPrefix("clitest-") { return true }
        return false
    }
}

public struct PickerPageInfo: Sendable, Equatable {
    public var page: Int
    public var pageCount: Int
    public var total: Int
    public var rangeStart: Int
    public var rangeEnd: Int
}

public struct PickerSnapshot: Sendable {
    public var lines: [PickerLine]
    public var selectableIndices: [Int]
    public var scanStatus: String?
    public var pageInfo: PickerPageInfo

    public init(
        lines: [PickerLine],
        selectableIndices: [Int],
        scanStatus: String? = nil,
        pageInfo: PickerPageInfo
    ) {
        self.lines = lines
        self.selectableIndices = selectableIndices
        self.scanStatus = scanStatus
        self.pageInfo = pageInfo
    }
}

public enum CLIMetadata {
    public static func sizeLabel(for url: URL) -> String {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let n = try? url.resourceValues(forKeys: keys).fileSize else { return "—" }
        return CLIRelativeTime.formatByteCount(Int64(n))
    }

    public static func modifiedLabel(for url: URL) -> String {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let d = try? url.resourceValues(forKeys: keys).contentModificationDate else { return "—" }
        return CLIRelativeTime.describe(since: d)
    }

    public static func creationDate(for url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        guard let vals = try? url.resourceValues(forKeys: keys) else { return nil }
        return vals.creationDate ?? vals.contentModificationDate
    }

    public static func createdLabel(for url: URL) -> String {
        guard let d = creationDate(for: url) else { return "—" }
        return CLIRelativeTime.describe(since: d)
    }

    public static func subtitle(for url: URL) -> String {
        "\(sizeLabel(for: url)) • modified \(modifiedLabel(for: url))"
    }
}
