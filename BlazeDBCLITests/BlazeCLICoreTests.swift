import XCTest
import Foundation
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

final class CLIMasterKeyringTests: XCTestCase {
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
