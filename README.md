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

## Guarantees

- Public database-opening APIs require a password; stored pages use AES-256-GCM ([key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md))
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

Android is **experimental**: the PR gate cross-compiles the bridge and runs a KMM emulator smoke. It is not **shipped** as a consumer SDK (no `Package.swift` platform entry, no published registry artifacts) and not equivalent to Linux host Tier0.

Authority for tiers: [Compatibility](Docs/COMPATIBILITY.md) · [android-status.md](Docs/android-status.md)

---

## Tools and native embedding

The `blazedb` CLI and REPL ship with the package for local inspection:

```bash
swift build --product blazedb
.build/debug/blazedb --help
.build/debug/blazedb          # interactive picker / REPL (not a network server)
```

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
| API and queries | [API Reference](Docs/API/API_REFERENCE.md) · [Developer Guide](Docs/DEVELOPER_GUIDE.md) |
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
