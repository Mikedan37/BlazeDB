# BlazeDB

BlazeDB is an encrypted embedded document database written in Swift. It runs inside your process, stores data in a local encrypted file, and does not require a separate database server or network connection.

You can use it from Swift applications, from the `blazedb` CLI, and from other languages through a stable C ABI. The default open-source package is the Swift embedded core. The C ABI is one way to reach that same engine, not a replacement for the Swift product story.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/badge/release-v2.8.1-green.svg)](RELEASE.md)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Current release:** [v2.8.1](RELEASE.md) · [Getting started](Docs/GettingStarted/README.md) · [Documentation index](Docs/README.md) · [Contributing](CONTRIBUTING.md)

---

## What ships by default

| Area | Status |
|------|--------|
| Embedded encrypted engine, typed and raw Swift APIs, transactions, WAL-backed recovery, import/export, health/stats, CLI | **Default shipped core** |
| Migrations, schema validation, indexing and search tuning, manual mapping | **Advanced but supported** |
| Distributed sync, server/discovery, full telemetry packaging | **Conditional or deferred** (source may exist; not the default OSS story) |

Source present in the tree does not always mean default runtime support. Trust `Package.swift`, CI, and the [documentation index](Docs/README.md) over folder names.

### Guarantees and boundaries

BlazeDB encrypts at rest (AES-256-GCM) and requires a password. Durability is WAL-backed for the core write path; see [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) for the exact contract. The engine is single-process oriented. Multi-writer and network filesystem behavior are not the primary design target.

---

## Choose your path

