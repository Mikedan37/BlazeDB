//
//  CLIDiscovery.swift
//  BlazeCLICore
//

import Foundation
import BlazeDBCore

public enum CLIDiscovery {
    public static let defaultPageSize = CLIPickerRender.pageSize

    /// Non-recursive `*.blazedb` under PathResolver default directory.
    public static func fastFoundURLs() throws -> [URL] {
        let dir = try PathResolver.defaultDatabaseDirectory()
        return try listBlazedbFiles(in: dir)
    }

    public static func listBlazedbFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { $0.pathExtension.lowercased() == "blazedb" }
    }

    public static func normalizePath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Build Found URLs excluding any path already in `recentPaths` (normalized).
    public static func foundSectionURLs(
        registry: CLIRegistry,
        extraFromScan: [URL] = []
    ) throws -> [URL] {
        mergeFoundDistinct(try fastFoundURLs(), extraFromScan, registry: registry)
    }

    /// Merges fast + scan hits, excluding any path already listed as a recent.
    internal static func mergeFoundDistinct(
        _ fast: [URL],
        _ extras: [URL],
        registry: CLIRegistry
    ) -> [URL] {
        var seen = Set<String>()
        for p in registry.recents.map(\.path) {
            seen.insert(normalizePath(p))
        }
        var out: [URL] = []
        for u in fast + extras {
            let n = normalizePath(u.path)
            if seen.insert(n).inserted {
                out.append(u)
            }
        }
        return out
    }

    /// All unique database URLs (recents + default folder + scan extras).
    public static func allDatabaseURLs(
        registry: CLIRegistry,
        scanExtras: [URL]
    ) throws -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for entry in registry.recents {
            let n = normalizePath(entry.path)
            if seen.insert(n).inserted {
                urls.append(URL(fileURLWithPath: entry.path))
            }
        }
        let fast = try fastFoundURLs()
        for u in fast + scanExtras {
            let n = normalizePath(u.path)
            if seen.insert(n).inserted {
                urls.append(u)
            }
        }
        return urls
    }

    public static func sortByNewestFirst(_ urls: [URL]) -> [URL] {
        urls.sorted { a, b in
            let da = CLIMetadata.creationDate(for: a) ?? .distantPast
            let db = CLIMetadata.creationDate(for: b) ?? .distantPast
            if da != db { return da > db }
            return a.path < b.path
        }
    }

    public static func applyFilters(
        urls: [URL],
        registry: CLIRegistry,
        query: PickerQuery
    ) -> [URL] {
        let bookmarkSet = Set(registry.bookmarks.map { normalizePath($0) })
        let needle = query.filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return urls.filter { url in
            let norm = normalizePath(url.path)
            if query.hideNoiseFiles && CLIDatabaseFilter.isNoiseFileName(url.lastPathComponent) {
                return false
            }
            if query.bookmarkedOnly && !bookmarkSet.contains(norm) { return false }
            if needle.isEmpty { return true }
            return url.lastPathComponent.lowercased().contains(needle)
                || url.path.lowercased().contains(needle)
        }
    }

    public static func pageSlice(
        _ urls: [URL],
        query: PickerQuery
    ) -> (slice: [URL], info: PickerPageInfo) {
        let total = urls.count
        let pageSize = max(1, query.pageSize)
        let pageCount = max(1, (total + pageSize - 1) / pageSize)
        let page = min(max(0, query.page), pageCount - 1)
        let start = page * pageSize
        let end = min(start + pageSize, total)
        let slice = start < end ? Array(urls[start..<end]) : []
        let info = PickerPageInfo(
            page: page,
            pageCount: pageCount,
            total: total,
            rangeStart: total == 0 ? 0 : start + 1,
            rangeEnd: end
        )
        return (slice, info)
    }

    public static func buildPickerSnapshot(
        registry: CLIRegistry,
        scanExtras: [URL],
        scanStatus: String?,
        query: PickerQuery
    ) throws -> PickerSnapshot {
        let bookmarkSet = Set(registry.bookmarks.map { normalizePath($0) })
        let recentSet = Set(registry.recents.map { normalizePath($0.path) })

        let all = sortByNewestFirst(try allDatabaseURLs(registry: registry, scanExtras: scanExtras))
        let filtered = applyFilters(urls: all, registry: registry, query: query)
        let (pageURLs, pageInfo) = pageSlice(filtered, query: query)

        var lines: [PickerLine] = []
        var selectable: [Int] = []

        if pageInfo.total == 0 {
            let filterNote = query.filterText.isEmpty ? "" : " (filter: \"\(query.filterText)\")"
            let bmNote = query.bookmarkedOnly ? " · bookmarked only" : ""
            lines.append(.header("No databases match\(filterNote)\(bmNote)"))
            lines.append(.header("Press s to scan · / to filter · b bookmarks toggle"))
        } else {
            for url in pageURLs {
                let norm = normalizePath(url.path)
                let row = PickerRow(
                    url: url,
                    section: recentSet.contains(norm) ? .recent : .found,
                    isRecent: recentSet.contains(norm),
                    isBookmarked: bookmarkSet.contains(norm),
                    isLocked: true,
                    subtitle: CLIMetadata.subtitle(for: url),
                    sizeLabel: CLIMetadata.sizeLabel(for: url),
                    modifiedLabel: CLIMetadata.createdLabel(for: url),
                    createdAt: CLIMetadata.creationDate(for: url)
                )
                selectable.append(lines.count)
                lines.append(.row(row))
            }
        }

        return PickerSnapshot(
            lines: lines,
            selectableIndices: selectable,
            scanStatus: scanStatus,
            pageInfo: pageInfo
        )
    }
}
