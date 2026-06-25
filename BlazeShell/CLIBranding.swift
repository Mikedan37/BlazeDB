//
//  CLIBranding.swift
//  BlazeCLICore
//

import Foundation

public enum CLIBranding {
    public static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// Full hero block: 6 art rows + top/bottom rules.
    /// Layout per row (visible widths):
    ///   "  " (2) + fireL (5) + "  " (2) + cylinder (9) + "  " (2) + fireR (5) + "    " (4) + title-side
    /// The cylinder/fire glyph is intentionally shorter; title block is taller so
    /// branding and symbol feel visually balanced.
    public static func heroLines() -> [String] {
        let tip = CLIColors.flameTip
        let yellow = CLIColors.flameYellow
        let orange = CLIColors.flameOrange
        let red = CLIColors.flameRed
        let deep = CLIColors.flameDeep

        let edge = CLIColors.dbEdge
        let fill = CLIColors.dbFill

        let bar = CLIColors.accentBar("▌")
        // Taller 4-row block letters for BLAZEDB.
        let t0 = "█▀▀█ █    ▄▀▄   ▀▀▀█ █▀▀  █▀▀▄ █▀▀█"
        let t1 = "█▀▀▄ █    █▀█    ▄▀  █▀▀  █  █ █▀▀▄"
        let t2 = "█▀▀█ █    █ █   ▄▀   █▀▀  █  █ █▀▀█"
        let t3 = "▀▀▀  ▀▀▀▀ ▀ ▀  ▀▀▀▀  ▀▀▀▀ ▀▀▀  ▀▀▀ "
        let titleBold = CLIColors.titleBold
        let title0 = titleBold(t0)
        let title1 = titleBold(t1)
        let title2 = titleBold(t2)
        let title3 = titleBold(t3)
        let tag1 = CLIColors.tagline("LOCAL ENCRYPTED DATABASES")
        let tag2 = CLIColors.subline("pick · unlock · inspect · query")

        // Flames: 6 rows, each exactly 5 visible cells.
        // Hottest at the wide middle, cooler tips and base.
        let f1 = tip("  ░  ")
        let f2 = yellow(" ░▒░ ")
        let f3 = orange("▒▓█▓▒")
        let f4 = red("▓███▓")
        let f5 = orange(" ▓█▓ ")
        let f6 = deep("  ▀  ")

        // Shorter rounded cylinder, 6 rows, 9 visible cells wide each.
        let cap1 = edge("╭───────╮")
        let body = edge("│") + fill("░░░░░░░") + edge("│")
        let mid  = edge("╞═══════╡")
        let cap2 = edge("╰───────╯")

        return [
            "  " + f1 + "  " + cap1 + "  " + f1 + "    " + title0,
            "  " + f2 + "  " + body + "  " + f2 + "    " + title1,
            "  " + f3 + "  " + mid  + "  " + f3 + "    " + title2,
            "  " + f4 + "  " + body + "  " + f4 + "    " + title3,
            "  " + f5 + "  " + mid  + "  " + f5 + "    " + bar + " " + tag1,
            "  " + f6 + "  " + cap2 + "  " + f6 + "    " + bar + " " + tag2,
        ]
    }

    public static func heroBlockLines(width: Int) -> [String] {
        let bar = String(repeating: "═", count: max(40, width))
        var lines: [String] = []
        lines.append(CLIColors.frame(bar))
        for line in heroLines() { lines.append(line) }
        lines.append(CLIColors.frame(bar))
        return lines
    }

    /// 3-line compact banner for very short terminals.
    public static func heroCompactLines(width: Int) -> [String] {
        let bar = String(repeating: "═", count: max(40, width))
        let badge = CLIColors.flameRed("▓") + CLIColors.flameOrange("█") + CLIColors.flameYellow("░")
        let title = CLIColors.titleBold("BLAZEDB")
        let tag = CLIColors.subline(" · local encrypted databases · pick · unlock · query")
        return [
            CLIColors.frame(bar),
            "  \(badge)  \(title)\(tag)",
            CLIColors.frame(bar),
        ]
    }

    public static func spinnerText(frame: Int, message: String) -> String {
        let spin = CLIColors.flameOrange(spinnerFrames[frame % spinnerFrames.count])
        return "  \(spin)  \(CLIColors.muted(message))"
    }

    public static func separator(width: Int) -> String {
        CLIColors.frame(String(repeating: "─", count: max(20, width)))
    }
}