| If you want to… | Start here |
|-----------------|------------|
| Build a Swift app | [Start Here](#start-here-new-users) · [Getting Started](Docs/GettingStarted/README.md) |
| Try the library from this clone | `swift run HelloBlazeDB` |
| Inspect a database in a terminal | [CLI](#cli) |
| Contribute tests or storage changes | [Contributing](#contributing) · [CONTRIBUTING.md](CONTRIBUTING.md) |
| Embed from C / Go / other languages | [C ABI](#cross-language-c-abi) · [C_ABI_BYTE_KV](Docs/Architecture/C_ABI_BYTE_KV.md) |

---

<a id="start-here-new-users"></a>

## Start Here (new users)

No separate database server is involved. BlazeDB keeps one encrypted file per database name. You describe records with ordinary Swift structs. `put` saves a value, `get` loads one record when you know its id string, and `query` returns a filtered list.

Read the sample top to bottom: `open` → `put` → `get` → `query`.

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

let loaded: Bug? = try db.get("bug:\(bug.id.uuidString)")
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

The `"bug"` in `query("bug")` is a namespace label for that kind of record. It is not a separate SQL table. Id strings look like `"bug:<uuid>"`.

| Step | What it does |
|------|----------------|
| `open` | Opens or creates your encrypted file |
| `put` | Saves a struct |
| `get("bug:…")` | Loads one bug by id |
| `query("bug")…` | Lists or filters bugs |

### Try it from this repo

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

### Add the package to your app

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

Depend on the `BlazeDB` product. For a longer walkthrough, see [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md). For SwiftUI wiring, see [Docs/GettingStarted](Docs/GettingStarted/README.md) and `Examples/SwiftUIExample.swift`.

---

## CLI

The `blazedb` executable opens databases interactively and runs a REPL.

```bash
swift build --product blazedb
.build/debug/blazedb help
.build/debug/blazedb start
```

From a package checkout, contributors can use `./dev` for repository workflows (tests, tiers, experiments). That wrapper rebuilds the CLI only when `BlazeShell`, `BlazedbCLI`, or `Package.swift` changed:

```bash
./dev help
./dev tiers
./dev tests bplus
./dev test BPlusTreeNodeTests.createsSimpleTree
./dev tier0
```

Full process: [CONTRIBUTING.md](CONTRIBUTING.md). Tool notes: [Docs/Tools/README.md](Docs/Tools/README.md).

---

## Installation

Requires Swift 6+ ([swift.org](https://www.swift.org/install/) or Xcode on Apple platforms).

**Swift apps:** add the SPM dependency above and import `BlazeDB`.

**C library (FFI hosts):**

```bash
swift build -c release --product BlazeDBC
```

| Artifact | Location |
|----------|----------|
| Shared library | `.build/release/libBlazeDBC.dylib` (macOS) or `libBlazeDBC.so` (Linux) |
| Header | `BlazeDBC/include/blazedb.h` |

Link with `-lBlazeDBC` and an rpath appropriate for your host. Details: [BlazeDBC/README.md](BlazeDBC/README.md) · [RELEASE.md](RELEASE.md).

---

## Architecture summary

Swift apps talk to `BlazeDB` / `BlazeDBCore` directly. Other languages talk to the same engine through `BlazeDBC` (`blazedb.h`). Distributed sync and telemetry live outside the default core packaging path.

```text
Swift apps / blazedb CLI
        │
        ▼
   BlazeDB / BlazeDBCore
        │
        ├── typed models (BlazeStorable)
        ├── raw / byte APIs
        └── WAL + encrypted pages → disk

Other languages ──► BlazeDBC (C ABI) ──► same engine
```

Deeper design: [Docs/Architecture/README.md](Docs/Architecture/README.md).

---

## Cross-language C ABI

The stable C ABI is the embed path for Go, Rust, Python, C, and similar hosts. Official language wrappers are still rolling out; `blazedb-go` is planned, not shipped in v2.8.1.

```c
#include <blazedb.h>

BlazeDB *db = blazedb_open("jobs.blaze", "DemoPass123!");
blazedb_put(db, "job:42", "hello", 5);
/* get / free / delete / close: Examples/C/hello_blazedb.c */
```

Contract and ownership rules: [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) · [Examples/C](Examples/C/) · [Examples/Go](Examples/Go/).

---

## Advanced but supported

These belong in the engine and are documented, but they are not day-one onboarding:

- Migrations and schema evolution
- Schema validation
- Indexing and search tuning
- Manual `BlazeDocument` mapping

Start from the [Developer Guide](Docs/DEVELOPER_GUIDE.md) and [API Reference](Docs/API/API_REFERENCE.md) after the Getting Started path works.

---

## Tools and applications

| Tool | Role |
|------|------|
| `blazedb` | Database picker and REPL |
| [BlazeStudio](BlazeStudio/) | macOS browsing app (Archive from its own Xcode project) |
| [BlazeDBVisualizer](BlazeDBVisualizer/) | Inspection UI (Archive from its own Xcode project) |
| `BlazeDoctor` / `BlazeDump` / `BlazeInfo` | Maintenance utilities |
| `BlazeDBBenchmarks` | Release performance workloads |
| `./dev` | Contributor test, tier, and experiment commands |

Interactive IDE schemes stay lean: [Docs/Build/XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md).

---

## Examples

Curated entry points (full catalog: [Examples/README.md](Examples/README.md)):

| Example | Purpose | Command |
|---------|---------|---------|
| [HelloBlazeDB](Examples/HelloBlazeDB/) | Canonical open → put → get → query | `swift run HelloBlazeDB` |
| [CorePathSmoke](Examples/CorePathSmoke/) | Portable core path smoke | `swift run CorePathSmoke` |
| [MVVMPattern](Examples/MVVMPattern/) | Repository + ViewModel without SwiftUI | `swift run MVVMPattern` |
| [ReadmeSamples](Examples/ReadmeSamples/) | CI-verified README snippets | `swift run ReadmeSamples` |
| [C/hello_blazedb.c](Examples/C/hello_blazedb.c) | Stable C ABI sample | see [Examples/C/README.md](Examples/C/README.md) |

Sync, telemetry, and some server samples are conditional or deferred. Treat them as design or gated code unless the docs say otherwise.

---

## Benchmarks and profiling

Repeatable measurements come from the `BlazeDBBenchmarks` target in **Release**. Use Xcode **Product → Profile** on the shared `BlazeDBBenchmarks` scheme (Time Profiler, Allocations, File Activity, System Trace) when you need to explain CPU, allocations, or I/O.

Do not Profile the `blazedb` scheme with `dev test …` arguments. That mostly measures dispatcher and `swift test` overhead, not storage work.

Methodology and caveats: [Docs/Benchmarks/README.md](Docs/Benchmarks/README.md). This README does not publish raw throughput numbers; those need environment and methodology context.

---

## Contributing

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
./dev help
./dev test BPlusTreeNodeTests.createsSimpleTree
./dev tier0
```

| Topic | Doc |
|-------|-----|
| Full contribution process | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Test tiers and CI | [Docs/Testing/CI_AND_TEST_TIERS.md](Docs/Testing/CI_AND_TEST_TIERS.md) |
| Xcode schemes | [Docs/Build/XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md) |
| Experiments | [Experiments/README.md](Experiments/README.md) |
| Architecture | [Docs/Architecture/README.md](Docs/Architecture/README.md) |

Keep PRs narrow. Prefer `./dev` for focused tests and tiers. Use Xcode schemes for interactive Run, Profile, Analyze, and Archive. Storage-format, WAL, encryption, and recovery changes are high risk: read the architecture and durability docs, and list the exact validation commands you ran.

---

## Documentation map

The [documentation index](Docs/README.md) is the authority map for what is canonical, advanced, conditional, maintainer-only, internal, or historical. Use this table only as a short front door:

| Doc | Purpose |
|-----|---------|
| [Getting Started](Docs/GettingStarted/README.md) | First Swift path |
| [HOW_TO_USE](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Longer usage guide |
| [Docs/README.md](Docs/README.md) | Full navigation and support-state framing |
| [Architecture](Docs/Architecture/README.md) | Internals |
| [C ABI + byte KV](Docs/Architecture/C_ABI_BYTE_KV.md) | Embedder contract |
| [Compatibility](Docs/COMPATIBILITY.md) | Platforms |
| [Security](SECURITY.md) | Vulnerability reporting |
| [CHANGELOG](CHANGELOG.md) / [RELEASE](RELEASE.md) | History and current release |

---

## Conditional and deferred features

Distributed sync, discovery, server paths, and full telemetry packaging are outside the default OSS product. See [Distributed Transport Deferred](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) and the Conditional section in [Docs/README.md](Docs/README.md). Do not treat sync example files as the default onboarding path.

---

## Project status and limitations

| Version | Focus |
|---------|--------|
| **2.8.x** | Encrypted embedded core, Swift apps, CLI, stable `BlazeDBC` shared library |
| **2.9.0** | Planned official `blazedb-go` wrapper |
| **2.10.0** | Planned additional C APIs (iterators / scans) |
| **3.0.0** | Intentional breaking API or on-disk format change |

Known boundaries: single-process embedded model; password required; distributed modules are deferred from default packaging; some Status docs under `Docs/Status/` are historical and are not the contribution entry path.

---

## Security

Report vulnerabilities according to [SECURITY.md](SECURITY.md). Do not open public issues for sensitive reports.

---

## License

MIT. See [LICENSE](LICENSE).
