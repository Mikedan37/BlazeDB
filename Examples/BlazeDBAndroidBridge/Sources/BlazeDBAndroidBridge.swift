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
    private let lock = NSLock()
    private var cancelled = false

#if os(Android)
    // BlazeLiveQuery and ChangeNotificationManager deliver on DispatchQueue.main, which
    // is not pumped from JNI on Android. Poll on a background queue instead (bridge-only).
    private let callback: blazedb_bridge_live_query_cb
    private let userData: UnsafeMutableRawPointer?

    init(
        db: BlazeDBClient,
        callback: blazedb_bridge_live_query_cb,
        userData: UnsafeMutableRawPointer?
    ) {
        self.db = db
        self.callback = callback
        self.userData = userData
        emitCurrent()
        startPolling()
    }

    private func queryOpenTodos() throws -> [Todo] {
        try db.query("todo")
            .where("isDone", equals: .bool(false))
            .orderBy("title", descending: false)
            .all()
    }

    private func emitCurrent() {
        do {
            let json = encodeTodos(try queryOpenTodos())
            json.withCString { cstr in
                callback(cstr, userData)
            }
        } catch {
            let message = "{\"error\":\"\(error.localizedDescription)\"}"
            message.withCString { cstr in
                callback(cstr, userData)
            }
        }
    }

    private func startPolling() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self {
                self.lock.lock()
                let stop = self.cancelled
                self.lock.unlock()
                if stop { return }
                Thread.sleep(forTimeInterval: 0.25)
                self.lock.lock()
                let stillRunning = !self.cancelled
                self.lock.unlock()
                if !stillRunning { return }
                self.emitCurrent()
            }
        }
    }

    func stop() {
        lock.lock()
        cancelled = true
        lock.unlock()
        try? db.close()
    }
#else
    let query: BlazeLiveQuery<Todo>

    init(db: BlazeDBClient, query: BlazeLiveQuery<Todo>) {
        self.db = db
        self.query = query
    }

    func stop() {
        query.stop()
        try? db.close()
    }
#endif
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

private func databaseURL(from path: String) -> URL {
#if os(Android) || os(Linux)
    return URL(filePath: path, directoryHint: .notDirectory)
#else
    return URL(fileURLWithPath: path, isDirectory: false)
#endif
}

@_cdecl("blazedb_bridge_smoke")
public func blazedb_bridge_smoke(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?
) -> Int32 {
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let url = databaseURL(from: path)

        let db = try BlazeDBClient.open(at: url, password: pass)
        defer { try? db.close() }

#if !os(Android)
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
        var token: ObserverToken? = db.observe { _ in counter.bump() }
        defer {
            token?.invalidate()
            token = nil
        }
#endif

        let todo = Todo(title: "android-bridge-smoke")
        try db.put(todo)

        let loaded: Todo? = try db.get("todo:\(todo.id.uuidString)")
        guard loaded?.title == todo.title else { return -2 }

        let all: [Todo] = try db.query("todo").all()
        guard all.contains(where: { $0.id == todo.id }) else { return -3 }

#if os(Android)
        // JNI smoke runs without a SwiftUI/main run loop; CRUD is sufficient runtime proof.
        // Live-query observation is covered by BlazeLiveQueryTests on the host core path.
        return Int32(all.count)
#else
        try db.put(Todo(title: "observe-trigger"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard counter.count >= 1 else { return -4 }

        return Int32(all.count)
#endif
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
        let url = databaseURL(from: path)
        let db = try BlazeDBClient.open(at: url, password: pass)

#if os(Android)
        let slot = LiveQuerySlot(db: db, callback: callback, userData: userData)
        return liveQueryRegistry.insert(slot)
#else
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
#endif
    } catch {
        return -1
    }
}

@_cdecl("blazedb_bridge_live_query_stop")
public func blazedb_bridge_live_query_stop(_ handle: Int64) {
    guard handle > 0 else { return }
    liveQueryRegistry.remove(handle)
}

@_cdecl("blazedb_bridge_add_todo")
public func blazedb_bridge_add_todo(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?,
    _ title: UnsafePointer<CChar>?
) -> Int32 {
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let titleText = try cString(title)
        let url = databaseURL(from: path)
        let db = try BlazeDBClient.open(at: url, password: pass)
        defer { try? db.close() }
        try db.put(Todo(title: titleText))
        return 1
    } catch {
        return -1
    }
}

@_cdecl("blazedb_bridge_mark_todo_done")
public func blazedb_bridge_mark_todo_done(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?,
    _ todoID: UnsafePointer<CChar>?
) -> Int32 {
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let idText = try cString(todoID)
        guard let uuid = UUID(uuidString: idText) else { return -2 }
        let url = databaseURL(from: path)
        let db = try BlazeDBClient.open(at: url, password: pass)
        defer { try? db.close() }
        guard var todo: Todo = try db.get("todo:\(uuid.uuidString)") else { return -3 }
        todo.isDone = true
        try db.put(todo)
        return 0
    } catch {
        return -1
    }
}

// MARK: - KMM session API

private final class DBSession: @unchecked Sendable {
    let db: BlazeDBClient

    init(db: BlazeDBClient) {
        self.db = db
    }
}

private final class SessionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: Int64 = 1
    private var sessions: [Int64: DBSession] = [:]

    func insert(_ session: DBSession) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        sessions[id] = session
        return id
    }

    func get(_ id: Int64) -> DBSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[id]
    }

    func remove(_ id: Int64) {
        lock.lock()
        defer { lock.unlock() }
        if let session = sessions[id] {
            try? session.db.close()
        }
        sessions.removeValue(forKey: id)
    }
}

