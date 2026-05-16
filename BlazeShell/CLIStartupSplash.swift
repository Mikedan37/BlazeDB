//
//  CLIStartupSplash.swift
//  BlazeCLICore
//

import Foundation

#if os(macOS) || os(Linux)

public enum CLIStartupSplash {
    public static func run(
        minimumSeconds: TimeInterval = 0.7,
        maximumSeconds: TimeInterval = 2.5,
        isComplete: @escaping () -> Bool
    ) {
        let started = Date()
        var frame = 0
        while true {
            let elapsed = Date().timeIntervalSince(started)
            let done = isComplete() && elapsed >= minimumSeconds
            if done || elapsed >= maximumSeconds { break }

            let cols = CLITerminalDraw.layoutColumns()
            let rows = CLITerminalDraw.layoutRows()
            var lines = rows < 12
                ? CLIBranding.heroCompactLines(width: cols)
                : CLIBranding.heroBlockLines(width: cols)
            lines.append("")
            lines.append(CLIBranding.spinnerText(frame: frame, message: "Scanning your Mac for databases…"))
            lines.append(CLIBranding.separator(width: cols))
            CLITerminalDraw.presentFrame(lines.joined(separator: "\n"))
            frame += 1
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

#endif
