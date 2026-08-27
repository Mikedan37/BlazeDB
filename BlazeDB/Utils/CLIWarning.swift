//
//  CLIWarning.swift
//  BlazeDB
//
//  Swift 6-safe stderr warnings for standalone CLI executables (#310/#313).
//

import Foundation

public enum CLIWarning {
    /// Write a warning line to stderr without touching the global `stderr` var (Linux Swift 6).
    public static func write(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
