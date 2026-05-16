//
//  CLITerminalSize.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

public enum CLITerminalSize {
    public static func columns(fallback: Int = 100) -> Int {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 else { return fallback }
        let cols = Int(size.ws_col)
        return cols > 20 ? cols : fallback
    }
}
