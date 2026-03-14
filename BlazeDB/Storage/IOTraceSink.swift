import Foundation

#if DEBUG
internal enum IOTraceSink {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var initialized = false
    nonisolated(unsafe) private static var traceDir: URL?
    nonisolated(unsafe) private static var traceFile: URL?
    nonisolated(unsafe) private static var lockOwners: [String: String] = [:]
    nonisolated(unsafe) private static var tail: [[String: Any]] = []
    private static let maxTail = 512

    private static func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true

        let env = ProcessInfo.processInfo.environment
        guard let dirRaw = env["BLAZEDB_IO_TRACE_DIR"], !dirRaw.isEmpty else {
            return
        }
        let dir = URL(fileURLWithPath: dirRaw, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            traceDir = dir
            traceFile = dir.appendingPathComponent("io_trace.jsonl")
        } catch {
            traceDir = nil
            traceFile = nil
        }
    }

    internal static func enabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        initializeIfNeeded()
        return traceFile != nil
    }

    internal static func record(
        operation: String,
        path: String?,
        fd: Int32? = nil,
        resultCode: Int32? = nil,
        errnoValue: Int32? = nil,
        context: [String: String] = [:]
    ) {
        lock.lock()
        defer { lock.unlock() }
        initializeIfNeeded()
        guard let traceFile else { return }

        let event = eventPayload(
            operation: operation,
            path: path,
            fd: fd,
            resultCode: resultCode,
            errnoValue: errnoValue,
            context: context
        )
        appendToTail(event)

        if operation == "lock_acquired", let path {
            lockOwners[path] = String(event["threadID"] as? UInt64 ?? 0)
        } else if operation == "lock_released", let path {
            lockOwners.removeValue(forKey: path)
        }

        writeJSONLine(event, to: traceFile)
    }

    internal static func ownerHint(for path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        initializeIfNeeded()
        return lockOwners[path]
    }

    @discardableResult
    internal static func dumpTailSummary(
        reason: String,
        operation: String,
        path: String?,
        errnoValue: Int32?
    ) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        initializeIfNeeded()
        guard let dir = traceDir else { return nil }

        let summaryURL = dir.appendingPathComponent("io_trace_tail.json")
        let payload: [String: Any] = [
            "reason": reason,
            "operation": operation,
            "path": path as Any,
            "errno": errnoValue as Any,
            "timestampMonotonicNs": DispatchTime.now().uptimeNanoseconds,
            "tail": tail.suffix(80)
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try data.write(to: summaryURL, options: .atomic)
            return summaryURL
        } catch {
            return nil
        }
    }

    private static func eventPayload(
        operation: String,
        path: String?,
        fd: Int32?,
        resultCode: Int32?,
        errnoValue: Int32?,
        context: [String: String]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "timestampMonotonicNs": DispatchTime.now().uptimeNanoseconds,
            "threadID": threadID(),
            "operation": operation
        ]
        if let path { payload["path"] = path }
        if let fd { payload["fd"] = fd }
        if let resultCode { payload["result"] = resultCode }
        if let errnoValue { payload["errno"] = errnoValue }
        if !context.isEmpty { payload["context"] = context }
        return payload
    }

    private static func appendToTail(_ event: [String: Any]) {
        tail.append(event)
        if tail.count > maxTail {
            tail.removeFirst(tail.count - maxTail)
        }
    }

    private static func writeJSONLine(_ payload: [String: Any], to url: URL) {
        do {
            var line = try JSONSerialization.data(withJSONObject: payload, options: [])
            line.append(0x0a)
            if !FileManager.default.fileExists(atPath: url.path) {
                try line.write(to: url, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // Tracing must never fail the engine.
        }
    }

    private static func threadID() -> UInt64 {
        #if canImport(Darwin)
        return UInt64(pthread_mach_thread_np(pthread_self()))
        #else
        return UInt64(bitPattern: Int64(ObjectIdentifier(Thread.current).hashValue))
        #endif
    }
}
#else
internal enum IOTraceSink {
    internal static func enabled() -> Bool { false }
    internal static func record(
        operation: String,
        path: String?,
        fd: Int32? = nil,
        resultCode: Int32? = nil,
        errnoValue: Int32? = nil,
        context: [String: String] = [:]
    ) {}
    internal static func ownerHint(for path: String) -> String? { nil }
    @discardableResult
    internal static func dumpTailSummary(
        reason: String,
        operation: String,
        path: String?,
        errnoValue: Int32?
    ) -> URL? { nil }
}
#endif
