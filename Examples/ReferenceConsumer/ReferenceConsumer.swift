//
//  ReferenceConsumer
//  BlazeDB Production-Readiness: boring lifecycle example.
//  Proves open → write → read → observe → (simulated exit) → reopen → verify.
//  No network, no background loops. Run twice: phase1 writes and exits; phase2 verifies recovery.
//

import Foundation
import BlazeDB

private let dbName = "ReferenceConsumer"
private let artifactDir = "BlazeDB_ReferenceConsumer"
private let flagFileName = ".phase1_done"

@main
struct ReferenceConsumer {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(artifactDir)
        let dbURL = base.appendingPathComponent("ref.blazedb")
        let flagURL = base.appendingPathComponent(flagFileName)

        if FileManager.default.fileExists(atPath: flagURL.path) {
            try runPhase2(dbURL: dbURL, flagURL: flagURL)
        } else {
            try runPhase1(dbURL: dbURL, base: base, flagURL: flagURL)
        }
    }

    /// Phase 1: create DB, write, read back, observe(), write flag, exit (simulate abrupt exit after commit).
    static func runPhase1(dbURL: URL, base: URL, flagURL: URL) throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let db = try BlazeDBClient.open(at: dbURL, password: "Ref-Consumer-Pwd-123")

        let record = BlazeDataRecord([
            "app": .string("ReferenceConsumer"),
            "phase": .int(1),
            "at": .date(Date())
        ])
        let id = try db.insert(record)
        print("[phase1] inserted id=\(id.uuidString.prefix(8))")

        let results = try db.query().limit(5).execute().records
        print("[phase1] read back count=\(results.count)")

        let snapshot = try db.observe()
        print("[phase1] observe(): uptime=\(snapshot.uptime)s health=\(snapshot.health.status) tx committed=\(snapshot.transactions.committed)")

        try Data().write(to: flagURL)
        print("[phase1] wrote flag at \(flagURL.path); exiting without close (simulated abrupt exit after commit).")
        exit(0)
    }

    /// Phase 2: reopen, verify data, observe(), clean up, exit cleanly.
    static func runPhase2(dbURL: URL, flagURL: URL) throws {
        let db = try BlazeDBClient.open(at: dbURL, password: "Ref-Consumer-Pwd-123")

        let results = try db.query().limit(10).execute().records
        guard !results.isEmpty else {
            print("[phase2] ERROR: no records after reopen")
            exit(1)
        }
        print("[phase2] recovered record count=\(results.count)")

        let snapshot = try db.observe()
        print("[phase2] observe(): uptime=\(snapshot.uptime)s health=\(snapshot.health.status) tx committed=\(snapshot.transactions.committed)")

        try db.close()
        try? FileManager.default.removeItem(at: flagURL)
        let base = dbURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: base)
        print("[phase2] closed and cleaned up. Done.")
    }
}
