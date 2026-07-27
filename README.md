# BlazeDB

BlazeDB is an encrypted, in-process database engine written in Swift for applications and in-process services. It provides typed document APIs, raw key-value access, transactional write APIs, WAL-backed recovery, live queries, SwiftUI integration on Apple platforms, local inspection tools, Linux runtime support, a documented C ABI for native embeds, and CI-validated Android/KMM paths (experimental packaging). Go and other languages can call the C ABI through cgo or FFI; no official language SDKs are published.

It runs inside your process. No separate database server is required.

[![CI](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v2.8.1-green.svg)](RELEASE.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)

**Current release:** [v2.8.1](RELEASE.md) · [Changelog](CHANGELOG.md) · [Docs index](Docs/README.md) · [Compatibility](Docs/COMPATIBILITY.md)

### Platforms

| Tier | Platforms |
|------|-----------|
| **Runtime CI** (host engine tests) | macOS, Linux |
| **Declared and compile-tested** | iOS, watchOS, tvOS, visionOS |
| **CI-validated (experimental packaging)** | Android cross-compile + KMM sample runtime in the PR gate |

Android is **not unsupported**: the PR gate cross-compiles the bridge and runs a KMM emulator smoke. It is also **not the same tier as Linux** (no host `BlazeDB_Tier0` on Android; not in `Package.swift` `platforms:`; no published consumer SDK). Details: [Compatibility](Docs/COMPATIBILITY.md) · [android-status.md](Docs/android-status.md).

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

CI also verifies the README snippets: `swift run ReadmeSamples`.

---

## Why BlazeDB

