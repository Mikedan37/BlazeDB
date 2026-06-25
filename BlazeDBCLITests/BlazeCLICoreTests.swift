import XCTest
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import BlazeCLICore
import BlazeDBCore

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


final class CLIDatabasePasswordResolverTests: XCTestCase {
    func testMasterModePrefersStoredSecretOverEnvAndExplicitPasswords() throws {
        var masterPromptCount = 0
        var databasePromptCount = 0
        var standardPromptCount = 0

        let resolved = try CLIDatabasePasswordResolver.resolve(
            path: "/tmp/foo.blazedb",
            masterMode: true,
            explicitPassword: "argv-secret",
            envPassword: "env-secret",
            fallbackPrompt: true,
            readMasterPassphrase: {
                masterPromptCount += 1
                return "master-passphrase"
            },
            readStandardPassword: {
                standardPromptCount += 1
                return "standard-prompt-secret"
            },
            readDatabasePassword: {
                databasePromptCount += 1
                return "database-prompt-secret"
            },
            resolveStoredSecret: { passphrase, dbPath in
                XCTAssertEqual(passphrase, "master-passphrase")
                XCTAssertEqual(dbPath, "/tmp/foo.blazedb")
                return "stored-secret"
            }
        )

        XCTAssertEqual(resolved, "stored-secret")
        XCTAssertEqual(masterPromptCount, 1)
        XCTAssertEqual(databasePromptCount, 0)
        XCTAssertEqual(standardPromptCount, 0)
    }

    func testMasterModeFallsBackToDatabasePromptInsteadOfEnvPassword() throws {
        var masterPromptCount = 0
        var databasePromptCount = 0

        let resolved = try CLIDatabasePasswordResolver.resolve(
            path: "/tmp/missing.blazedb",
            masterMode: true,
            explicitPassword: nil,
            envPassword: "env-secret",
            fallbackPrompt: true,
            readMasterPassphrase: {
                masterPromptCount += 1
                return "master-passphrase"
            },
            readStandardPassword: {
                XCTFail("regular password prompt should not be used in master mode")
                return "standard-prompt-secret"
            },
            readDatabasePassword: {
                databasePromptCount += 1
                return "database-prompt-secret"
            },
            resolveStoredSecret: { _, _ in nil }
        )

        XCTAssertEqual(resolved, "database-prompt-secret")
        XCTAssertEqual(masterPromptCount, 1)
        XCTAssertEqual(databasePromptCount, 1)
    }

    func testRegularModeUsesExplicitThenEnvironmentThenPrompt() throws {
        let explicit = try CLIDatabasePasswordResolver.resolve(
            path: "/tmp/foo.blazedb",
            masterMode: false,
            explicitPassword: "argv-secret",
            envPassword: "env-secret",
            fallbackPrompt: true,
            readMasterPassphrase: {
                XCTFail("master passphrase should not be read outside master mode")
                return "master-passphrase"
            },
            readStandardPassword: {
                XCTFail("prompt should not be used when explicit password is present")
                return "standard-prompt-secret"
            },
            readDatabasePassword: {
                XCTFail("database prompt should not be used outside master mode")
                return "database-prompt-secret"
            },
            resolveStoredSecret: { _, _ in
                XCTFail("keyring should not be consulted outside master mode")
                return nil
            }
        )
        XCTAssertEqual(explicit, "argv-secret")

        let environment = try CLIDatabasePasswordResolver.resolve(
            path: "/tmp/foo.blazedb",
            masterMode: false,
            explicitPassword: nil,
            envPassword: "env-secret",
            fallbackPrompt: true,
            readMasterPassphrase: { "master-passphrase" },
            readStandardPassword: {
                XCTFail("prompt should not be used when env password is present")
                return "standard-prompt-secret"
            },
            readDatabasePassword: { "database-prompt-secret" },
            resolveStoredSecret: { _, _ in nil }
        )
        XCTAssertEqual(environment, "env-secret")
    }
}

final class CLIProjectPasswordResolverTests: XCTestCase {
    func testResolveCandidatesFindsSwiftConfigLiteralForDBName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try " // marker ".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let dbURL = root.appendingPathComponent("users.blazedb")
        try Data().write(to: dbURL)

        let swift = """
        import BlazeDBCore
        let dbURL = URL(fileURLWithPath: "/tmp/users.blazedb")
        let db = try BlazeDBClient(name: "users", fileURL: dbURL, password: "SwiftLiteralPass_123A")
        """
        try swift.write(
            to: root.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let candidates = CLIProjectPasswordResolver.resolveCandidates(dbPath: dbURL.path)
        XCTAssertTrue(candidates.contains(where: { $0.password == "SwiftLiteralPass_123A" }))
    }

    func testResolveCandidatesFindsGenericEnvFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try " // marker ".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let dbURL = root.appendingPathComponent("orders.blazedb")
        try Data().write(to: dbURL)
        try "BLAZEDB_PASSWORD=EnvFallback_123A\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )

        let candidates = CLIProjectPasswordResolver.resolveCandidates(dbPath: dbURL.path)
        XCTAssertTrue(candidates.contains(where: { $0.password == "EnvFallback_123A" }))
    }
}

final class BlazedbReplTrustTests: XCTestCase {
    private func makeClient() throws -> BlazeDBClient {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("repl-trust-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("trust.blazedb")
        return try BlazeDBClient(name: "trust", fileURL: dbURL, password: "TrustPassword_123A")
    }

    private func insertRecord(client: BlazeDBClient, id: UUID = UUID()) throws -> UUID {
        let record = BlazeDataRecord([
            "id": .uuid(id),
            "kind": .string("test"),
            "name": .string("sample"),
        ])
        _ = try client.insert(record)
        return id
    }

    func testSoftDeleteSuccess() throws {
        let client = try makeClient()
        let id = try insertRecord(client: client)

        let output = BlazedbRepl.runSoftDelete(client: client, id: id)
        XCTAssertEqual(output, "🗑️ Soft deleted")
    }

    func testSoftDeleteFailure() throws {
        let client = try makeClient()
        try client.close()

        let output = BlazedbRepl.runSoftDelete(client: client, id: UUID())
        XCTAssertTrue(output.hasPrefix("❌ Soft delete failed:"))
    }

    func testDeleteSuccess() throws {
        let client = try makeClient()
        let id = try insertRecord(client: client)

        let output = BlazedbRepl.runDelete(client: client, id: id)
        XCTAssertEqual(output, "🗑️ Deleted record \(id)")
    }

    func testDeleteFailure() throws {
        let client = try makeClient()
        try client.close()

        let output = BlazedbRepl.runDelete(client: client, id: UUID())
        XCTAssertTrue(output.hasPrefix("❌ Delete failed:"))
    }

    func testUpdateSuccess() throws {
        let client = try makeClient()
        let id = try insertRecord(client: client)

        let output = BlazedbRepl.runUpdate(
            client: client,
            id: id,
            json: #"{"kind":"test","name":"updated"}"#
        )
        XCTAssertEqual(output, "✏️ Updated record \(id)")
    }

    func testUpdateFailure() throws {
        let client = try makeClient()
        try client.close()

        let output = BlazedbRepl.runUpdate(
            client: client,
            id: UUID(),
            json: #"{"kind":"test","name":"updated"}"#
        )
        XCTAssertTrue(output.hasPrefix("❌ Update failed:"))
    }

    func testRowIndexMissingIDShowsUnavailable() {
        let record = BlazeDataRecord([
            "kind": .string("chatmessage"),
            "text": .string("hello"),
        ])
        let display = BlazedbRepl.recordIDDisplayText(record: record, requestedID: nil)
        XCTAssertEqual(display, "<id unavailable>")
    }

    func testRowIndexNonUUIDIDShowsInvalid() {
        let record = BlazeDataRecord([
            "id": .string("not-a-uuid"),
            "kind": .string("chatmessage"),
        ])
        let display = BlazedbRepl.recordIDDisplayText(record: record, requestedID: nil)
        XCTAssertEqual(display, "<id invalid: not-a-uuid>")
    }

    func testRunShellStartupUsesSingleInitialFetchAllSourceGuard() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeShell/BlazedbRepl.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(source.contains("let initialRecords = (try? client.fetchAll()) ?? []"))
        XCTAssertTrue(source.contains("printDatabaseSnapshot(client: client, databasePath: dbPath, records: initialRecords)"))
        XCTAssertTrue(source.contains("var lastTableRecords: [BlazeDataRecord] = initialRecords"))
    }

    func testHistoryNavigationWrapsBackwardAndForward() {
        let count = 3
        XCTAssertEqual(BlazedbRepl.nextHistoryIndex(current: nil, direction: -1, count: count), 2)
        XCTAssertEqual(BlazedbRepl.nextHistoryIndex(current: 0, direction: -1, count: count), 2)
        XCTAssertEqual(BlazedbRepl.nextHistoryIndex(current: nil, direction: 1, count: count), 0)
        XCTAssertEqual(BlazedbRepl.nextHistoryIndex(current: 2, direction: 1, count: count), 0)
    }
}

