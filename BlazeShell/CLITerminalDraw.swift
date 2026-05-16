//
//  CLITerminalDraw.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

public enum CLITerminalDraw {
    private static func writeStdout(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    public static func layoutColumns(fallback: Int = 80) -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 else { return fallback }
        let cols = Int(size.ws_col)
        if cols < 60 { return 60 }
        if cols > 140 { return 140 }
        return cols
    }

    public static func layoutRows(fallback: Int = 30) -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 else { return fallback }
        let rows = Int(size.ws_row)
        if rows < 12 { return 12 }
        return rows
    }

    public static func enterAlternateScreen() {
        writeStdout("\u{1b}[?1049h")
        writeStdout("\u{1b}[?25l")
        writeStdout("\u{1b}[H")
    }

    public static func leaveAlternateScreen() {
        writeStdout("\u{1b}[?25h")
        writeStdout("\u{1b}[?1049l")
    }

    /// Replace entire alternate screen with one frame.
    /// Converts every '\n' into '\r\n' so raw-mode terminals don't stairstep.
    public static func presentFrame(_ frame: String) {
        writeStdout("\u{1b}[H\u{1b}[2J")
        let normalized = frame.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        writeStdout(normalized)
        writeStdout("\r\n")
    }

    public static func writeLine(_ text: String) {
        writeStdout(text)
        writeStdout("\r\n")
    }

    public static func clearScreen() {
        writeStdout("\u{1b}[2J\u{1b}[H")
    }

    public static func flush() {
        // FileHandle writes are immediate; keep API for call-site compatibility.
    }
}