- **Encryption by default:** Public database-opening APIs require a password; stored pages use AES-256-GCM. See [Key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) and [Security architecture](Docs/Security/README.md).
- **Typed Swift records:** Store ordinary structs with `BlazeStorable`, or use raw and byte APIs when you need them. [Getting Started](Docs/GettingStarted/README.md) · [API Reference](Docs/API/API_REFERENCE.md).
- **WAL-backed recovery:** The default storage path uses a write-ahead log. Documented durability behavior and overflow caveats: [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md).
- **Transactional write APIs:** Public write paths support transactional work. See [Transactions](Docs/DEVELOPER_GUIDE.md#transactions) in the Developer Guide.
- **Live queries and SwiftUI:** Observe result sets in-process with `BlazeLiveQuery` and SwiftUI-facing wrappers on supported Apple platforms. [Live query architecture](Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md) · [SwiftUI patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md).
- **Inspection tooling:** Explore databases with the shipped `blazedb` CLI/REPL; companion macOS apps and maintenance executables are listed below.
- **Linux runtime:** Core engine is exercised in Linux CI alongside macOS. [Linux getting started](Docs/GettingStarted/LINUX_GETTING_STARTED.md).
- **Native embeds:** The same engine is reachable through `BlazeDBC` (`blazedb.h`). [C ABI contract](Docs/Architecture/C_ABI_BYTE_KV.md).
- **Android / KMM (CI-validated, experimental packaging):** PR-gate cross-compile + KMM emulator smoke exist; not a published mobile SDK and not Linux-equivalent host Tier0. [android-status.md](Docs/android-status.md).

---

## Choose your path

| If you want to… | Start here |
|-----------------|------------|
| Build a Swift app | [Try it](#try-it) · [Getting Started](Docs/GettingStarted/README.md) |
| Embed in Vapor or server-side Swift | [HOW_TO_USE: Vapor embedding](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#8-using-blazedb-in-a-server-vapor-example) |
| Use the CLI / REPL | [CLI and tools](#cli-and-inspection-tools) · [Tools docs](Docs/Tools/README.md) |
| Call from C | [Native interoperability](#native-interoperability) · [Examples/C](Examples/C/) |
| Call from Go via cgo | [Examples/Go](Examples/Go/README.md) (recipe; no official Go module) |
| Understand durability and recovery | [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) |
| Encryption and vulnerability reporting | [Key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) · [SECURITY.md](SECURITY.md) |
| Live queries / SwiftUI | [Live query architecture](Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md) · [SwiftUI patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Linux setup | [LINUX_GETTING_STARTED.md](Docs/GettingStarted/LINUX_GETTING_STARTED.md) |
| Android / KMM (CI-validated; experimental packaging) | [android-status.md](Docs/android-status.md) |
| Platform support tiers | [Compatibility](Docs/COMPATIBILITY.md) |
| Benchmarks and methodology | [Docs/Benchmarks](Docs/Benchmarks/README.md) |
| Contribute | [Contributing](#contributing) · [CONTRIBUTING.md](CONTRIBUTING.md) |

---

## Installation

Requires Swift 6.0+ ([swift.org](https://www.swift.org/install/) or Xcode). Matches `swift-tools-version:6.0` in `Package.swift`.

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

Depend on the **`BlazeDB`** product and `import BlazeDB`.

From a clone:

```bash
swift run HelloBlazeDB
swift run ReadmeSamples
swift build --product blazedb
swift build -c release --product BlazeDBC
```

Release notes for this pin: [RELEASE.md](RELEASE.md) (v2.8.1). Longer walkthrough: [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md).

---

## Core API overview

| Task | Entry | Deeper docs |
|------|-------|-------------|
| Open | `BlazeDB.open(name:password:)` or `open(at:password:)` | [Getting Started](Docs/GettingStarted/README.md) |
| Typed put / get / query | `BlazeStorable` + namespace queries | [API Reference](Docs/API/API_REFERENCE.md) |
| Transactional writes | `beginTransaction` / `commitTransaction` / rollback | [Transactions](Docs/DEVELOPER_GUIDE.md#transactions) |
| Live queries | `BlazeLiveQuery` / SwiftUI property wrappers | [LIVE_QUERY_ARCHITECTURE](Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md) |
| Raw / byte KV | Client byte APIs; C ABI mirrors this surface | [C_ABI_BYTE_KV](Docs/Architecture/C_ABI_BYTE_KV.md) |
| Indexing and queries | Query builder, indexes, search tuning | [Developer Guide](Docs/DEVELOPER_GUIDE.md) · [Performance](Docs/Performance/README.md) |
| Schema and migrations | Schema validation and migration APIs | [MIGRATION.md](Docs/MIGRATION.md) · [Advanced topics](Docs/README.md#advanced-but-supported) |
| Backup, export, restore | Export/import and verification APIs | [HOW_TO_USE: Backups](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#9-backups-restore-and-trust) |

See the [documentation index](Docs/README.md) for support status and deeper guides.

---

## Deployment model

BlazeDB is embedded and runs inside the host process on a local database file.

Common hosts include:

- SwiftUI and other Apple-platform applications
- macOS and Linux command-line tools
- Vapor and other server-side Swift processes ([embedding guide](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#8-using-blazedb-in-a-server-vapor-example))
- Native applications linking `BlazeDBC`

It is not a standalone network database server and not a multi-device sync product in the default package. Platform tiers (runtime, compile-tested, experimental): [Compatibility](Docs/COMPATIBILITY.md).

---

## Guarantees and boundaries

**Core guarantees:**

- Public database-opening APIs require a password; stored pages use AES-256-GCM
- Default storage path uses WAL-backed recovery ([documented durability behavior](Docs/Status/DURABILITY_MODE_SUPPORT.md))
- Typed document APIs and raw key-value access
- Transactional write APIs and in-process live queries
- Single-process file ownership model

**Boundaries (stated once):**

- Embedded and in-process. A Swift service may embed BlazeDB; BlazeDB is not a networked database server product.
- No SQL string engine (fluent Swift queries only).
- Distributed sync, discovery, server, and full telemetry packaging are deferred from the default OSS product ([Distributed Transport Deferred](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)).
- Multi-process writers are not supported.
- Network filesystems are not recommended.
- Android and KMM are CI-validated in the PR gate but remain experimental packaging (not a published SDK; not Linux host Tier0).
- The C ABI enables native embeds; there are no official Go, Rust, or Python SDKs.

Direction (not release guarantees): [ROADMAP.md](ROADMAP.md).

---

## CLI and inspection tools

| Tool | Role | Status |
|------|------|--------|
| `blazedb` | Interactive picker, inspection, REPL (`swift build --product blazedb`) | **Shipped** product |
| `BlazeDoctor` / `BlazeDump` / `BlazeInfo` | Maintenance utilities (`swift run BlazeDoctor`, etc.) | **Developer tools** (separate executables, not `blazedb` subcommands) |
| [BlazeStudio](BlazeStudio/) | macOS database browser | **Companion** app |
| [BlazeDBVisualizer](BlazeDBVisualizer/) | Storage inspection UI | **Developer tool** / beta |
| `BlazeDBBenchmarks` | Release performance workloads | **Developer tool** |
| `./dev` | Contributor test / tier helper | **Contributor** tooling |

```bash
swift build --product blazedb
.build/debug/blazedb --help
.build/debug/blazedb          # interactive picker / REPL (not a network server)
```

More: [Docs/Tools/README.md](Docs/Tools/README.md) · schemes: [XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md).

---

## Native interoperability

`BlazeDBC` exposes a documented **byte-oriented** C ABI (`BlazeDBC/include/blazedb.h`). Published symbols and behavior follow [C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) (stability-governed signatures, not a forever-frozen binary drop-in).

Excerpt from [Examples/C/hello_blazedb.c](Examples/C/hello_blazedb.c):

```c
BlazeDB *db = blazedb_open("hello.blaze", "DemoPass123!");
const char *payload = "queued";
BlazeDBResult rc = blazedb_put(db, "job:42", payload, strlen(payload));
/* get, blazedb_free, delete, close: see hello_blazedb.c */
```

```bash
swift build -c release --product BlazeDBC
# .build/release/libBlazeDBC.dylib (macOS) or libBlazeDBC.so (Linux)
```

Languages that can call C (including Go via cgo, Rust, and Python) can use this surface. That is interoperability capability, not an official SDK for each language.

**Go:** Go can call the C ABI through cgo; no official Go module is currently published. Recipe and limits: [Examples/Go/README.md](Examples/Go/README.md). Dynamic packaging notes: [RELEASE.md](RELEASE.md).

---

## Architecture map

| Topic | Canonical doc |
|-------|----------------|
| Overview | [Docs/Architecture/README.md](Docs/Architecture/README.md) |
| Encryption / keys | [Key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md) · [Security architecture](Docs/Security/README.md) |
| WAL / recovery | [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) |
| Codebase map | [CODEBASE_MAP](Docs/Architecture/CODEBASE_MAP.md) |
| Live queries | [LIVE_QUERY_ARCHITECTURE](Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md) |
| C ABI | [C_ABI_BYTE_KV](Docs/Architecture/C_ABI_BYTE_KV.md) |
| Indexing / queries | [Developer Guide](Docs/DEVELOPER_GUIDE.md) |
| Schema / migrations | [MIGRATION.md](Docs/MIGRATION.md) |

```text
Swift apps / blazedb CLI
        │
        ▼
   BlazeDB / BlazeDBCore
        ├── typed and raw APIs
        ├── queries, indexes, live queries
        ├── transactional writes + WAL recovery
        └── encrypted pages → disk

C / FFI hosts ──► BlazeDBC ──► same engine
```

---

## Examples

Full catalog with support-state labels: [Examples/README.md](Examples/README.md).

### Default / maintained

| Example | Purpose | Command |
|---------|---------|---------|
| [HelloBlazeDB](Examples/HelloBlazeDB/) | Canonical open → put → get → query | `swift run HelloBlazeDB` |
| [ReadmeSamples](Examples/ReadmeSamples/) | CI-verified README snippets | `swift run ReadmeSamples` |
| [CorePathSmoke](Examples/CorePathSmoke/) | Portable core path | `swift run CorePathSmoke` |
| [MVVMPattern](Examples/MVVMPattern/) | Repository + ViewModel without SwiftUI | `swift run MVVMPattern` |
| [C/hello_blazedb.c](Examples/C/hello_blazedb.c) | C ABI sample | see [Examples/C/README.md](Examples/C/README.md) |

### Conditional / preview / experimental

| Example | Label | Notes |
|---------|-------|-------|
| [VaporServer](Examples/VaporServer/) | Conditional | Embed sample; not a Package product |
| [Go preview](Examples/Go/README.md) | Preview | cgo recipe; no checked-in `.go` module |
| [SwiftUIExample.swift](Examples/SwiftUIExample.swift) | Sample file | Advanced raw-row patterns; default SwiftUI path is [SWIFTUI_DATABASE_PATTERNS](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Android / KMM samples | CI-validated; experimental packaging | [android-status.md](Docs/android-status.md) |

Sync and telemetry samples are deferred or conditional. They are not default onboarding.

---

## Documentation map

See the [documentation index](Docs/README.md) for canonical, advanced, conditional, and historical material.

### Get started

- [Getting Started](Docs/GettingStarted/README.md)
- [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) (includes Vapor embedding)
- [LINUX_GETTING_STARTED.md](Docs/GettingStarted/LINUX_GETTING_STARTED.md)
- [Examples/README.md](Examples/README.md)

### Understand the engine

- [Architecture](Docs/Architecture/README.md)
- [Encryption and key management](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)
- [Durability and recovery](Docs/Status/DURABILITY_MODE_SUPPORT.md)
- [Transactional writes](Docs/DEVELOPER_GUIDE.md#transactions)
- [Developer Guide](Docs/DEVELOPER_GUIDE.md)
- [API Reference](Docs/API/API_REFERENCE.md)
- [Indexing and performance](Docs/Performance/README.md)
- [Schema and migrations](Docs/MIGRATION.md)
- [Backup, export, and restore](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md#9-backups-restore-and-trust)

### Tools and integrations

- [Tools](Docs/Tools/README.md)
- [C ABI](Docs/Architecture/C_ABI_BYTE_KV.md)
- [Go preview](Examples/Go/README.md)
- [Benchmarks](Docs/Benchmarks/README.md) (methodology only; no raw vanity numbers here)
- [Why not SQLite?](Docs/GettingStarted/WHY_NOT_SQLITE.md) (fit comparison; measured numbers live under Benchmarks)

### Project information

- [Compatibility](Docs/COMPATIBILITY.md)
- [SECURITY.md](SECURITY.md) (reporting)
- [RELEASE.md](RELEASE.md) · [CHANGELOG.md](CHANGELOG.md)
- [ROADMAP.md](ROADMAP.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [Repository metrics](Docs/Meta/REPOSITORY_METRICS.md) (maintainer scale + health snapshot)

---

## Contributing

BlazeDB welcomes focused contributions across documentation, developer tooling, tests, platform support, and core correctness.

Start with:

- [Good first issues](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
- [Help wanted](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
- [Contribution guide](CONTRIBUTING.md)
- [Issue guide](Docs/Contributing/ISSUE_GUIDE.md)
- [Learning paths](Docs/Contributing/LEARNING_PATHS.md)
- [Roadmap](ROADMAP.md)

Comment on an issue before starting substantial work so scope and ownership are clear.

Setup, `./dev`, and PR expectations: [CONTRIBUTING.md](CONTRIBUTING.md). Codebase orientation: [CODEBASE_MAP](Docs/Architecture/CODEBASE_MAP.md).

---

## Project status

| | |
|--|--|
| Release | [v2.8.1](RELEASE.md) · [CHANGELOG](CHANGELOG.md) |
| Platforms | [COMPATIBILITY.md](Docs/COMPATIBILITY.md) |
| Roadmap | [ROADMAP.md](ROADMAP.md) (directional) |
| Security | [SECURITY.md](SECURITY.md) |
| License | MIT ([LICENSE](LICENSE)) |

### Repository scale

Approximate tracked size:

- ~101k source lines · ~229k test lines · ~200k documentation lines
- ~2.3× test-to-source line ratio · ~7,200 `test*` methods · ~1,100 Swift files
- ~66k lines in the `BlazeDB/` engine tree
- 28 SwiftPM targets across seven major subsystems: engine core, storage/WAL, query, crypto, transactions, C ABI, and CLI (plus experimental Android/KMM packaging)
- CI coverage on macOS, Linux, and Android/KMM paths

Full counts, CI-lane coverage, and review candidates: [Docs/Meta/REPOSITORY_METRICS.md](Docs/Meta/REPOSITORY_METRICS.md) (`./Scripts/repo-metrics.sh`).

Deferred packaging (sync / server / telemetry): [DISTRIBUTED_TRANSPORT_DEFERRED.md](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md).
