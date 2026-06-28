import Foundation
import BlazeDBCore

// C callback type (matches include/blazedb_android_bridge.h).
public typealias blazedb_bridge_live_query_cb = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

// C ABI exports for Android JNI shims (see examples/android/app/src/main/cpp/).

private struct Todo: BlazeStorable, Codable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

private enum BridgeError: Error {
    case invalidPath
    case invalidPassword
}

private final class LiveQuerySlot: @unchecked Sendable {
    let db: BlazeDBClient
    let query: BlazeLiveQuery<Todo>
    init(db: BlazeDBClient, query: BlazeLiveQuery<Todo>) {
        self.db = db
        self.query = query
    }

    func stop() {
        query.stop()
        try? db.close()
    }
}

private final class LiveQueryRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: Int64 = 1
    private var slots: [Int64: LiveQuerySlot] = [:]

    func insert(_ slot: LiveQuerySlot) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        slots[id] = slot
        return id
    }

    func remove(_ id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        slots[id]?.stop()
        slots.removeValue(forKey: id)
    }
}

private let liveQueryRegistry = LiveQueryRegistry()

private func cString(_ ptr: UnsafePointer<CChar>?) throws -> String {
    guard let ptr else { throw BridgeError.invalidPath }
    let value = String(cString: ptr)
    guard !value.isEmpty else { throw BridgeError.invalidPath }
    return value
}

private func encodeTodos(_ todos: [Todo]) -> String {
    let payload: [[String: Any]] = todos.map { todo in
        [
            "id": todo.id.uuidString,
            "title": todo.title,
            "isDone": todo.isDone,
        ]
    }
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8)
    else {
        return "[]"
    }
    return json
}

@_cdecl("blazedb_bridge_smoke")
public func blazedb_bridge_smoke(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?
) -> Int32 {
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let url = URL(fileURLWithPath: path)

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
        let db = try BlazeDBClient.open(at: url, password: pass)
        defer { try? db.close() }

        var token: ObserverToken? = db.observe { _ in counter.bump() }
        defer {
            token?.invalidate()
            token = nil
        }

        let todo = Todo(title: "android-bridge-smoke")
        try db.put(todo)

        let loaded: Todo? = try db.get("todo:\(todo.id.uuidString)")
        guard loaded?.title == todo.title else { return -2 }

        let all: [Todo] = try db.query("todo").all()
        guard all.contains(where: { $0.id == todo.id }) else { return -3 }

        try db.put(Todo(title: "observe-trigger"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard counter.count >= 1 else { return -4 }

        return Int32(all.count)
    } catch {
        return -1
    }
}

@_cdecl("blazedb_bridge_live_query_start")
public func blazedb_bridge_live_query_start(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?,
    _ callback: blazedb_bridge_live_query_cb?,
    _ userData: UnsafeMutableRawPointer?
) -> Int64 {
    guard let callback else { return -1 }
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let url = URL(fileURLWithPath: path)
        let db = try BlazeDBClient.open(at: url, password: pass)

        let live = BlazeLiveQuery<Todo>(
            db: db,
            where: "isDone",
            equals: .bool(false),
            sortBy: "title",
            descending: false
        )
        live.onResults = { result in
            switch result {
            case .success(let rows):
                let json = encodeTodos(rows)
                json.withCString { cstr in
                    callback(cstr, userData)
                }
            case .failure(let error):
                let message = "{\"error\":\"\(error.localizedDescription)\"}"
                message.withCString { cstr in
                    callback(cstr, userData)
                }
            }
        }
        live.start()

        let slot = LiveQuerySlot(db: db, query: live)
        return liveQueryRegistry.insert(slot)
    } catch {
        return -1
    }
}

@_cdecl("blazedb_bridge_live_query_stop")
public func blazedb_bridge_live_query_stop(_ handle: Int64) {
    guard handle > 0 else { return }
    liveQueryRegistry.remove(handle)
}
