import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

final class CrossVersionExportRestoreHarnessTests: XCTestCase {
    private let fixturesRoot = URL(fileURLWithPath: "Tests/CompatibilityFixtures", isDirectory: true)

    func testRestoreAllDumpFixtures() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fixturesRoot.path) else {
            throw XCTSkip("No compatibility fixtures directory at Tests/CompatibilityFixtures")
        }

        let versionDirs = try fm.contentsOfDirectory(
            at: fixturesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !versionDirs.isEmpty else {
            throw XCTSkip("No version fixture directories found in Tests/CompatibilityFixtures")
        }

        var exercised = 0

        for versionDir in versionDirs {
            let dumpURL = versionDir.appendingPathComponent("dump.blazedump")
            guard fm.fileExists(atPath: dumpURL.path) else { continue }

            let tempRoot = fm.temporaryDirectory.appendingPathComponent("blazedb-compat-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempRoot) }

            let restoredURL = tempRoot.appendingPathComponent("restored.blazedb")
            let db = try BlazeDBClient(name: "compat-restore", fileURL: restoredURL, password: "Compat-123Aa!")

            let dumpBytes = try Data(contentsOf: dumpURL)
            let dump = try DatabaseDump.decodeAndVerify(
                dumpBytes,
                allowLegacyHashMismatch: true
            )

            try BlazeDBImporter.restore(
                from: dumpURL,
                to: db,
                allowSchemaMismatch: true,
                allowLegacyHashMismatch: true
            )

            let restoredCount = try db.count()
            XCTAssertEqual(
                restoredCount,
                dump.manifest.recordCount,
                "Fixture \(versionDir.lastPathComponent) restore count mismatch"
            )

            let health = try db.health()
            XCTAssertTrue(
                health.status == .ok || health.status == .warn,
                "Fixture \(versionDir.lastPathComponent) restored with unhealthy state: \(health.status.rawValue)"
            )

            exercised += 1
        }

        guard exercised > 0 else {
            throw XCTSkip("No dump.blazedump fixtures found under Tests/CompatibilityFixtures/*")
        }
    }
}
