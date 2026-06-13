//
//  BlazedbPicker.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

#if os(macOS) || os(Linux)

private final class ScanState: @unchecked Sendable {
    let lock = NSLock()
    var scanExtras: [URL] = []
    var scanSeen = Set<String>()
    var scanHitCount = 0
    var scanActive = false
    var completedHomeScanPass = false
    var dirty = true

    func normalized(_ path: String) -> String {
        CLIDiscovery.normalizePath(path)
    }

    func appendHit(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let n = normalized(url.path)
        guard scanSeen.insert(n).inserted else { return }
        scanExtras.append(url)
        scanHitCount = scanExtras.count
        dirty = true
    }

    func copyExtras() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return scanExtras
    }

    func takeDirty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let d = dirty
        dirty = false
        return d
    }

    func markDirty() {
        lock.lock()
        dirty = true
        lock.unlock()
    }

    func scanFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completedHomeScanPass && !scanActive
    }

    func isScanActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return scanActive
    }
}

public enum BlazedbPicker {
    static func readByte(timeoutMs: Int32, fd: Int32 = STDIN_FILENO) throws -> UInt8? {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pr = poll(&pfd, 1, timeoutMs)
        if pr <= 0 { return nil }
        if (pfd.revents & Int16(POLLIN | POLLHUP | POLLERR)) == 0 { return nil }

        var b: UInt8 = 0
        let bytesRead = read(fd, &b, 1)
        if bytesRead == 1 { return b }
        if bytesRead == 0 { throw CLIError.cancelled }
        return nil
    }

