//
//  CLIPickerRender.swift
//  BlazeCLICore
//

import Foundation

public enum CLIPickerRender {
    public static let pageSize = 10

    /// Visible character count, ignoring ANSI CSI/OSC escape sequences.
    /// Correctly parses CSI: `ESC [ <params 0x30..0x3F>* <intermediate 0x20..0x2F>* <final 0x40..0x7E>`.
    public static func visibleLength(_ text: String) -> Int {
        var count = 0
        let scalars = text.unicodeScalars
        var i = scalars.startIndex
        while i < scalars.endIndex {
            let s = scalars[i]
            if s != "\u{1B}" {
                count += 1
                i = scalars.index(after: i)
                continue
            }
            i = scalars.index(after: i)
            if i >= scalars.endIndex { break }
            let next = scalars[i]
            if next == "[" { // CSI
                i = scalars.index(after: i)
                while i < scalars.endIndex {
                    let c = scalars[i]
                    i = scalars.index(after: i)
                    if c.value >= 0x40 && c.value <= 0x7E { break }
                }
            } else if next == "]" { // OSC: terminated by BEL or ESC \\
                i = scalars.index(after: i)
                while i < scalars.endIndex {
                    let c = scalars[i]
                    i = scalars.index(after: i)
                    if c.value == 0x07 { break } // BEL
                    if c == "\u{1B}" {
                        if i < scalars.endIndex { i = scalars.index(after: i) }
                        break
                    }
                }
            } else {
                i = scalars.index(after: i)
            }
        }
        return count
    }

    /// Plain-text clip with ellipsis. Caller must pass plain text only.
    public static func clip(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        if text.count <= width { return text }
        if width == 1 { return "…" }
        return String(text.prefix(width - 1)) + "…"
    }

    /// Pad text to `width` visible columns. Safe with ANSI: if the visible
    /// width already meets or exceeds `width`, returns text unchanged (does
    /// not chop into escape sequences).
    public static func pad(_ text: String, width: Int, align: Align = .left) -> String {
        let visible = visibleLength(text)
        if visible >= width { return text }
        let extra = String(repeating: " ", count: width - visible)
        switch align {
        case .left: return text + extra
        case .right: return extra + text
        }
    }

    public enum Align { case left, right }

    public struct ColumnWidths {
        public var name: Int
        public var size: Int
        public var created: Int
        public var tags: Int
        public var path: Int
        public var total: Int

        public static func compute(for terminalWidth: Int) -> ColumnWidths {
            let total = max(70, min(140, terminalWidth))
            // Row layout: "  ▸ " (4) + name + " │ " (3) + size + " │ " (3) + created + " │ " (3) + path
            let inner = total - 4 // 4-char marker block
            let size = 8
            let created = 12
            let tags = 0 // hidden
            let dividerSpace = 9 // " │ " ×3
            let nameTarget = max(22, min(46, (inner - size - created - dividerSpace) * 5 / 11))
            let name = nameTarget
            let path = max(18, inner - name - size - created - dividerSpace)
            return ColumnWidths(name: name, size: size, created: created, tags: tags, path: path, total: total)
        }
    }

    public static func homeShortened(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        if path == home { return "~" }
        return path
    }

    /// Compact "important endpoints": the last 1-2 path components.
    public static func locationShort(_ raw: String) -> String {
        let url = URL(fileURLWithPath: raw)
        let file = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty || parent == "/" || parent == file { return file }
        return parent + "/" + file
    }

    public static func displayPath(_ raw: String, width: Int) -> String {
        let short = locationShort(raw)
        if short.count <= width { return short }
        if width <= 1 { return "…" }
        // Filename stays on the right; truncate the parent dir prefix if needed.
        return "…" + short.suffix(width - 1)
    }

    public static func tagsString(for row: PickerRow) -> String {
        // Hidden in the table view; kept for callers that still want a glyph.
        let recent = row.isRecent ? CLIColors.accent("●") : ""
        let book = row.isBookmarked ? CLIColors.flameYellow("★") : ""
        return recent + book
    }

    public struct FrameInput {
        public var snapshot: PickerSnapshot
        public var selection: Int
        public var filterText: String
        public var bookmarkedOnly: Bool
        public var filterDraft: String?
        public var isFilterMode: Bool
        public var terminalWidth: Int
        public var terminalRows: Int
        public var useCompactBanner: Bool

        public init(
            snapshot: PickerSnapshot,
            selection: Int,
            filterText: String = "",
            bookmarkedOnly: Bool = false,
            filterDraft: String? = nil,
            isFilterMode: Bool = false,
            terminalWidth: Int = 80,
            terminalRows: Int = 30,
            useCompactBanner: Bool = false
        ) {
            self.snapshot = snapshot
            self.selection = selection
            self.filterText = filterText
            self.bookmarkedOnly = bookmarkedOnly
            self.filterDraft = filterDraft
            self.isFilterMode = isFilterMode
            self.terminalWidth = terminalWidth
            self.terminalRows = terminalRows
            self.useCompactBanner = useCompactBanner
        }
    }

