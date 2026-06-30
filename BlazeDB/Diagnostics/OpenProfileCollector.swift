//
//  OpenProfileCollector.swift
//  BlazeDBCore
//
//  Opt-in cold-open span collection (BLAZEDB_PROFILE_OPEN=1).
//  Used by BlazeDBOpenProfiler and regression tests — no overhead when disabled.
//

import Foundation

public enum OpenProfileCollector {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var spans: [(name: String, milliseconds: Double)] = []

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BLAZEDB_PROFILE_OPEN"] == "1"
    }

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        spans.removeAll(keepingCapacity: true)
    }

    public static func record(_ name: String, milliseconds: Double) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        spans.append((name: name, milliseconds: milliseconds))
    }

    @discardableResult
    public static func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        guard isEnabled else { return try block() }
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            record(name, milliseconds: ms)
        }
        return try block()
    }

    public static func measure(_ name: String, _ block: () throws -> Void) rethrows {
        guard isEnabled else { try block(); return }
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            record(name, milliseconds: ms)
        }
        try block()
    }

    public static func snapshot() -> [(name: String, milliseconds: Double)] {
        lock.lock()
        defer { lock.unlock() }
        return spans
    }

    public static func totalMilliseconds() -> Double {
        snapshot().reduce(0) { $0 + $1.milliseconds }
    }

    public static func markdownTable(title: String) -> String {
        let rows = snapshot()
        guard !rows.isEmpty else { return "\(title)\n\n(no spans recorded)\n" }
        let total = rows.reduce(0.0) { $0 + $1.milliseconds }
        var lines = [
            title,
            "",
            "| Phase | ms | % of measured |",
            "|-------|---:|--------------:|",
        ]
        for row in rows {
            let pct = total > 0 ? (row.milliseconds / total) * 100.0 : 0
            lines.append("| \(row.name) | \(String(format: "%.2f", row.milliseconds)) | \(String(format: "%.1f", pct))% |")
        }
        lines.append("| **Total (spans)** | **\(String(format: "%.2f", total))** | **100%** |")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
