import XCTest
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import BlazeCLICore

private final class HitCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var snapshot: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

final class CLIRegistryTests: XCTestCase {
    func testMRURecordOpen() {
        var reg = CLIRegistry()
        reg.recordSuccessfulOpen(path: "/a/x.blazedb")
        reg.recordSuccessfulOpen(path: "/b/y.blazedb")
        reg.recordSuccessfulOpen(path: "/a/x.blazedb")
        XCTAssertEqual(reg.recents.count, 2)
        XCTAssertEqual(reg.recents[0].path, "/a/x.blazedb")
        XCTAssertEqual(reg.recents[1].path, "/b/y.blazedb")
    }

    func testMRUCap() {
        var reg = CLIRegistry()
        for i in 0..<30 {
            reg.recordSuccessfulOpen(path: "/db\(i).blazedb")
        }
        XCTAssertEqual(reg.recents.count, CLIRegistry.maxRecents)
        XCTAssertEqual(reg.recents[0].path, "/db29.blazedb")
    }

    func testBookmarks() {
        var reg = CLIRegistry()
        reg.addBookmark(path: "/p/a.blazedb")
        reg.addBookmark(path: "/p/a.blazedb")
        XCTAssertEqual(reg.bookmarks.count, 1)
        reg.removeBookmark(path: "/p/a.blazedb")
        XCTAssertTrue(reg.bookmarks.isEmpty)
    }
}

final class CLIDiscoveryTests: XCTestCase {
    func testPageSliceAndNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("picker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 0..<12 {
            let u = dir.appendingPathComponent("db\(i).blazedb")
            try Data([1]).write(to: u)
            urls.append(u)
        }
        let sorted = CLIDiscovery.sortByNewestFirst(urls)
        XCTAssertEqual(sorted.count, 12)

        let (p0, info0) = CLIDiscovery.pageSlice(sorted, query: PickerQuery(page: 0, pageSize: 10))
        XCTAssertEqual(p0.count, 10)
        XCTAssertEqual(info0.pageCount, 2)
        XCTAssertEqual(info0.rangeEnd, 10)

        let (p1, info1) = CLIDiscovery.pageSlice(sorted, query: PickerQuery(page: 1, pageSize: 10))
        XCTAssertEqual(p1.count, 2)
        XCTAssertEqual(info1.rangeStart, 11)
    }

    func testNoiseFilterHidesTestShards() {
        let urls = [
            URL(fileURLWithPath: "/tmp/daemontest-ABC.blazedb"),
            URL(fileURLWithPath: "/tmp/real.blazedb"),
        ]
        let reg = CLIRegistry()
        let visible = CLIDiscovery.applyFilters(
            urls: urls,
            registry: reg,
            query: PickerQuery(hideNoiseFiles: true)
        )
        XCTAssertEqual(visible.map(\.lastPathComponent), ["real.blazedb"])
    }

    func testPickerRenderColumnsAlign() throws {
        let row = PickerRow(
            url: URL(fileURLWithPath: "/Users/me/proj/foo.blazedb"),
            section: .found,
            isRecent: true,
            isBookmarked: false,
            isLocked: true,
            subtitle: "",
            sizeLabel: "1.5 MB",
            modifiedLabel: "2h ago"
        )
        let snap = PickerSnapshot(
            lines: [.row(row)],
            selectableIndices: [0],
            pageInfo: PickerPageInfo(page: 0, pageCount: 1, total: 1, rangeStart: 1, rangeEnd: 1)
        )
        let frame = CLIPickerRender.renderFrame(
            CLIPickerRender.FrameInput(snapshot: snap, selection: 0)
        )
        let dataLine = frame.split(separator: "\n").first { $0.hasPrefix("  >") || $0.hasPrefix("  ") && $0.contains("foo.blazedb") }
        XCTAssertNotNil(dataLine)
        XCTAssertFalse(frame.contains("\u{1b}["), "picker frame must be plain text")
    }

    func testApplyFilters() {
        let reg = CLIRegistry(bookmarks: ["/tmp/a.blazedb"])
        let urls = [
            URL(fileURLWithPath: "/tmp/a.blazedb"),
            URL(fileURLWithPath: "/tmp/other.blazedb"),
        ]
        let byName = CLIDiscovery.applyFilters(
            urls: urls,
            registry: reg,
            query: PickerQuery(filterText: "other")
        )
        XCTAssertEqual(byName.map(\.lastPathComponent), ["other.blazedb"])

        let bookmarked = CLIDiscovery.applyFilters(
            urls: urls,
            registry: reg,
            query: PickerQuery(bookmarkedOnly: true)
        )
        XCTAssertEqual(bookmarked.map(\.lastPathComponent), ["a.blazedb"])
    }

    func testMergeFoundExcludesRecents() {
        let r1 = URL(fileURLWithPath: "/tmp/one.blazedb")
        let r2 = URL(fileURLWithPath: "/tmp/two.blazedb")
        let reg = CLIRegistry(recents: [CLIRegistryRecentEntry(path: r1.path)])
        let merged = CLIDiscovery.mergeFoundDistinct([r1, r2], [], registry: reg)
        XCTAssertEqual(merged.map(\.path), [r2.path])
    }

    func testHomeScannerSkipsExcludedDirs() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let nm = home.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        let hiddenDb = nm.appendingPathComponent("bad.blazedb")
        try Data([1]).write(to: hiddenDb)

        let goodDir = home.appendingPathComponent("proj", isDirectory: true)
        try FileManager.default.createDirectory(at: goodDir, withIntermediateDirectories: true)
        let goodDb = goodDir.appendingPathComponent("good.blazedb")
        try Data([1]).write(to: goodDb)

        let exp = expectation(description: "scan")
        let collector = HitCollector()
        let cfg = CLIHomeScannerConfig(maxHits: 50, timeBudget: 5)
        CLIHomeScanner.scan(home: home, config: cfg, onHit: { url in
            collector.append(url)
        }, completion: {
            exp.fulfill()
        })
        wait(for: [exp], timeout: 10)
        XCTAssertEqual(collector.snapshot.map(\.lastPathComponent), ["good.blazedb"])
    }
}