final class BlazedbRLSCLITests: XCTestCase {
    private struct CLIResult {
        let status: Int32
        let output: String
    }

    private func makeDatabase() throws -> (dbURL: URL, password: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rls-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("test.blazedb")
        let password = "RLSCliPass_123A"
        let client = try BlazeDBClient(name: "rls-cli", fileURL: dbURL, password: password)
        _ = try client.insert(BlazeDataRecord([
            "id": .uuid(UUID()),
            "ownerId": .string("owner-1"),
            "teamId": .string("team-1"),
            "kind": .string("seed")
        ]))
        try client.persist()
        try client.close()
        return (dbURL, password)
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func blazedbExecutableURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["BLAZEDB_CLI_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let fallback = projectRootURL()
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("blazedb")
        guard FileManager.default.isExecutableFile(atPath: fallback.path) else {
            throw XCTSkip("blazedb executable not found at \(fallback.path). Run `swift build --product blazedb` first.")
        }
        return fallback
    }

    private func runCLI(_ args: [String], env: [String: String] = [:]) throws -> CLIResult {
        let process = Process()
        process.executableURL = try blazedbExecutableURL()
        process.arguments = args
        process.currentDirectoryURL = projectRootURL()

        var mergedEnv = ProcessInfo.processInfo.environment
        for (k, v) in env {
            mergedEnv[k] = v
        }
        process.environment = mergedEnv

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        let outputData = out.fileHandleForReading.readDataToEndOfFile()
            + err.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return CLIResult(status: process.terminationStatus, output: output)
    }

    func testRLSStatusDisabled() throws {
        let (dbURL, password) = try makeDatabase()
        let result = try runCLI(["rls", "status", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("RLS: disabled"))
        XCTAssertTrue(result.output.contains("Policies: 0"))
        XCTAssertTrue(result.output.contains("Runtime context set: no"))
    }

    func testRLSEnableThenStatusEnabled() throws {
        let (dbURL, password) = try makeDatabase()
        let enable = try runCLI(["rls", "enable", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(enable.status, 0)
        XCTAssertTrue(enable.output.contains("RLS enabled"))

        let status = try runCLI(["rls", "status", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(status.status, 0)
        XCTAssertTrue(status.output.contains("RLS: enabled"))
    }

    func testRLSDisableThenStatusDisabled() throws {
        let (dbURL, password) = try makeDatabase()
        _ = try runCLI(["rls", "enable", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        let disable = try runCLI(["rls", "disable", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(disable.status, 0)
        XCTAssertTrue(disable.output.contains("RLS disabled"))

        let status = try runCLI(["rls", "status", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(status.status, 0)
        XCTAssertTrue(status.output.contains("RLS: disabled"))
    }

    func testRLSPolicyAddEachPresetAndList() throws {
        let (dbURL, password) = try makeDatabase()
        let addAdminOwner = try runCLI([
            "rls", "policy", "add",
            "--db", dbURL.path,
            "--preset", "admin-owner",
            "--owner-field", "ownerId"
        ], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(addAdminOwner.status, 0)

        let addAdminTeam = try runCLI([
            "rls", "policy", "add",
            "--db", dbURL.path,
            "--preset", "admin-team",
            "--team-field", "teamId"
        ], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(addAdminTeam.status, 0)

        let addViewer = try runCLI([
            "rls", "policy", "add",
            "--db", dbURL.path,
            "--preset", "viewer-readonly"
        ], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(addViewer.status, 0)

        let list = try runCLI(["rls", "policy", "list", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(list.status, 0)
        XCTAssertTrue(list.output.contains("admin_full_access"))
        XCTAssertTrue(list.output.contains("user_owns_record"))
        XCTAssertTrue(list.output.contains("user_in_team"))
        XCTAssertTrue(list.output.contains("viewer_can_select"))
        XCTAssertTrue(list.output.contains("viewer_read_only"))
    }

    func testRLSPolicyClear() throws {
        let (dbURL, password) = try makeDatabase()
        _ = try runCLI([
            "rls", "policy", "add",
            "--db", dbURL.path,
            "--preset", "admin-owner"
        ], env: ["BLAZEDB_PASSWORD": password])

        let clear = try runCLI(["rls", "policy", "clear", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(clear.status, 0)
        XCTAssertTrue(clear.output.contains("RLS policies cleared"))

        let list = try runCLI(["rls", "policy", "list", "--db", dbURL.path], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertEqual(list.status, 0)
        XCTAssertTrue(list.output.contains("No RLS policies configured."))
    }

    func testRLSInvalidPresetFailsNonzero() throws {
        let (dbURL, password) = try makeDatabase()
        let result = try runCLI([
            "rls", "policy", "add",
            "--db", dbURL.path,
            "--preset", "bad-preset"
        ], env: ["BLAZEDB_PASSWORD": password])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Invalid preset"))
    }

    func testRLSMissingDBPathFailsDeterministically() throws {
        let result = try runCLI(["rls", "status"], env: ["BLAZEDB_PASSWORD": "irrelevant"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Missing required --db <path> argument"))
    }
}

final class BlazedbRLSIntegrationSurfaceTests: XCTestCase {
    private func makeDatabase() throws -> (dbURL: URL, password: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rls-surface-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dbURL = root.appendingPathComponent("surface.blazedb")
        let password = "RLSConfigPass_123A"
        _ = try BlazeDBClient(name: "surface", fileURL: dbURL, password: password)
        return (dbURL, password)
    }

    func testRLSConfigStoreRoundTripAndApply() throws {
        let (dbURL, password) = try makeDatabase()
        let config = CLIRLSConfig(
            enabled: true,
            policies: [CLIRLSPolicySpec(preset: "admin-owner", ownerField: "userId", teamField: nil)]
        )

        try CLIRLSConfigStore.save(config, forDBPath: dbURL.path)
        let loaded = try CLIRLSConfigStore.load(forDBPath: dbURL.path)
        XCTAssertEqual(loaded, config)

        let client = try BlazeDBClient(name: "surface", fileURL: dbURL, password: password)
        _ = try CLIRLSConfigStore.loadAndApply(forDBPath: dbURL.path, to: client)
        XCTAssertTrue(client.isRLSEnabled)
        XCTAssertTrue(client.listRLSPolicyNames().contains("admin_full_access"))
        XCTAssertTrue(client.listRLSPolicyNames().contains("user_owns_record"))
    }

    func testGlobalHelpMentionsRLSCommandsSourceGuard() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeShell/CLIHelp.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(source.contains("blazedb rls <command>"))
    }

    func testRunShellAppliesRLSConfigAndFetchAllJSONUpdatesContextSourceGuard() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeShell/BlazedbRepl.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(source.contains("CLIRLSConfigStore.loadAndApply(forDBPath: dbPath, to: client)"))
        XCTAssertTrue(source.contains("} else if trimmed == \"fetchAll --json\""))
        XCTAssertTrue(source.contains("lastTableRecords = records"))
        XCTAssertTrue(source.contains("} else if trimmed == \"fetchAll --ndjson\""))
    }

    func testReplIncludesOperatorConsoleCommandsSourceGuard() throws {
        let replURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeShell/BlazedbRepl.swift")
        let replSource = try String(contentsOf: replURL, encoding: .utf8)
        XCTAssertTrue(replSource.contains("if trimmed == \"status\""))
        XCTAssertTrue(replSource.contains("if trimmed == \"schema\""))
        XCTAssertTrue(replSource.contains("if trimmed == \"doctor\" || trimmed == \"doctor --json\""))
        XCTAssertTrue(replSource.contains("trimmed.starts(with: \"explain query \")"))
        XCTAssertTrue(replSource.contains("if trimmed == \"begin\""))
        XCTAssertTrue(replSource.contains("if trimmed == \"commit\""))
        XCTAssertTrue(replSource.contains("if trimmed == \"rollback\""))
    }

    func testReplHelpIncludesOperatorConsoleCommandsSourceGuard() throws {
        let helpURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlazeShell/CLIHelp.swift")
        let source = try String(contentsOf: helpURL, encoding: .utf8)
        XCTAssertTrue(source.contains("explain query <...>"))
        XCTAssertTrue(source.contains("status                           Runtime health and performance summary"))
        XCTAssertTrue(source.contains("schema                           Inferred fields/types + indexes"))
        XCTAssertTrue(source.contains("doctor                           Operator health checks"))
        XCTAssertTrue(source.contains("begin                            Begin transaction"))
        XCTAssertTrue(source.contains("rollback                         Roll back transaction"))
        XCTAssertTrue(source.contains("Global commands: blazedb start · blazedb --help"))
    }
}
