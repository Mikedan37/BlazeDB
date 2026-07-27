//
//  WriteProfileCollector.swift
//  BlazeDBCore
//
//  Opt-in durable-write stage profiling (BLAZEDB_WRITE_PROFILE=1).
//  Benchmark / debug investigation only — zero overhead when disabled.
//  Not product telemetry.
//

import Foundation

public enum WriteProfilePath: String, Codable, Sendable {
    case singleInsert
    case insertMany
    case transactionPuts
}

public enum WriteProfileSyscall: String, Codable, Hashable, Sendable {
    case write
    case fsync
}

public struct WriteProfileOperation: Codable, Sendable, Equatable {
    public var path: WriteProfilePath
    public var batchSize: Int
    public var durabilityMode: String
    public var recordBytes: Int
    public var steadyState: Bool

    public init(
        path: WriteProfilePath,
        batchSize: Int,
        durabilityMode: String,
        recordBytes: Int,
        steadyState: Bool
    ) {
        self.path = path
        self.batchSize = batchSize
        self.durabilityMode = durabilityMode
        self.recordBytes = recordBytes
        self.steadyState = steadyState
    }
}

public struct WriteProfileSpan: Codable, Sendable, Equatable {
    public var name: String
    public var milliseconds: Double
}

public struct WriteProfileSnapshot: Sendable {
    public var operations: [WriteProfileOperation]
    public var spans: [WriteProfileSpan]
    public var bytesWritten: Int
    public var syscallCounts: [WriteProfileSyscall: Int]
}

/// Collects stage timings for durable writes when `BLAZEDB_WRITE_PROFILE=1`.
public enum WriteProfileCollector {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var operations: [WriteProfileOperation] = []
    private nonisolated(unsafe) static var spans: [WriteProfileSpan] = []
    private nonisolated(unsafe) static var bytesWritten: Int = 0
    private nonisolated(unsafe) static var syscallCounts: [WriteProfileSyscall: Int] = [:]
    private nonisolated(unsafe) static var openOperation: WriteProfileOperation?

    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BLAZEDB_WRITE_PROFILE"] == "1"
    }

    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        operations.removeAll(keepingCapacity: true)
        spans.removeAll(keepingCapacity: true)
        bytesWritten = 0
        syscallCounts.removeAll(keepingCapacity: true)
        openOperation = nil
    }

    public static func beginOperation(_ op: WriteProfileOperation) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        // Nested begin (e.g. insert inside transactionPuts) keeps the outer operation.
        if openOperation == nil {
            openOperation = op
        }
    }

    /// True when an outer operation (e.g. transactionPuts) owns the current profile window.
    public static var hasOpenOperation: Bool {
        guard isEnabled else { return false }
        lock.lock()
        defer { lock.unlock() }
        return openOperation != nil
    }

    public static func endOperation() {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if let op = openOperation {
            operations.append(op)
            openOperation = nil
        }
    }

    public static func record(_ name: String, milliseconds: Double) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        spans.append(WriteProfileSpan(name: name, milliseconds: milliseconds))
    }

    public static func addBytes(_ count: Int) {
        guard isEnabled, count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        bytesWritten += count
    }

    public static func addSyscall(kind: WriteProfileSyscall, count: Int = 1) {
        guard isEnabled, count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        syscallCounts[kind, default: 0] += count
    }

    private static func monotonicSeconds() -> Double {
        BlazeDBDiagnostics.monotonicSeconds()
    }

    @discardableResult
    public static func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        guard isEnabled else { return try block() }
        let start = monotonicSeconds()
        defer {
            let ms = (monotonicSeconds() - start) * 1000.0
            record(name, milliseconds: ms)
        }
        return try block()
    }

    public static func measure(_ name: String, _ block: () throws -> Void) rethrows {
        guard isEnabled else { try block(); return }
        let start = monotonicSeconds()
        defer {
            let ms = (monotonicSeconds() - start) * 1000.0
            record(name, milliseconds: ms)
        }
        try block()
    }

    public static func snapshot() -> WriteProfileSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return WriteProfileSnapshot(
            operations: operations,
            spans: spans,
            bytesWritten: bytesWritten,
            syscallCounts: syscallCounts
        )
    }

    public static func markdownReport(title: String = "Write path profile") -> String {
        let snap = snapshot()
        var lines = [
            "# \(title)",
            "",
        ]
        if let op = snap.operations.last ?? snap.operations.first {
            lines.append("Path: `\(op.path.rawValue)` · batch=\(op.batchSize) · durability=`\(op.durabilityMode)` · recordBytes≈\(op.recordBytes) · steadyState=\(op.steadyState)")
            lines.append("")
        }
        if snap.spans.isEmpty {
            lines.append("(no spans recorded)")
            lines.append("")
            return lines.joined(separator: "\n")
        }
        let total = snap.spans.reduce(0.0) { $0 + $1.milliseconds }
        lines.append("| Stage | ms | % of measured |")
        lines.append("|-------|---:|--------------:|")
        for span in snap.spans {
            let pct = total > 0 ? (span.milliseconds / total) * 100.0 : 0
            lines.append("| \(span.name) | \(String(format: "%.3f", span.milliseconds)) | \(String(format: "%.1f", pct))% |")
        }
        lines.append("| **Total (spans)** | **\(String(format: "%.3f", total))** | **100%** |")
        lines.append("")
        lines.append("Bytes written (instrumented): \(snap.bytesWritten)")
        let writeN = snap.syscallCounts[.write] ?? 0
        let fsyncN = snap.syscallCounts[.fsync] ?? 0
        lines.append("Syscall counts (instrumented): write=\(writeN) fsync=\(fsyncN)")
        lines.append("")
        lines.append("_Enable with `BLAZEDB_WRITE_PROFILE=1`. Not product telemetry._")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
