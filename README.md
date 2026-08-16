# BlazeDB

BlazeDB is an encrypted, embedded database for Swift applications and services, with typed records, transactional writes, WAL-backed recovery, live queries, and Linux support.

It runs inside your process. No separate database server is required.

[![CI](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v2.8.1-green.svg)](RELEASE.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)

**Current release:** [v2.8.1](RELEASE.md) · [Changelog](CHANGELOG.md) · [Docs index](Docs/README.md) · [Compatibility](Docs/COMPATIBILITY.md)

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

---

## Is BlazeDB the right choice

| Choose BlazeDB when | Choose SQLite or GRDB when |
|---------------------|----------------------------|
| You want typed Swift document APIs | You need SQL |
| Encryption by default matters | You need ecosystem maturity |
| Live in-process Swift queries matter | You need broader third-party tooling |
| You accept single-process file ownership | You need multi-process access |

Longer fit comparison, including where SQLite wins on latency: [Why not SQLite?](Docs/GettingStarted/WHY_NOT_SQLITE.md)

### Do not use BlazeDB when you need

- Multi-process writers ([why single-writer](Docs/Guarantees/WHY_SINGLE_WRITER.md))
- Networked or client-server access
- Multi-device sync ([deferred from the default package](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md))
- SQL compatibility (fluent Swift queries only)
- Storage on a network filesystem (not recommended)
- A published mobile SDK for Android ([experimental only](Docs/android-status.md))

---

## Installation

Requires Swift 6.0+ ([swift.org](https://www.swift.org/install/) or Xcode), matching `swift-tools-version:6.0` in `Package.swift`.

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
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
- Single-process file ownership model

**Deployment:** a SwiftUI or Apple-platform app, a macOS or Linux command-line tool, a Vapor or other server-side Swift process, or a native application linking `BlazeDBC`. In every case BlazeDB runs in the host process and owns a local file. Constraints are listed under [Do not use BlazeDB when you need](#do-not-use-blazedb-when-you-need) above.

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

- [Good first issues](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) · [Help wanted](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
- [Contribution guide](CONTRIBUTING.md) · [Issue guide](Docs/Contributing/ISSUE_GUIDE.md) · [Learning paths](Docs/Contributing/LEARNING_PATHS.md)

Comment on an issue before starting substantial work so scope and ownership are clear. Codebase orientation: [CODEBASE_MAP](Docs/Architecture/CODEBASE_MAP.md)

---

## Project status

| | |
|--|--|
| Release | [v2.8.1](RELEASE.md) · [CHANGELOG](CHANGELOG.md) |
| Platforms | [COMPATIBILITY.md](Docs/COMPATIBILITY.md) |
| Roadmap | [ROADMAP.md](ROADMAP.md) (directional) |
| Security | [SECURITY.md](SECURITY.md) (reporting) |
| License | MIT ([LICENSE](LICENSE)) |

Repository structure, test coverage, and CI lane metrics: [Docs/Meta/REPOSITORY_METRICS.md](Docs/Meta/REPOSITORY_METRICS.md)