final class BlazedbPickerInputTests: XCTestCase {
    #if os(macOS) || os(Linux)
    func testReadByteReadsAvailableByte() throws {
        var fds = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fds), 0)
        let readFD = fds[0]
        let writeFD = fds[1]
        defer {
            close(readFD)
            close(writeFD)
        }

        var byte = UInt8(ascii: "q")
        let written = withUnsafeBytes(of: byte) { buffer in
            write(writeFD, buffer.baseAddress, buffer.count)
        }
        XCTAssertEqual(written, 1)

        let read = try BlazedbPicker.readByte(timeoutMs: 100, fd: readFD)
        XCTAssertEqual(read, byte)
    }

    func testReadByteThrowsCancelledOnEOF() throws {
        var fds = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fds), 0)
        let readFD = fds[0]
        let writeFD = fds[1]
        close(writeFD)
        defer { close(readFD) }

        XCTAssertThrowsError(try BlazedbPicker.readByte(timeoutMs: 100, fd: readFD)) { error in
            XCTAssertEqual(error as? CLIError, .cancelled)
        }
    }
    #endif
}

final class CLIMasterKeyringTests: XCTestCase {
    func testMasterKeyringInitRejectsWeakPassphrase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("master-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyringPath = dir.appendingPathComponent("keyring.json.enc").path
        setenv("BLAZEDB_MASTER_KEYRING_PATH", keyringPath, 1)
        defer {
            unsetenv("BLAZEDB_MASTER_KEYRING_PATH")
            try? FileManager.default.removeItem(at: dir)
        }

        XCTAssertThrowsError(try CLIMasterKeyringStore.initialize(passphrase: "1234"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyringPath))
    }

    func testResolveSecretReturnsNilWhenKeyringIsNotInitialized() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("master-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyringPath = dir.appendingPathComponent("keyring.json.enc").path
        setenv("BLAZEDB_MASTER_KEYRING_PATH", keyringPath, 1)
        defer {
            unsetenv("BLAZEDB_MASTER_KEYRING_PATH")
            try? FileManager.default.removeItem(at: dir)
        }

        XCTAssertFalse(try CLIMasterKeyringStore.status().exists)
        let resolved = try CLIMasterKeyringStore.resolveSecret(
            passphrase: "VeryStrongMasterPassphrase_123!",
            dbPath: "/tmp/missing.blazedb"
        )
        XCTAssertNil(resolved)
    }