    public static func pickDatabase(
        registry: inout CLIRegistry,
        registryURL: URL,
        startHomeScanImmediately: Bool,
        showStartupSplash: Bool = true
    ) throws -> URL? {
        _ = registryURL
        let state = ScanState()
        var scanStartRequested = startHomeScanImmediately
        var query = PickerQuery()
        var selection = 0
        var filterDraft = ""
        var isFilterMode = false
        var lastRedraw = Date.distantPast
        var lastWidth = CLITerminalDraw.layoutColumns()
        var lastRows = CLITerminalDraw.layoutRows()
        let reg = registry

        CLITerminalDraw.enterAlternateScreen()
        defer { CLITerminalDraw.leaveAlternateScreen() }

        func scanStatusLine(totalVisible: Int) -> String? {
            if scanStartRequested && state.isScanActive() {
                return "Scanning… (\(state.scanHitCount) new paths; \(totalVisible) shown after filters)"
            }
            if scanStartRequested && state.scanFinished() {
                return "Ready · \(totalVisible) databases (test/backup shards hidden — press / to filter)"
            }
            return nil
        }

        func makeSnapshot() throws -> PickerSnapshot {
            var snap = try CLIDiscovery.buildPickerSnapshot(
                registry: reg,
                scanExtras: state.copyExtras(),
                scanStatus: nil,
                query: query
            )
            snap.scanStatus = scanStatusLine(totalVisible: snap.pageInfo.total)
            return snap
        }

        func startScanIfNeeded() {
            guard scanStartRequested else { return }
            state.lock.lock()
            if state.scanActive {
                state.lock.unlock()
                return
            }
            state.scanActive = true
            state.completedHomeScanPass = false
            state.lock.unlock()

            let home = FileManager.default.homeDirectoryForCurrentUser
            CLIHomeScanner.scan(home: home, onHit: { url in
                state.appendHit(url)
            }, completion: {
                state.lock.lock()
                state.scanActive = false
                state.completedHomeScanPass = true
                state.dirty = true
                state.lock.unlock()
            })
        }

        let raw = try TerminalRawMode()
        _ = raw

        func clampSelection(for snap: PickerSnapshot) {
            if snap.selectableIndices.isEmpty {
                selection = 0
            } else {
                selection = min(max(0, selection), snap.selectableIndices.count - 1)
            }
        }

        func redraw(force: Bool = false) throws {
            let now = Date()
            let minInterval: TimeInterval = state.isScanActive() ? 0.35 : 0.05
            if !force, now.timeIntervalSince(lastRedraw) < minInterval { return }
            lastRedraw = now

            let cols = CLITerminalDraw.layoutColumns()
            let rows = CLITerminalDraw.layoutRows()
            lastWidth = cols
            lastRows = rows
            let compact = rows < 22
            query.pageSize = CLIPickerRender.adaptivePageSize(rows: rows, compactBanner: compact)

            let snap = try makeSnapshot()
            clampSelection(for: snap)
            let frame = CLIPickerRender.renderFrame(
                CLIPickerRender.FrameInput(
                    snapshot: snap,
                    selection: selection,
                    filterText: query.filterText,
                    bookmarkedOnly: query.bookmarkedOnly,
                    filterDraft: filterDraft,
                    isFilterMode: isFilterMode,
                    terminalWidth: cols,
                    terminalRows: rows,
                    useCompactBanner: compact
                )
            )
            CLITerminalDraw.presentFrame(frame)
        }

        if scanStartRequested {
            startScanIfNeeded()
            if showStartupSplash {
                CLIStartupSplash.run(isComplete: { state.scanFinished() })
            }
        }

        state.markDirty()
        try redraw(force: true)

        while true {
            let widthChanged = CLITerminalDraw.layoutColumns() != lastWidth
            let rowsChanged = CLITerminalDraw.layoutRows() != lastRows
            let sizeChanged = widthChanged || rowsChanged
            let shouldRedraw = state.takeDirty() || state.isScanActive() || sizeChanged
            if shouldRedraw {
                try redraw(force: sizeChanged)
            }

            guard let b = try Self.readByte(timeoutMs: 120) else {
                continue
            }

            if isFilterMode {
                if b == 27 {
                    isFilterMode = false
                    filterDraft = ""
                    state.markDirty()
                    continue
                }
                if b == 10 || b == 13 {
                    query.filterText = filterDraft
                    query.page = 0
                    selection = 0
                    isFilterMode = false
                    state.markDirty()
                    try redraw(force: true)
                    continue
                }
                if b == 127 || b == 8 {
                    if !filterDraft.isEmpty { filterDraft.removeLast() }
                    try redraw(force: true)
                    continue
                }
                if b >= 32, b < 127, let scalar = UnicodeScalar(UInt32(b)) {
                    filterDraft.append(Character(scalar))
                    try redraw(force: true)
                }
                continue
            }

            if b == 27 {
                if let b2 = try Self.readByte(timeoutMs: 80), b2 == UInt8(ascii: "["),
                   let b3 = try Self.readByte(timeoutMs: 80) {
                    let snap = try makeSnapshot()
                    if snap.selectableIndices.isEmpty { continue }
                    if b3 == UInt8(ascii: "A") {
                        if selection > 0 {
                            selection -= 1
                        } else if query.page > 0 {
                            query.page -= 1
                            let next = try makeSnapshot()
                            selection = max(0, next.selectableIndices.count - 1)
                        }
                    } else if b3 == UInt8(ascii: "B") {
                        if selection < snap.selectableIndices.count - 1 {
                            selection += 1
                        } else if query.page < snap.pageInfo.pageCount - 1 {
                            query.page += 1
                            selection = 0
                        }
                    }
                    try redraw(force: true)
                }
                continue
            }

            if b == UInt8(ascii: "[") || b == UInt8(ascii: "p") || b == UInt8(ascii: "P") {
                if query.page > 0 {
                    query.page -= 1
                    selection = 0
                    try redraw(force: true)
                }
                continue
            }
            if b == UInt8(ascii: "]") || b == UInt8(ascii: "n") || b == UInt8(ascii: "N") {
                let snap = try makeSnapshot()
                if query.page < snap.pageInfo.pageCount - 1 {
                    query.page += 1
                    selection = 0
                    try redraw(force: true)
                }
                continue
            }

            if b == UInt8(ascii: "/") {
                isFilterMode = true
                filterDraft = query.filterText
                try redraw(force: true)
                continue
            }

            if b == UInt8(ascii: "b") || b == UInt8(ascii: "B") {
                query.bookmarkedOnly.toggle()
                query.page = 0
                selection = 0
                try redraw(force: true)
                continue
            }

            if b == UInt8(ascii: "?") || b == UInt8(ascii: "h") || b == UInt8(ascii: "H") {
                let cols = CLITerminalDraw.layoutColumns()
                var lines = CLIBranding.heroBlockLines(width: cols)
                lines.append("")
                lines.append("  " + CLIColors.bold("Shortcuts"))
                lines.append("    " + CLIColors.ice("↑/↓") + "      Select row (wraps across pages)")
                lines.append("    " + CLIColors.ice("Enter") + "    Open the selected database")
                lines.append("    " + CLIColors.ice("[ / ]") + "    Previous / next page (10 per page)")
                lines.append("    " + CLIColors.ice("/") + "        Filter by name (Enter apply, Esc cancel)")
                lines.append("    " + CLIColors.ice("b") + "        Toggle bookmarked-only filter")
                lines.append("    " + CLIColors.ice("s") + "        Re-scan your home directory")
                lines.append("    " + CLIColors.ice("?") + "        Show / hide this help")
                lines.append("    " + CLIColors.ice("q") + "        Quit picker")
                lines.append("")
                lines.append("  " + CLIColors.muted("press any key to return…"))
                lines.append(CLIBranding.separator(width: cols))
                CLITerminalDraw.presentFrame(lines.joined(separator: "\n"))
                _ = try Self.readByte(timeoutMs: 300_000)
                try redraw(force: true)
                continue
            }

            if b == UInt8(ascii: "q") || b == UInt8(ascii: "Q") {
                return nil
            }

            if b == UInt8(ascii: "s") || b == UInt8(ascii: "S") {
                scanStartRequested = true
                state.lock.lock()
                if !state.scanActive {
                    state.scanExtras.removeAll()
                    state.scanSeen.removeAll()
                    state.scanHitCount = 0
                    state.completedHomeScanPass = false
                }
                state.lock.unlock()
                startScanIfNeeded()
                state.markDirty()
                continue
            }

            if b == 10 || b == 13 {
                let snap = try makeSnapshot()
                guard !snap.selectableIndices.isEmpty else { continue }
                let lineIdx = snap.selectableIndices[selection]
                if case .row(let row) = snap.lines[lineIdx] {
                    return row.url
                }
            }
        }
    }
}

#else

public enum BlazedbPicker {
    public static func pickDatabase(
        registry: inout CLIRegistry,
        registryURL: URL,
        startHomeScanImmediately: Bool,
        showStartupSplash: Bool = true
    ) throws -> URL? {
        throw CLIError.terminal("Interactive picker requires macOS or Linux")
    }
}

#endif
