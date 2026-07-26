import Foundation
import Dispatch
import BlazeDBCore

private enum CLIO {
    static func die(
        _ message: String,
        code: Int32 = EXIT_FAILURE
    ) -> Never {
        let line = message.hasSuffix("\n")
            ? message
            : message + "\n"

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

// MARK: - Application scope
//
// Equivalent to something like:
//
// AppDatabase.shared
//     +
// .blazeDBEnvironment(...)

@MainActor
enum AppDatabase {
    private static var client: BlazeDBClient?

    static func open(
        at url: URL,
        password: String
    ) throws -> BlazeDBClient {
        if let existing = client,
           !existing.isClosed {
            return existing
        }

        let openedClient = try BlazeDBClient.open(
            at: url,
            password: password
        )

        client = openedClient
        return openedClient
    }

    static func shutdown() throws {
        try client?.close()
        client = nil
    }
}

// MARK: - Repository
//
// Handles writes and typed reads.
// Observation remains in the view model through BlazeLiveQuery.

final class TodoRepository {
    private let db: BlazeDBClient

    init(db: BlazeDBClient) {
        self.db = db
    }

    func fetchOpenTodos() throws -> [Todo] {
        try db.query("todo")
            .where(
                "isDone",
                equals: .bool(false)
            )
            .orderBy(
                "title",
                descending: false
            )
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

// MARK: - View model
//
// BlazeLiveQuery performs:
//
// observe
//     → refresh
//     → decode
//
// This example intentionally has no SwiftUI dependency.

@MainActor
final class TodoListViewModel {
    private(set) var todos: [Todo] = []
    private(set) var errorMessage: String?

    private let repository: TodoRepository
    private var liveQuery: BlazeLiveQuery<Todo>?

    init(
        db: BlazeDBClient,
        repository: TodoRepository
    ) {
        self.repository = repository

        let query = BlazeLiveQuery<Todo>(
            db: db,
            where: "isDone",
            equals: .bool(false),
            sortBy: "title",
            descending: false
        )

        query.onResults = { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let rows):
                self.todos = rows
                self.errorMessage = nil

            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }

        liveQuery = query
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

// MARK: - Proof run
//
// No UI. This prints the state transitions produced by the
// repository, view model, and live-query observation.

@MainActor
enum MVVMPatternDemo {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blazedb-mvvm-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let databaseURL = directory
            .appendingPathComponent("todos.blazedb")

        let db = try AppDatabase.open(
            at: databaseURL,
            password: "MVVMPass123!"
        )

        let repository = TodoRepository(db: db)

        let viewModel = TodoListViewModel(
            db: db,
            repository: repository
        )

        viewModel.start()

        defer {
            viewModel.stop()
            try? AppDatabase.shutdown()
        }

        waitForObserverPump()

        print(
            "todos (initial): \(viewModel.todos.count)"
        )

        viewModel.addTodo(
            title: "Buy milk"
        )

        waitForObserverPump()

        print(
            """
            todos (after add): \(viewModel.todos.count) — \
            \(viewModel.todos.first?.title ?? "-")
            """
        )

        if let firstTodo = viewModel.todos.first {
            try repository.markDone(firstTodo)
            waitForObserverPump()
        }

        print(
            "todos (after done): \(viewModel.todos.count)"
        )

        print("mvvm-pattern: ok")
    }

    /// `db.observe` batches for roughly 50 ms and delivers
    /// through the main queue in `ChangeObservation.swift`.
    private static func waitForObserverPump() {
        RunLoop.main.run(
            until: Date().addingTimeInterval(0.15)
        )
    }
}

// MARK: - Entry point
//
// This file is named main.swift, so top-level code is the entry point.
// Do not add an @main declaration to this target.

Task { @MainActor in
    do {
        try MVVMPatternDemo.run()
        exit(EXIT_SUCCESS)
    } catch {
        CLIO.die("Error: \(error)")
    }
}

dispatchMain()
