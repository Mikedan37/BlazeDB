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
        fputs("\u{1b}[?1049h", stdout)
        fputs("\u{1b}[?25l", stdout)
        fputs("\u{1b}[H", stdout)
        fflush(stdout)
    }

    public static func leaveAlternateScreen() {
        fputs("\u{1b}[?25h", stdout)
        fputs("\u{1b}[?1049l", stdout)
        fflush(stdout)
    }

    /// Replace entire alternate screen with one frame.
    /// Converts every '\n' into '\r\n' so raw-mode terminals don't stairstep.
    public static func presentFrame(_ frame: String) {
        fputs("\u{1b}[H\u{1b}[2J", stdout)
        let normalized = frame.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        fputs(normalized, stdout)
        fputs("\r\n", stdout)
        fflush(stdout)
    }

    public static func writeLine(_ text: String) {
        fputs(text, stdout)
        fputs("\r\n", stdout)
    }

    public static func clearScreen() {
        fputs("\u{1b}[2J\u{1b}[H", stdout)
    }

    public static func flush() {
        fflush(stdout)
    }
}
