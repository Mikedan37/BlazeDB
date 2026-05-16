//
//  TerminalRawMode.swift
//  BlazeCLICore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

#if os(macOS) || os(Linux)
public final class TerminalRawMode: @unchecked Sendable {
    private var saved: termios
    private let fd: Int32

    public init(fd: Int32 = STDIN_FILENO) throws {
        self.fd = fd
        var t = termios()
        if tcgetattr(fd, &t) != 0 {
            throw CLIError.terminal("tcgetattr failed")
        }
        saved = t
        var raw = t
        cfmakeraw(&raw)
        raw.c_oflag |= tcflag_t(OPOST | ONLCR)
        if tcsetattr(fd, TCSANOW, &raw) != 0 {
            throw CLIError.terminal("tcsetattr(raw) failed")
        }
    }

    deinit {
        _ = tcsetattr(fd, TCSANOW, &saved)
    }
}

public enum CLIError: Error, Equatable {
    case terminal(String)
    case cancelled
}
#else
public final class TerminalRawMode: @unchecked Sendable {
    public init(fd: Int32 = 0) throws {
        throw CLIError.terminal("Raw terminal mode unsupported on this platform")
    }
}

public enum CLIError: Error, Equatable {
    case terminal(String)
    case cancelled
}
#endif
