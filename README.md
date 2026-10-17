# BlazeDB

Encrypted local storage for Swift. One file, typed records, WAL-backed recovery, and a REPL that opens the same databases your app uses.

BlazeDB is an embedded **document** database (Swift `Codable`, not SQL). Pages are encrypted by default. You get transactions, live queries, and a `blazedb` CLI. macOS and Linux are runtime-tested in CI; iOS and friends are compile-tested; Android/KMM is experimental.

Not the GPU SQL project [BlazingDB](https://github.com/BlazingDB/BlazingDB). This is the Swift engine on disk.

[![CI](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v2.8.2-green.svg)](RELEASE.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)

**Release:** [v2.8.2](RELEASE.md) · [Changelog](CHANGELOG.md) · [Docs](Docs/README.md) · [Compatibility](Docs/COMPATIBILITY.md)

---

## Try it

<a id="start-here-new-users"></a>
<a id="try-blazedb-from-this-repo"></a>

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
let bug = Bug(title: "Crash on launch", status: "open")
try db.put(bug)

// Typed records use namespaced IDs internally (namespace:UUID).
let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

`"bug"` in `query("bug")` is a namespace label, not a SQL table.

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

CI verifies the snippets above: `swift run ReadmeSamples`.

**Shipped with it today:** [Seeker for iPhone](https://www.seekerscore.com/iphone) (TestFlight) keeps résumés and matches on device; job queues can persist through the [C ABI / Go cgo](Examples/Go/hello_blazedb.go). [More examples](Docs/Adoption/REAL_WORLD_USAGE.md).

---

## Is BlazeDB the right choice?

| BlazeDB fits | Reach for SQLite or GRDB instead |
|--------------|----------------------------------|
| Swift documents, encryption on by default | SQL, ad hoc reporting, huge tooling ecosystem |
| Live queries in-process | Fastest raw inserts on an unencrypted path |
| One **owner** of the file: your app, or a daemon/worker with a queue (macOS/Linux) | Every process opening the same file on its own |

SQLite still wins plenty of benchmarks. We say so on purpose: [Why not SQLite?](Docs/GettingStarted/WHY_NOT_SQLITE.md)

<a id="hard-nos"></a>

### When to pass

- Two writers on the same file with no coordinator. Fix: **one process owns BlazeDB**, everyone else queues (Vapor service, Go worker, your daemon). Works on Mac/Linux; on iOS keep it in the app. [Details](Docs/Guarantees/WHY_SINGLE_WRITER.md)
- Built-in network DB or multi-device sync ([not in the default OSS package](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md))
- SQL, NFS/cloud mounts for the file, or a published Kotlin SDK ([Android is experimental](Docs/android-status.md))

---

## Installation

Requires Swift 6.0+ ([swift.org](https://www.swift.org/install/) or Xcode), matching `swift-tools-version:6.0` in `Package.swift`.

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.2")
```

Depend on the **`BlazeDB`** product and `import BlazeDB`.

Longer walkthrough: [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) · Release notes for this pin: [RELEASE.md](RELEASE.md)

---

## Run it from a clone

```bash
swift run HelloBlazeDB          # smallest working example
swift run ReadmeSamples         # every snippet in this README, verified
```

### Open your own database in the REPL

`blazedb` is how you read and edit an existing `.blazedb` file without writing any code. Point it at a database and you get a prompt against the live engine.

```bash
swift build --product blazedb
.build/debug/blazedb --help

.build/debug/blazedb                      # scan for databases, pick one, open a REPL
.build/debug/blazedb ./mydb.blazedb        # or open one directly
.build/debug/blazedb ./mydb.blazedb <pass> # same, skipping the password prompt
```

From the prompt you can inspect, query, and modify records directly:

```text
> inspect                        # db info plus a table preview
> schema                         # inferred fields and types, indexes
> fetchAll                       # every record as a table
> fetchAll --json                # or --ndjson / --raw to export
> query age > 60                 # ops: = != > < >= <= contains
> query age > 60 sort age desc limit 10
> explain query age > 60         # execution plan and estimate
> fetch <uuid>                   # inspector view for one record
> insert {"title": "Hello"}      # also update <uuid>, delete, softDelete
> begin / commit / rollback      # transactions
> doctor                         # operator health checks
> status                         # runtime health and performance
> help                           # full command list
```

Manager mode (`blazedb --manager`) mounts several databases at once and switches between them with `list`, `mount`, `use`, and `current`. Full reference: [blazedb CLI docs](Docs/Tools/BLAZESHELL_DOCUMENTATION.md)

The REPL is a local client against a file on disk, not a network server.

The interactive picker (`blazedb` with no arguments) enters raw terminal mode, so it needs a real TTY and will fail in an IDE console with `tcgetattr failed`. Opening a path directly does not, which means you can also script it:

```bash
printf 'query age > 60 --json\nexit\n' | .build/debug/blazedb ./mydb.blazedb <pass>
```

## Navigate the repo

`./dev help` is the front door for every contributor command, so you do not have to read the tree to find things.

```bash
./dev help                # all contributor and benchmark commands
./dev tiers               # test tiers and which script runs each
./dev tests BPlusTree     # find tests by name
./dev experiments         # list repository experiments
```

## Run the tests

Locally, by tier. Tier 0 is the fast loop; Tier 1 is the PR gate.

```bash
./dev tier0               # fast local correctness
./dev tier1               # PR correctness gate
./dev tier2               # integration and recovery
./dev tier3               # stress and destructive
./dev test BPlusTreeNodeTests.createsSimpleTree   # one focused test
```

To reproduce CI exactly, these are the commands the `PR Gate` workflow runs in its macOS job, in order:

```bash
swift build --target BlazeDBCore
./Scripts/check-sendable-observation.sh
swift build --product blazedb
BLAZEDB_TEST_SCOPE=tier0 swift test --filter BlazeDB_Tier0
swift test --skip-build --filter BlazeDB_Tier1
swift test --skip-build --filter BlazeDB_CLITests
./Scripts/verify-readme-quickstart.sh
./Scripts/verify-readme-samples.sh
```

The Linux job builds `BlazeDBCore` and the CLI tools, then runs the same Tier 0 filter. Apple platforms beyond macOS are cross-compiled only.

Tier definitions, what belongs in each, and the full lane map: [TESTING_GUIDE.md](Docs/TESTING_GUIDE.md) · [XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md)

---

## Guarantees

- Public database-opening APIs require a password; keys are derived with PBKDF2-HMAC-SHA256 and pages use AES-256-GCM ([key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) — not Argon2id)
- Default storage path uses WAL-backed recovery ([documented durability behavior and overflow caveats](Docs/Status/DURABILITY_MODE_SUPPORT.md))
- Typed document APIs and raw key-value access ([API reference](Docs/API/API_REFERENCE.md))
- Transactional write APIs ([transactions](Docs/DEVELOPER_GUIDE.md#transactions)) and in-process live queries ([architecture](Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md))
- One engine writer per database file (many clients via an owning daemon on macOS/Linux is fine)

**Runs as:** SwiftUI app, CLI, Vapor service, or anything linking `BlazeDBC` (Go, C, etc.). The engine always lives in **one** process that holds the file open; see [When to pass](#hard-nos) for sharing rules.

Direction, not release guarantees: [ROADMAP.md](ROADMAP.md)

---

## Platforms

| Tier | Platforms |
|------|-----------|
| **Runtime CI** (host engine tests) | macOS, Linux |
| **Declared and compile-tested** | iOS, watchOS, tvOS, visionOS |
| **experimental** | Android cross-compile + KMM sample runtime in the PR gate (not a published SDK) |

### Android and KMM (experimental)

Android is reached through a Swift bridge plus a Kotlin Multiplatform module, not a published SDK.

- **`BlazeDBAndroidBridge`** wraps `BlazeDBCore` and builds as `libBlazeDBAndroidBridge.so`. Two products expose it: `BlazeDBAndroidBridge` (dynamic) and `BlazeDBKMMBridgeStatic` (static). Sources in [Examples/BlazeDBAndroidBridge](Examples/BlazeDBAndroidBridge/).
- **The KMM module** in [Examples/android](Examples/android/) links that bridge. `shared/src/androidMain` calls into Swift over JNI through a C shim (`System.loadLibrary("blazedb_android_bridge")`); `iosMain` uses cinterop instead.
- Cross-compiled for `aarch64-unknown-linux-android28` and `x86_64-unknown-linux-android28`.

Three jobs in the `PR Gate` workflow cover it (names shortened here; the workflow separates the prefix with a dash):

| Job | What it proves |
|-----|----------------|
| Android Cross-Compile | builds the bridge, then asserts `libBlazeDBAndroidBridge.so` exists for both triples |
| KMM Android x86_64 Emulator Runtime | boots an API 34 x86_64 emulator with KVM and runs `:app:connectedDebugAndroidTest`, a real on-device instrumentation test |
| KMM Android arm64 Artifact Packaging | stages `arm64-v8a` native libs and packages the artifact |

It stays **experimental** because there is no `Package.swift` platform entry and no published registry artifacts, so it is not a consumer SDK and not equivalent to Linux host Tier0.

Authority for tiers: [Compatibility](Docs/COMPATIBILITY.md) · [android-status.md](Docs/android-status.md)

---

## Tools and native embedding

The `blazedb` CLI and REPL ship with the package. They read and edit real databases against the same engine your app uses, so they are the fastest way to see what is actually in a file. See [Open your own database in the REPL](#open-your-own-database-in-the-repl) above.

`BlazeDoctor`, `BlazeDump`, and `BlazeInfo` are separate shipped executables for health checks, export and restore, and a quick snapshot. Each requires arguments; pass `--help` for the shape.

`BlazeDBC` exposes a documented byte-oriented C ABI (`BlazeDBC/include/blazedb.h`), so any language that can call C is able to embed the same engine. That is interoperability capability, not an official SDK per language. No Go, Rust, or Python SDKs are published.

```bash
swift build -c release --product BlazeDBC
```

Full tool catalog with support-state labels, visualizer apps, and the benchmark front door: [Docs/Tools/README.md](Docs/Tools/README.md) · C ABI contract: [C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) · Go via cgo recipe: [Examples/Go/README.md](Examples/Go/README.md)

Benchmarks are not normal XCTest CI. Methodology and honest framing: [Docs/Benchmarks/README.md](Docs/Benchmarks/README.md)

---

## Documentation

Start with the [documentation index](Docs/README.md), which carries support status for every area.

| Area | Entry point |
|------|-------------|
| Support & limits | [Support and limitations matrix](Docs/Support/SUPPORT_AND_LIMITATIONS.md) |
| Choose a store | [Embedded Swift storage comparison](Docs/GettingStarted/COMPARE_EMBEDDED_SWIFT_STORAGE.md) · [Why not SQLite?](Docs/GettingStarted/WHY_NOT_SQLITE.md) |
| Get started | [Getting Started](Docs/GettingStarted/README.md) · [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) · [Linux](Docs/GettingStarted/LINUX_GETTING_STARTED.md) |
| API and queries | [API Reference](Docs/API/API_REFERENCE.md) · [Developer Guide](Docs/DEVELOPER_GUIDE.md) · [Graph Query](Docs/API/GRAPH_QUERY_API.md) (advanced charting) |
| Engine internals | [Architecture](Docs/Architecture/README.md) · [Codebase map](Docs/Architecture/CODEBASE_MAP.md) |
| Encryption and keys | [Key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) · [Security architecture](Docs/Security/README.md) |
| Durability and recovery | [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) |
| Schema and migrations | [MIGRATION.md](Docs/MIGRATION.md) |
| Backup and restore | [HOW_TO_USE: Backups](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#9-backups-restore-and-trust) |
| Performance | [Docs/Performance](Docs/Performance/README.md) · [Benchmarks](Docs/Benchmarks/README.md) |
| Examples | [Examples/README.md](Examples/README.md) (catalog with support-state labels) |
| SwiftUI | [SwiftUI patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |

---

## Contributing

BlazeDB welcomes focused contributions across documentation, developer tooling, tests, platform support, and core correctness.

- [Starter tasks (curated)](Docs/Contributing/STARTER_TASKS.md) — documentation and CLI tasks with acceptance criteria (prefer these over the full `good first issue` label list)
- [Contribution guide](CONTRIBUTING.md) · [Issue guide](Docs/Contributing/ISSUE_GUIDE.md) · [Learning paths](Docs/Contributing/LEARNING_PATHS.md)

Comment on an issue before starting substantial work so scope and ownership are clear. Codebase orientation: [CODEBASE_MAP](Docs/Architecture/CODEBASE_MAP.md)

---

## Project status

| | |
|--|--|
| Release | [v2.8.2](RELEASE.md) · [CHANGELOG](CHANGELOG.md) |
| Platforms | [COMPATIBILITY.md](Docs/COMPATIBILITY.md) |
| Roadmap | [ROADMAP.md](ROADMAP.md) (directional) |
| Security | [SECURITY.md](SECURITY.md) (reporting) |
| License | MIT ([LICENSE](LICENSE)) |

Repository structure, test coverage, and CI lane metrics: [Docs/Meta/REPOSITORY_METRICS.md](Docs/Meta/REPOSITORY_METRICS.md)