    /// Page size that fits the picker inside the current terminal.
    /// Reserves space for the banner, headers, status, hint and frame lines.
    public static func adaptivePageSize(rows: Int, compactBanner: Bool) -> Int {
        let bannerHeight = compactBanner ? 3 : 8 // 6 art rows + 2 bars vs 3
        // chrome non-data lines: blank + status + header + rule + hint + footer = 6
        let chrome = bannerHeight + 6
        let usable = rows - chrome
        if usable < 2 { return 2 }
        if usable > 12 { return 12 }
        return usable
    }

    public static func renderFrame(_ input: FrameInput) -> String {
        let cw = ColumnWidths.compute(for: input.terminalWidth)
        var lines: [String] = []

        let bannerLines = input.useCompactBanner
            ? CLIBranding.heroCompactLines(width: cw.total)
            : CLIBranding.heroBlockLines(width: cw.total)
        for line in bannerLines { lines.append(line) }
        lines.append("")

        // Single status line combining scan progress + page indicator + filter.
        let p = input.snapshot.pageInfo
        var statusBits: [String] = []
        if let s = input.snapshot.scanStatus, !s.isEmpty { statusBits.append(s) }
        if p.total > 0 {
            statusBits.append("page \(p.page + 1)/\(p.pageCount) · \(p.rangeStart)–\(p.rangeEnd) of \(p.total)")
        }
        if !input.filterText.isEmpty { statusBits.append("filter “\(input.filterText)”") }
        if input.bookmarkedOnly { statusBits.append("bookmarked only") }
        if !statusBits.isEmpty {
            lines.append("  " + CLIColors.muted(statusBits.joined(separator: "   ")))
        }

        let div = CLIColors.frame("│")
        let dataDiv = " " + div + " "

        // 4-space prefix on header: 2-col left margin + 2-col marker gutter.
        let headerBits =
            CLIColors.headerCol(pad("Name", width: cw.name)) + dataDiv
            + CLIColors.headerCol(pad("Size", width: cw.size)) + dataDiv
            + CLIColors.headerCol(pad("Created", width: cw.created)) + dataDiv
            + CLIColors.headerCol("Location")
        lines.append("    " + headerBits)

        // Subtle under-header rule with column-divider ticks ("┼") at each break.
        let nameRule = String(repeating: "─", count: cw.name + 1)
        let sizeRule = String(repeating: "─", count: cw.size + 2)
        let createdRule = String(repeating: "─", count: cw.created + 2)
        let pathRule = String(repeating: "─", count: cw.path + 1)
        let ruleLine = nameRule + "┼" + sizeRule + "┼" + createdRule + "┼" + pathRule
        lines.append("    " + CLIColors.frame(ruleLine))

        let selectedLineIdx: Int = {
            guard !input.snapshot.selectableIndices.isEmpty else { return -1 }
            let idx = min(max(0, input.selection), input.snapshot.selectableIndices.count - 1)
            return input.snapshot.selectableIndices[idx]
        }()

        for (idx, line) in input.snapshot.lines.enumerated() {
            switch line {
            case .header(let text):
                let t = text.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { lines.append("    " + CLIColors.muted(t)) }
            case .row(let row):
                let isSelected = idx == selectedLineIdx
                let marker = isSelected ? CLIColors.accent("▸") : " "
                let nameRaw = clip(row.url.lastPathComponent, width: cw.name)
                let nameCell = pad(nameRaw, width: cw.name)
                let sizeCell = pad(row.sizeLabel, width: cw.size)
                let createdCell = pad(row.modifiedLabel, width: cw.created)
                let locCell = displayPath(row.url.path, width: cw.path)
                let nameStyled = isSelected ? CLIColors.selected(nameCell) : CLIColors.bold(nameCell)
                let sizeStyled = CLIColors.muted(sizeCell)
                let createdStyled = CLIColors.muted(createdCell)
                let locStyled = CLIColors.tagline(locCell)
                lines.append(
                    "  " + marker + " "
                        + nameStyled + dataDiv
                        + sizeStyled + dataDiv
                        + createdStyled + dataDiv
                        + locStyled
                )
            }
        }

        if input.snapshot.selectableIndices.isEmpty {
            lines.append("")
            lines.append("  " + CLIColors.muted("No matches. Press / to filter, s to scan, or blazedb --create-test"))
        }

        if input.isFilterMode {
            let draft = input.filterDraft ?? ""
            lines.append("  " + CLIColors.accent("Filter: ") + draft + CLIColors.bold("▌") + "  " + CLIColors.muted("(Enter apply · Esc cancel)"))
        } else {
            let hint = "↑/↓ select   Enter open   [/] page   / filter   b bookmarks   s scan   ? help   q quit"
            lines.append("  " + CLIColors.muted(hint))
        }
        lines.append(CLIBranding.separator(width: cw.total))
        return lines.joined(separator: "\n")
    }
}
