import Foundation
import BlazeDBCore

private enum CLIO {
    static func die(_ message: String, code: Int32 = 1) -> Never {
        let line = message.hasSuffix("\n") ? message : message + "\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
        exit(code)
    }
}

struct Item: BlazeStorable {
    var id: UUID = UUID()
    var title: String
}

@main
enum CorePathSmoke {
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-core-path-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("smoke.blazedb")
        let db = try BlazeDBClient.open(at: dbURL, password: "SmokePass123!")

        final class ObserveCounter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var count = 0
            func bump() {
                lock.lock()
                defer { lock.unlock() }
                count += 1
            }
        }

        let counter = ObserveCounter()
        var token: ObserverToken? = db.observe { _ in
            counter.bump()
        }
        defer {
            token?.invalidate()
            token = nil
        }

        let item = Item(title: "hello-core-path")
        try db.put(item)

        let loaded: Item? = try db.get("item:\(item.id.uuidString)")
        guard loaded?.title == item.title else {
            CLIO.die("get mismatch")
        }

        let all: [Item] = try db.query("item").all()
        guard all.contains(where: { $0.id == item.id }) else {
            CLIO.die("query mismatch")
        }

        try db.put(Item(title: "trigger-observe"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard counter.count >= 1 else {
            CLIO.die("observe did not fire (count=\(counter.count))")
        }

        print("core-path-smoke: ok observed=\(counter.count) queried=\(all.count)")
    }
}
