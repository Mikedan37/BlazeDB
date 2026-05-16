//
//  CLIPasswordReader.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

#if os(macOS) || os(Linux)
public enum CLIPasswordReader {
    /// Reads a single line from stdin with echo disabled (restores tty afterward).
    public static func readLineHidden(prompt: String) throws -> String {
        let fd = STDIN_FILENO
        var saved = termios()
        guard tcgetattr(fd, &saved) == 0 else {
            throw CLIError.terminal("tcgetattr failed")
        }
        var noEcho = saved
        let echoMask: tcflag_t = tcflag_t(ECHO) | tcflag_t(ECHOE) | tcflag_t(ECHOK) | tcflag_t(ECHONL)
        noEcho.c_lflag &= ~echoMask
        guard tcsetattr(fd, TCSANOW, &noEcho) == 0 else {
            throw CLIError.terminal("tcsetattr failed")
        }
        defer { _ = tcsetattr(fd, TCSANOW, &saved) }

        fputs(prompt, stderr)
        fflush(stderr)
        guard let line = Swift.readLine() else {
            throw CLIError.cancelled
        }
        return line
    }
}
#else
public enum CLIPasswordReader {
    public static func readLineHidden(prompt: String) throws -> String {
        throw CLIError.terminal("Password prompt unsupported on this platform")
    }
}
#endif
