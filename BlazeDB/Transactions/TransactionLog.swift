//  TransactionLog.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/16/25.
import Foundation

struct TransactionLog {
    // Durable Write-Ahead Journal Implementation

    let logFileURL: URL

    enum Operation: Codable {
        case write(pageID: Int, data: Data)
        case delete(pageID: Int)
        case begin(txID: Int)
        case commit(txID: Int)
        case abort(txID: Int)

        private enum CodingKeys: String, CodingKey {
            case type, pageID, data, txID
        }
        private enum Kind: String, Codable { case write, delete, begin, commit, abort }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(Kind.self, forKey: .type)
            switch type {
            case .write:
                let pageID = try c.decode(Int.self, forKey: .pageID)
                let data = try c.decode(Data.self, forKey: .data)
                self = .write(pageID: pageID, data: data)
            case .delete:
                let pageID = try c.decode(Int.self, forKey: .pageID)
                self = .delete(pageID: pageID)
            case .begin:
                let txID = try c.decode(Int.self, forKey: .txID)
                self = .begin(txID: txID)
            case .commit:
                let txID = try c.decode(Int.self, forKey: .txID)
                self = .commit(txID: txID)
            case .abort:
                let txID = try c.decode(Int.self, forKey: .txID)
                self = .abort(txID: txID)
            }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .write(let pageID, let data):
                try c.encode(Kind.write, forKey: .type)
                try c.encode(pageID, forKey: .pageID)
                try c.encode(data, forKey: .data)
            case .delete(let pageID):
                try c.encode(Kind.delete, forKey: .type)
                try c.encode(pageID, forKey: .pageID)
            case .begin(let txID):
                try c.encode(Kind.begin, forKey: .type)
                try c.encode(txID, forKey: .txID)
            case .commit(let txID):
                try c.encode(Kind.commit, forKey: .type)
                try c.encode(txID, forKey: .txID)
            case .abort(let txID):
                try c.encode(Kind.abort, forKey: .type)
                try c.encode(txID, forKey: .txID)
            }
        }
    }

    // Ensure the log file exists on disk
    public func ensureExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logFileURL.path) {
            try Data().write(to: logFileURL)
        }
    }

    private(set) var operations: [Operation] = []

    static var defaultPath: URL {
        // Use a temp-directory WAL by default so tests and ephemeral runs can locate it reliably.
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("txlog.blz")
    }

    init(logFileURL: URL) {
        self.logFileURL = logFileURL
    }

    init() {
        self.logFileURL = TransactionLog.defaultPath
    }

    // Decode newline-delimited JSON of Operation from raw data
    private static func decodeLines(_ data: Data) -> [Operation] {
        let lines = data.split(separator: 0x0a)
        let decoder = JSONDecoder()
        var ops: [Operation] = [Operation]()
        for line in lines where !line.isEmpty {
            if let op = try? decoder.decode(Operation.self, from: line) {
                ops.append(op)
            }
        }
        return ops
    }

    // Read all valid entries from a specific log URL
    static func readAll(from url: URL) -> [Operation] {
        guard let data = try? Data(contentsOf: url) else { return [Operation]() }
        return decodeLines(data)
    }

    // Read all valid entries from the log file
    func readAll() -> [Operation] {
        return TransactionLog.readAll(from: logFileURL)
    }

    mutating func recordWrite(pageID: Int, data: Data) {
        operations.append(.write(pageID: pageID, data: data))
    }

    mutating func recordDelete(pageID: Int) {
        operations.append(.delete(pageID: pageID))
    }

    // Append a single entry as JSON (newline-delimited) to the log file
    func append(_ op: Operation) throws {
        let url = logFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(op)
        guard let fh = try? FileHandle(forWritingTo: url) else {
            // If file doesn't exist, create and write
            try (data + Data([0x0a])).write(to: url, options: .atomic)
            return
        }
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: data)
        try fh.write(contentsOf: Data([0x0a]))
        try fh.synchronize()
    }

    // Append to a specific WAL file
    func append(_ op: Operation, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(op)
        if FileManager.default.fileExists(atPath: url.path) == false {
            try (data + Data([0x0a])).write(to: url, options: .atomic)
            return
        }
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: data)
        try fh.write(contentsOf: Data([0x0a]))
        try fh.synchronize()
    }

    // Convenience methods for transaction control
    func begin(txID: Int) throws {
        try self.append(.begin(txID: txID))
    }

    func commit(txID: Int) throws {
        try self.append(.commit(txID: txID))
    }

    func abort(txID: Int) throws {
        try self.append(.abort(txID: txID))
    }

    // Replay committed entries into PageStore and truncate log
    func recover(into store: PageStore) throws {
        try recover(into: store, from: logFileURL)
    }

    // Strict recovery from a specific WAL: only committed txns are applied
    func recover(into store: PageStore, from url: URL) throws {
        let ops = TransactionLog.readAll(from: url)

        var buffers: [Int: [Operation]] = [Int: [Operation]]()
        var committed = Set<Int>()
        var aborted = Set<Int>()
        var current: Int? = nil

        for op in ops {
            switch op {
            case .begin(let txID):
                // Start a new buffer; if one already exists uncommitted, discard it.
                buffers[txID] = [Operation]()
                current = txID

            case .write(let pageID, let data):
                // Only record writes that occur after a BEGIN for the current tx and with non-empty data
                if let tx = current, data.isEmpty == false {
                    buffers[tx, default: [Operation]()].append(.write(pageID: pageID, data: data))
                }

            case .delete(let pageID):
                if let tx = current {
                    buffers[tx, default: [Operation]()].append(.delete(pageID: pageID))
                }

            case .commit(let txID):
                if current == txID {
                    committed.insert(txID)
                    current = nil
                }

            case .abort(let txID):
                aborted.insert(txID)
                buffers.removeValue(forKey: txID)
                if current == txID { current = nil }
            }
        }

        for txID in committed {
            guard aborted.contains(txID) == false, let txOps = buffers[txID] else { continue }
            for op in txOps {
                switch op {
                case .write(let pageID, let data):
                    // Skip writes that would produce an empty page payload.
                    guard data.isEmpty == false else { continue }
                    try store.writePage(index: pageID, plaintext: data)
                case .delete(let pageID):
                    try store.deletePage(index: pageID)
                default:
                    break
                }
            }
        }

        // Cleanup uncommitted transactions by deleting or zeroing affected pages
        let uncommittedTxIDs = Set(buffers.keys).subtracting(committed)
        for txID in uncommittedTxIDs {
            guard let txOps = buffers[txID] else { continue }
            for op in txOps {
                switch op {
                case .write(let pageID, _):
                    // Log cleanup action
                    print("Cleaning uncommitted write on page \(pageID) from transaction \(txID)")
                    // Delete the page or zero it out to clean uncommitted data
                    try store.deletePage(index: pageID)
                case .delete(let pageID):
                    // Log cleanup action
                    print("Cleaning uncommitted delete on page \(pageID) from transaction \(txID)")
                    // To clean uncommitted delete, could attempt to restore or just ignore
                    // Here, just log and do nothing
                    break
                default:
                    break
                }
            }
        }

        // Truncate WAL after recovery
        try clear(url)
    }

    // Empty the log after a successful commit
    func clear() throws {
        try clear(logFileURL)
    }

    func clear(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.truncate(atOffset: 0)
        try fh.synchronize()
    }

    // Flush: optionally persist to disk before applying to PageStore
    func flush(to store: PageStore, durable: Bool = false) throws {
        if durable {
            // Write all operations to log first
            for op in operations {
                try self.append(op)
            }
        }
        for op in operations {
            switch op {
            case .write(let pageID, let data):
                try store.writePage(index: pageID, plaintext: data)
            case .delete(let pageID):
                // Delete the page from the store
                try store.deletePage(index: pageID)
            default:
                break
            }
        }
        if durable {
            // After applying, clear the log
            try self.clear()
        }
    }
}

