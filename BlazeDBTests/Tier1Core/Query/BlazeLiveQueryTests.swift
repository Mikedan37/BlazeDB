import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

/// Focused validation for ``BlazeLiveQuery`` — observe → refresh → typed decode.
/// Does not re-test ``BlazeDBClient/observe(_:)`` (see Tier1Perf ``ChangeObservationTests``)
/// or SwiftUI observers (``BlazeQueryObservationIntegrationTests``).
final class BlazeLiveQueryTests: LinuxTier1NonCryptoKDFHarness {

    struct LiveTask: BlazeStorable, Equatable {
        var id: UUID = UUID()
        var title: String
        var isDone: Bool = false
    }

    private var db: BlazeDBClient!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlazeLiveQuery-\(UUID().uuidString).blazedb")
        db = try! BlazeDBClient(
            name: "BlazeLiveQueryTests",
            fileURL: tempURL,
            password: "LiveQuery-Test-2026A!"
        )
    }

    override func tearDown() {
        try? db.close()
        db = nil
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: - Helpers

    /// Thread-safe capture for observer callbacks (delivered on main queue).
    private final class ThreadSafeBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        var current: T {
            get {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
            set {
                lock.lock()
                value = newValue
                lock.unlock()
            }
        }
    }

    private func manualOpenTasks() throws -> [LiveTask] {
        try db.query("livetask")
            .where("isDone", equals: .bool(false))
            .orderBy("title", descending: false)
            .all()
    }

    /// ``ChangeNotificationManager`` batches ~50ms and delivers on the main queue.
    private func pumpObserverDelivery() {
        let deadline = Date().addingTimeInterval(0.15)
        let pump = {
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        if Thread.isMainThread {
            pump()
        } else {
            DispatchQueue.main.sync(execute: pump)
        }
    }

    private func waitForLiveResults(
        live: BlazeLiveQuery<LiveTask>,
        latest: ThreadSafeBox<[LiveTask]>,
        timeout: TimeInterval = 1.0
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            pumpObserverDelivery()
            let expected = try manualOpenTasks()
            if latest.current == expected {
                return
            }
        }
        live.refresh()
        pumpObserverDelivery()
        let expected = try manualOpenTasks()
        XCTAssertEqual(latest.current, expected)
    }

    private func makeLiveQuery() -> BlazeLiveQuery<LiveTask> {
        BlazeLiveQuery(
            db: db,
            where: "isDone",
            equals: .bool(false),
            sortBy: "title",
            descending: false
        )
    }

    // MARK: - Lifecycle

    func testInitialRefreshOnStartIsEmpty() throws {
        var latest: [LiveTask]?
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result {
                latest = rows
            }
        }
        live.start()
        defer { live.stop() }

        XCTAssertEqual(latest ?? [], [])
        XCTAssertEqual(try manualOpenTasks(), [])
    }

    func testStopIsIdempotent() throws {
        let live = makeLiveQuery()
        live.start()
        live.stop()
        live.stop()
        XCTAssertNoThrow(live.stop())
    }

    func testStartRegistersExactlyOneObserver() throws {
        let live = makeLiveQuery()
        live.start()
        defer { live.stop() }

        let afterFirstStart = ChangeNotificationManager.shared.observerCount
        live.start()
        let afterSecondStart = ChangeNotificationManager.shared.observerCount

        XCTAssertEqual(afterFirstStart, 1)
        XCTAssertEqual(afterSecondStart, 1, "start() should replace, not accumulate observers")
    }

    func testDeinitUnregistersObserver() throws {
        var deliveryCount = 0
        do {
            let live = makeLiveQuery()
            live.onResults = { _ in deliveryCount += 1 }
            live.start()
        }

        XCTAssertEqual(deliveryCount, 1, "Initial refresh from start()")

        try db.put(LiveTask(title: "after deinit"))
        pumpObserverDelivery()

        XCTAssertEqual(deliveryCount, 1, "Deallocated live query must not receive observer callbacks")
    }

    func testStopSuppressesObserverRefresh() throws {
        var deliveryCount = 0
        let live = makeLiveQuery()
        live.onResults = { _ in deliveryCount += 1 }
        live.start()
        XCTAssertEqual(deliveryCount, 1)

        live.stop()
        try db.put(LiveTask(title: "ignored"))
        pumpObserverDelivery()

        XCTAssertEqual(deliveryCount, 1, "stop() should unregister observer")
    }

    // MARK: - Observation → refresh

    func testInsertTriggersRefreshMatchingManualQuery() throws {
        var latest: [LiveTask] = []
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result { latest = rows }
        }
        live.start()
        defer { live.stop() }

        let task = LiveTask(title: "alpha")
        try db.put(task)
        pumpObserverDelivery()

        XCTAssertEqual(latest, try manualOpenTasks())
        XCTAssertEqual(latest.map(\.title), ["alpha"])
    }

    func testUpdateTriggersRefreshMatchingManualQuery() throws {
        var latest: [LiveTask] = []
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result { latest = rows }
        }
        live.start()
        defer { live.stop() }

        var task = LiveTask(title: "todo")
        try db.put(task)
        pumpObserverDelivery()

        task.isDone = true
        try db.put(task)
        pumpObserverDelivery()

        XCTAssertEqual(latest, try manualOpenTasks())
        XCTAssertTrue(latest.isEmpty)
    }

    func testDeleteTriggersRefreshMatchingManualQuery() throws {
        var latest: [LiveTask] = []
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result { latest = rows }
        }
        live.start()
        defer { live.stop() }

        let task = LiveTask(title: "gone")
        try db.put(task)
        pumpObserverDelivery()
        XCTAssertEqual(latest.count, 1)

        try db.delete(id: task.id)
        pumpObserverDelivery()

        XCTAssertEqual(latest, try manualOpenTasks())
        XCTAssertTrue(latest.isEmpty)
    }

    func testFilteredQueryExcludesCompletedTasks() throws {
        var latest: [LiveTask] = []
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result { latest = rows }
        }
        live.start()
        defer { live.stop() }

        try db.put(LiveTask(title: "open", isDone: false))
        try db.put(LiveTask(title: "closed", isDone: true))
        pumpObserverDelivery()

        XCTAssertEqual(latest.map(\.title), ["open"])
        XCTAssertEqual(latest, try manualOpenTasks())
    }

    // MARK: - Safety

    func testCloseDatabaseAfterStopIsSafe() throws {
        let live = makeLiveQuery()
        live.onResults = { _ in }
        live.start()
        live.stop()
        try db.close()
        XCTAssertTrue(db.isClosed)
    }

    // MARK: - Stress (single randomized sync check)

    func testRandomOperationsStayConsistentWithManualQuery() throws {
        let latest = ThreadSafeBox<[LiveTask]>([])
        let live = makeLiveQuery()
        live.onResults = { result in
            if case .success(let rows) = result { latest.current = rows }
        }
        live.start()
        defer { live.stop() }

        var stored: [LiveTask] = []
        var rng = SeededRNG(seed: 0xB1A2E)

        for _ in 0..<150 {
            switch rng.nextInt(3) {
            case 0:
                let task = LiveTask(title: "t-\(stored.count)-\(rng.nextInt(10_000))")
                try db.put(task)
                stored.append(task)
            case 1 where !stored.isEmpty:
                let index = rng.nextInt(stored.count)
                stored[index].isDone.toggle()
                try db.put(stored[index])
            case 2 where !stored.isEmpty:
                let index = rng.nextInt(stored.count)
                let removed = stored.remove(at: index)
                try db.delete(id: removed.id)
            default:
                continue
            }

            try waitForLiveResults(live: live, latest: latest)
        }
    }
}

// MARK: - Deterministic RNG for stress test

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        state = state &* 6_364_136_223_846_793 &+ 1
        return Int(state % UInt64(upperBound))
    }
}