    func testMasterKeyringInitStatusAndDecrypt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("master-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyringPath = dir.appendingPathComponent("keyring.json.enc").path
        setenv("BLAZEDB_MASTER_KEYRING_PATH", keyringPath, 1)
        defer { unsetenv("BLAZEDB_MASTER_KEYRING_PATH") }

        let pre = try CLIMasterKeyringStore.status()
        XCTAssertFalse(pre.exists)

        let status = try CLIMasterKeyringStore.initialize(passphrase: "VeryStrongMasterPassphrase_123!")
        XCTAssertTrue(status.exists)
        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertEqual(status.kdfAlgorithm, "argon2id")

        let payload = try CLIMasterKeyringStore.loadPayload(passphrase: "VeryStrongMasterPassphrase_123!")
        XCTAssertTrue(payload.databases.isEmpty)

        XCTAssertThrowsError(try CLIMasterKeyringStore.loadPayload(passphrase: "wrong-passphrase"))
    }

    func testMasterAddListResolveRemovePersistent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("master-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyringPath = dir.appendingPathComponent("keyring.json.enc").path
        setenv("BLAZEDB_MASTER_KEYRING_PATH", keyringPath, 1)
        defer { unsetenv("BLAZEDB_MASTER_KEYRING_PATH") }

        _ = try CLIMasterKeyringStore.initialize(passphrase: "MasterPassphrase_For_Test_123!")
        let entry = try CLIMasterKeyringStore.addEntry(
            passphrase: "MasterPassphrase_For_Test_123!",
            dbPath: "/tmp/foo.blazedb",
            dbSecret: "SuperSecretDBPassword!",
            scope: .persistent,
            label: "Foo"
        )
        XCTAssertEqual(entry.scope, .persistent)

        let listed = try CLIMasterKeyringStore.listEntries(passphrase: "MasterPassphrase_For_Test_123!")
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].label, "Foo")

        let resolved = try CLIMasterKeyringStore.resolveSecret(
            passphrase: "MasterPassphrase_For_Test_123!",
            dbPath: "/tmp/foo.blazedb"
        )
        XCTAssertEqual(resolved, "SuperSecretDBPassword!")

        let removed = try CLIMasterKeyringStore.removeEntry(
            passphrase: "MasterPassphrase_For_Test_123!",
            dbPathOrID: "/tmp/foo.blazedb"
        )
        XCTAssertTrue(removed)
        XCTAssertEqual(try CLIMasterKeyringStore.listEntries(passphrase: "MasterPassphrase_For_Test_123!").count, 0)
    }

    func testConcurrentPersistentAddsPreserveAllEntries() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("master-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyringPath = dir.appendingPathComponent("keyring.json.enc").path
        setenv("BLAZEDB_MASTER_KEYRING_PATH", keyringPath, 1)
        defer { unsetenv("BLAZEDB_MASTER_KEYRING_PATH") }

        let passphrase = "MasterPassphrase_For_Test_123!"
        _ = try CLIMasterKeyringStore.initialize(passphrase: passphrase)

        let workerCount = 6
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let errors = ErrorCollector()

        for index in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                do {
                    _ = try CLIMasterKeyringStore.addEntry(
                        passphrase: passphrase,
                        dbPath: dir.appendingPathComponent("db-\(index).blazedb").path,
                        dbSecret: "DBSecret_\(index)_For_Test_123!",
                        scope: .persistent,
                        label: "DB \(index)"
                    )
                } catch {
                    errors.append(String(describing: error))
                }
                group.leave()
            }
        }

        for _ in 0..<workerCount {
            start.signal()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        let capturedErrors = errors.snapshot
        XCTAssertTrue(capturedErrors.isEmpty, capturedErrors.joined(separator: "\n"))

        let listed = try CLIMasterKeyringStore.listEntries(passphrase: passphrase)
        XCTAssertEqual(listed.count, workerCount)
        for index in 0..<workerCount {
            let resolved = try CLIMasterKeyringStore.resolveSecret(
                passphrase: passphrase,
                dbPath: dir.appendingPathComponent("db-\(index).blazedb").path
            )
            XCTAssertEqual(resolved, "DBSecret_\(index)_For_Test_123!")
        }
    }
}
