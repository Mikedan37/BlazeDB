#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.artifacts/vapor-reference-smoke-$(date +%s)"
LOG_DIR="${ROOT_DIR}/.logs"

mkdir -p "${WORK_DIR}" "${LOG_DIR}"
mkdir -p "${WORK_DIR}/Probe"

pushd "${WORK_DIR}/Probe" >/dev/null
swift package init --type executable --name VaporProbe >/dev/null

python3 - <<'PY'
from pathlib import Path

pkg = Path("Package.swift")
pkg.write_text("""// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VaporProbe",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(path: "../../../")
    ],
    targets: [
        .executableTarget(
            name: "VaporProbe",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "BlazeDB", package: "BlazeDB")
            ]
        )
    ]
)
""", encoding="utf-8")

main = Path("Sources/VaporProbe/main.swift")
main.write_text("""import Foundation
import Vapor
import BlazeDB

private enum DBKey: StorageKey {
    typealias Value = BlazeDBClient
}

@main
enum Entry {
    static func main() throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = Application(env)
        defer { app.shutdown() }

        let db = try BlazeDBClient.open(named: "vapor-reference-smoke", password: "smoke-password")
        app.storage[DBKey.self] = db
        app.lifecycle.use(DBLifecycle())

        app.http.server.configuration.port = 18181
        app.http.server.configuration.hostname = "127.0.0.1"

        app.get("db", "health") { req -> String in
            guard let db = req.application.storage[DBKey.self] else {
                throw Abort(.internalServerError, reason: "Database not initialized")
            }
            return try db.health().status.rawValue
        }

        app.post("users") { req -> [String: String] in
            guard let db = req.application.storage[DBKey.self] else {
                throw Abort(.internalServerError, reason: "Database not initialized")
            }
            let body = try req.content.decode([String: String].self)
            let record = BlazeDataRecord([
                "name": .string(body["name"] ?? "unknown"),
                "email": .string(body["email"] ?? "unknown@example.com"),
                "active": .bool(true)
            ])
            let id = try db.insert(record)
            return ["id": id.uuidString]
        }

        app.get("users") { req -> Int in
            guard let db = req.application.storage[DBKey.self] else {
                throw Abort(.internalServerError, reason: "Database not initialized")
            }
            return try db.query().where("active", equals: .bool(true)).execute().records.count
        }

        try app.execute()
    }
}

private struct DBLifecycle: LifecycleHandler {
    func shutdown(_ application: Application) {
        try? application.storage[DBKey.self]?.close()
    }
}
""", encoding="utf-8")
PY

for attempt in 1 2 3; do
  if swift package resolve >>"${LOG_DIR}/vapor-reference-smoke.log" 2>&1; then
    break
  fi
  if [[ "${attempt}" == "3" ]]; then
    echo "swift package resolve failed after retries" >&2
    exit 1
  fi
  sleep 2
done

swift run VaporProbe >"${LOG_DIR}/vapor-reference-smoke.log" 2>&1 &
SERVER_PID=$!
trap 'kill "${SERVER_PID}" 2>/dev/null || true; wait "${SERVER_PID}" 2>/dev/null || true' EXIT

for _ in {1..300}; do
  if curl -fsS "http://127.0.0.1:18181/db/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:18181/db/health" | tee "${LOG_DIR}/vapor-reference-health.txt"; then
  echo "Server did not become healthy; see ${LOG_DIR}/vapor-reference-smoke.log" >&2
  exit 1
fi
curl -fsS -X POST "http://127.0.0.1:18181/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Smoke User","email":"smoke@example.com"}' | tee "${LOG_DIR}/vapor-reference-create-user.json"
curl -fsS "http://127.0.0.1:18181/users" | tee "${LOG_DIR}/vapor-reference-users-count.txt"

kill "${SERVER_PID}" 2>/dev/null || true
wait "${SERVER_PID}" 2>/dev/null || true
trap - EXIT

popd >/dev/null
echo "Vapor reference integration smoke test passed."
