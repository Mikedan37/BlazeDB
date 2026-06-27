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

// MARK: - Model

struct Todo: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

// MARK: - Application scope (equivalent to AppDatabase.shared + .blazeDBEnvironment)

@MainActor
enum AppDatabase {
    private static var _client: BlazeDBClient?

    static func open(at url: URL, password: String) throws -> BlazeDBClient {
        if let existing = _client, !existing.isClosed {
            return existing
        }
        let client = try BlazeDBClient.open(at: url, password: password)
        _client = client
        return client
    }

    static func shutdown() throws {
        try _client?.close()
        _client = nil
    }
}

// MARK: - Repository (writes + typed reads; observation lives in ViewModel via BlazeLiveQuery)

final class TodoRepository {
    private let db: BlazeDBClient

    init(db: BlazeDBClient) {
        self.db = db
    }

    func fetchOpenTodos() throws -> [Todo] {
        try db.query("todo")
            .where("isDone", equals: .bool(false))
            .orderBy("title", descending: false)
            .all()
    }

    @discardableResult
    func addTodo(title: String) throws -> Todo {
        let todo = Todo(title: title)
        try db.put(todo)
        return todo
    }

    func markDone(_ todo: Todo) throws {
        var updated = todo
        updated.isDone = true
        try db.put(updated)
    }
}

// MARK: - ViewModel (BlazeLiveQuery = observe → refresh → decode; no SwiftUI)

@MainActor
final class TodoListViewModel {
    private(set) var todos: [Todo] = []
    private(set) var errorMessage: String?

    private let repository: TodoRepository
    private var liveQuery: BlazeLiveQuery<Todo>?

    init(db: BlazeDBClient, repository: TodoRepository) {
        self.repository = repository
        let query = BlazeLiveQuery<Todo>(
            db: db,
            where: "isDone",
            equals: .bool(false),
            sortBy: "title",
            descending: false
        )
        query.onResults = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let rows):
                self.todos = rows
                self.errorMessage = nil
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
        self.liveQuery = query
    }

    func start() {
        liveQuery?.start()
    }

    func stop() {
        liveQuery?.stop()
        liveQuery = nil
    }

    func addTodo(title: String) {
        do {
            try repository.addTodo(title: title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Proof run (no UI — prints state transitions)

@MainActor
enum MVVMPatternDemo {
    static func run() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazedb-mvvm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let db = try AppDatabase.open(
            at: dir.appendingPathComponent("todos.blazedb"),
            password: "MVVMPass123!"
        )

        let repository = TodoRepository(db: db)
        let viewModel = TodoListViewModel(db: db, repository: repository)

        viewModel.start()
        defer {
            viewModel.stop()
            try? AppDatabase.shutdown()
        }

        waitForObserverPump()
        print("todos (initial): \(viewModel.todos.count)")

        viewModel.addTodo(title: "Buy milk")
        waitForObserverPump()

        print("todos (after add): \(viewModel.todos.count) — \(viewModel.todos.first?.title ?? "-")")

        if let first = viewModel.todos.first {
            try repository.markDone(first)
            waitForObserverPump()
        }

        print("todos (after done): \(viewModel.todos.count)")
        print("mvvm-pattern: ok")
    }

    /// `db.observe` batches ~50ms and delivers on the main queue (`ChangeObservation.swift`).
    private static func waitForObserverPump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
}

@main
enum MVVMPatternEntry {
    static func main() {
        do {
            try MVVMPatternDemo.run()
        } catch {
            CLIO.die("Error: \(error)")
        }
    }
}