// MARK: - Test Compatibility Extensions
extension TransactionLog {
    // UUID compatibility for tests
    func appendBegin(txID: UUID) throws {
        try self.append(.begin(txID: txID.hashValue))
    }

    func appendWrite(pageID: Int, data: Data) throws {
        try self.append(.write(pageID: pageID, data: data))
    }

    func appendCommit(txID: UUID) throws {
        try self.append(.commit(txID: txID.hashValue))
    }

    func appendAbort(txID: UUID) throws {
        try self.append(.abort(txID: txID.hashValue))
    }

    func appendBegin(txID: UUID, logURL: URL) throws {
        try self.append(.begin(txID: txID.hashValue), to: logURL)
    }
    func appendWrite(pageID: Int, data: Data, logURL: URL) throws {
        try self.append(.write(pageID: pageID, data: data), to: logURL)
    }
    func appendCommit(txID: UUID, logURL: URL) throws {
        try self.append(.commit(txID: txID.hashValue), to: logURL)
    }
    func appendAbort(txID: UUID, logURL: URL) throws {
        try self.append(.abort(txID: txID.hashValue), to: logURL)
    }

    // LogURL-compatible recover shim
    func recover(into store: PageStore, logURL: URL) {
        try? recover(into: store, from: logURL)
    }
}