private let sessionRegistry = SessionRegistry()

private func jsonField(from value: Any) -> BlazeDocumentField? {
    switch value {
    case let s as String:
        if let uuid = UUID(uuidString: s) { return .uuid(uuid) }
        return .string(s)
    case let b as Bool:
        return .bool(b)
    case let i as Int:
        return .int(i)
    case let d as Double:
        return .double(d)
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        }
        if floor(n.doubleValue) == n.doubleValue {
            return .int(n.intValue)
        }
        return .double(n.doubleValue)
    default:
        return nil
    }
}

private func jsonValue(from field: BlazeDocumentField) -> Any {
    switch field {
    case .string(let v): return v
    case .int(let v): return v
    case .double(let v): return v
    case .bool(let v): return v
    case .uuid(let v): return v.uuidString
    case .date(let v): return v.timeIntervalSinceReferenceDate
    case .data(let v): return v.base64EncodedString()
    case .array(let v): return v.map { jsonValue(from: $0) }
    case .dictionary(let v):
        var dict: [String: Any] = [:]
        for (k, f) in v { dict[k] = jsonValue(from: f) }
        return dict
    case .vector, .null:
        return NSNull()
    }
}

private func recordToJSON(_ record: BlazeDataRecord) -> String {
    var dict: [String: Any] = [:]
    for (key, field) in record.storage {
        dict[key] = jsonValue(from: field)
    }
    guard JSONSerialization.isValidJSONObject(dict),
          let data = try? JSONSerialization.data(withJSONObject: dict),
          let json = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return json
}

private func recordsToJSONArray(_ records: [BlazeDataRecord]) -> String {
    let payload = records.map { record -> [String: Any] in
        var dict: [String: Any] = [:]
        for (key, field) in record.storage {
            dict[key] = jsonValue(from: field)
        }
        return dict
    }
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8)
    else {
        return "[]"
    }
    return json
}

private func duplicateCString(_ string: String) -> UnsafeMutablePointer<CChar>? {
    string.withCString { cstr in
        guard let copy = strdup(cstr) else { return nil }
        return copy
    }
}

@_cdecl("blazedb_bridge_open")
public func blazedb_bridge_open(
    _ dbPath: UnsafePointer<CChar>?,
    _ password: UnsafePointer<CChar>?
) -> Int64 {
    do {
        let path = try cString(dbPath)
        let pass = try cString(password)
        let url = databaseURL(from: path)
        let db = try BlazeDBClient.open(at: url, password: pass)
        return sessionRegistry.insert(DBSession(db: db))
    } catch {
        return -1
    }
}

@_cdecl("blazedb_bridge_close")
public func blazedb_bridge_close(_ handle: Int64) {
    guard handle > 0 else { return }
    sessionRegistry.remove(handle)
}

@_cdecl("blazedb_bridge_put_json")
public func blazedb_bridge_put_json(
    _ handle: Int64,
    _ kind: UnsafePointer<CChar>?,
    _ json: UnsafePointer<CChar>?
) -> Int32 {
    guard let session = sessionRegistry.get(handle) else { return -1 }
    do {
        let kindText = try cString(kind).lowercased()
        let jsonText = try cString(json)
        guard let data = jsonText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return -2 }

        var storage: [String: BlazeDocumentField] = [:]
        for (key, value) in object {
            guard let field = jsonField(from: value) else { return -3 }
            storage[key] = field
        }
        storage[BlazeRecordKind.storageKey] = .string(kindText)
        _ = try session.db.insert(BlazeDataRecord(storage))
        return 0
    } catch {
        return -1
    }
}

private func parseStorageKey(_ key: String) throws -> (namespace: String?, id: UUID) {
    if let colon = key.firstIndex(of: ":") {
        let namespace = String(key[..<colon])
        let idPart = String(key[key.index(after: colon)...])
        guard let id = UUID(uuidString: idPart) else { throw BridgeError.invalidPath }
        return (namespace, id)
    }
    guard let id = UUID(uuidString: key) else { throw BridgeError.invalidPath }
    return (nil, id)
}

@_cdecl("blazedb_bridge_get_json")
public func blazedb_bridge_get_json(
    _ handle: Int64,
    _ key: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let session = sessionRegistry.get(handle) else { return nil }
    do {
        let keyText = try cString(key)
        let (namespace, id) = try parseStorageKey(keyText)
        guard let record = try session.db.fetch(id: id) else { return nil }
        if let namespace {
            let want = namespace.lowercased()
            if let have = record.storage[BlazeRecordKind.storageKey]?.stringValue?.lowercased(), have != want {
                return nil
            }
        }
        return duplicateCString(recordToJSON(record))
    } catch {
        return nil
    }
}

@_cdecl("blazedb_bridge_query_json")
public func blazedb_bridge_query_json(
    _ handle: Int64,
    _ kind: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let session = sessionRegistry.get(handle) else { return nil }
    do {
        let kindText = try cString(kind)
        let norm = kindText.lowercased()
        let records = try session.db.fetchAll().filter {
            BlazeRecordKind.recordMatchesNamespace($0, normalizedNamespace: norm)
        }
        return duplicateCString(recordsToJSONArray(records))
    } catch {
        return duplicateCString("[]")
    }
}

@_cdecl("blazedb_bridge_free_string")
public func blazedb_bridge_free_string(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}
