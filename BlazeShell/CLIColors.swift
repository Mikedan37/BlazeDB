//
//  CLIColors.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

public enum CLIColors {
    public static var enabled: Bool {
        guard isatty(STDOUT_FILENO) != 0 else { return false }
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        if ProcessInfo.processInfo.environment["TERM"] == "dumb" { return false }
        return true
    }

    private static func wrap(_ code: String, _ text: String) -> String {
        guard enabled else { return text }
        return "\u{1b}[\(code)m\(text)\u{1b}[0m"
    }

    // --- Fire (truecolor red→orange→yellow gradient) ---
    public static func flameDeep(_ t: String) -> String { wrap("1;38;2;180;20;10", t) }  // dark base
    public static func flameRed(_ t: String) -> String { wrap("1;38;2;235;60;25", t) }
    public static func flameOrange(_ t: String) -> String { wrap("1;38;2;255;130;30", t) }
    public static func flameYellow(_ t: String) -> String { wrap("1;38;2;255;215;90", t) }
    public static func flameTip(_ t: String) -> String { wrap("1;38;2;255;245;180", t) } // hottest white-yellow

    // --- Database cylinder ---
    public static func dbEdge(_ t: String) -> String { wrap("38;2;120;200;255", t) }
    public static func dbFill(_ t: String) -> String { wrap("38;2;60;140;210", t) }
    public static func dbDeep(_ t: String) -> String { wrap("38;2;35;90;160", t) }

    // --- Title block ---
    public static func titleBold(_ t: String) -> String { wrap("1;38;2;255;240;210", t) }
    public static func tagline(_ t: String) -> String { wrap("38;2;200;200;210", t) }
    public static func subline(_ t: String) -> String { wrap("38;2;150;150;160", t) }
    public static func accentBar(_ t: String) -> String { wrap("1;38;2;255;120;30", t) }

    // --- Chrome ---
    public static func frame(_ t: String) -> String { wrap("38;2;80;82;92", t) }
    public static func muted(_ t: String) -> String { wrap("38;2;150;150;160", t) }
    public static func dim(_ t: String) -> String { wrap("2", t) }
    public static func bold(_ t: String) -> String { wrap("1;38;2;235;235;240", t) }
    public static func ice(_ t: String) -> String { wrap("38;2;130;200;255", t) }
    public static func accent(_ t: String) -> String { wrap("1;38;2;255;130;30", t) }
    public static func selected(_ t: String) -> String { wrap("1;38;2;255;160;60", t) }
    public static func headerCol(_ t: String) -> String { wrap("1;38;2;180;180;195", t) }

    // Compatibility shims for older call sites.
    public static func dbBlue(_ t: String) -> String { dbEdge(t) }
    public static func dbStripe(_ t: String) -> String { dbFill(t) }
}
