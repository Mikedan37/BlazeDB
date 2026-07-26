# BlazeDB

BlazeDB is an encrypted embedded document database written in Swift. It runs inside your process, stores data locally, and does not require a separate database server or network connection.

It is intended for applications that need private local persistence, typed Swift models, transactions, and inspection tooling without operating a separate database service.

You can use BlazeDB from Swift applications, from the `blazedb` CLI, or through its documented C ABI. Published C symbols and signatures follow the compatibility rules defined in the ABI documentation. The primary open-source product is the embedded Swift engine. The C ABI is one way to reach that same engine, not a replacement for the Swift product story.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/badge/release-v2.8.1-green.svg)](RELEASE.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Current release:** [v2.8.1](RELEASE.md) · [Getting started](Docs/GettingStarted/README.md) · [Documentation index](Docs/README.md) · [Contributing](CONTRIBUTING.md) · [Compatibility](Docs/COMPATIBILITY.md)

### Platforms

- **Runtime CI:** macOS, Linux
- **Declared and compile-tested:** iOS, watchOS, tvOS, visionOS
- **Experimental:** Android cross-compilation, KMM sample, portable MVVM pattern

See [Compatibility](Docs/COMPATIBILITY.md) for minimum versions and support details. Android and KMM notes: [android-status.md](Docs/android-status.md).

---

## What ships by default

`Package.swift`, tests, and CI are the source of truth when documentation and source layout disagree.

| Area | Product status | Documentation |
|------|----------------|---------------|
| Embedded storage, typed and raw APIs, transactions, durability, import/export, inspection APIs, CLI | **Default shipped core** | Maintained |
| Migrations, indexing, search tuning, and manual mapping | **Advanced and supported** | Maintained entry points |
| Schema validation | **Advanced and supported** | Dedicated guide under consolidation |
| Distributed sync, server/discovery, full telemetry packaging | **Conditional or deferred** | Not default onboarding |

### Guarantees and boundaries

BlazeDB’s public database-opening APIs require a password, and persisted data is encrypted at rest with AES-GCM. Durability for the default client path is WAL-backed; see [Durability Mode Support](Docs/Status/DURABILITY_MODE_SUPPORT.md) for modes, fsync behavior, and recovery details. The engine is single-process oriented. Multi-writer and network filesystem behavior are not the primary design target.

---

## Choose your path

| If you want to… | Start here |
|-----------------|------------|
| Build a Swift app | [Start Here](#start-here-new-users) · [Getting Started](Docs/GettingStarted/README.md) |
| Try the library from this clone | `swift run HelloBlazeDB` |
| Inspect a database in a terminal | [CLI](#cli) |
| Contribute tests or storage changes | [Contributing](#contributing) · [CONTRIBUTING.md](CONTRIBUTING.md) |
| Embed from C or call C from another language | [C ABI](#cross-language-c-abi) · [C_ABI_BYTE_KV](Docs/Architecture/C_ABI_BYTE_KV.md) |
| Call from Go via cgo | [Go integration preview](#go-integration-preview) · [Examples/Go](Examples/Go/README.md) |

---

<a id="start-here-new-users"></a>

## Start Here (new users)

No separate database server is involved. BlazeDB stores each named database locally using an encrypted database file and its required durability metadata. You describe records with ordinary Swift structs. `put` saves a value, `get` loads one record when you know its namespaced record ID, and `query` returns a filtered list.

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

The `"bug"` in `query("bug")` is a namespace label for that kind of record. It is not a separate SQL table. Namespaced record IDs look like `"bug:<uuid>"` (namespace + the model’s `id`).

| Step | What it does |
|------|----------------|
| `open` | Opens or creates your local encrypted database |
| `put` | Saves a struct |
| `get("bug:…")` | Loads one bug by namespaced record ID |
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

Depend on the `BlazeDB` product. For a longer walkthrough, see [HOW_TO_USE_BLAZEDB.md](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md). For SwiftUI wiring, see [Docs/GettingStarted](Docs/GettingStarted/README.md) and [Examples/SwiftUIExample.swift](Examples/SwiftUIExample.swift).

---

## CLI

The `blazedb` executable provides interactive database access, inspection commands, and a REPL.

```bash
swift build --product blazedb
.build/debug/blazedb help
.build/debug/blazedb start
```

From a package checkout, contributors can use `./dev` for repository workflows (tests, tiers, experiments). The wrapper reuses the existing developer build when possible:

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

Requires Swift 6.0+ ([swift.org](https://www.swift.org/install/) or Xcode on Apple platforms). Matches `swift-tools-version:6.0` in `Package.swift` and the minimum in [Compatibility](Docs/COMPATIBILITY.md).

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

Swift apps talk to `BlazeDB` / `BlazeDBCore` directly. Languages that can call C can use the same engine through `BlazeDBC` (`blazedb.h`). Distributed sync and telemetry live outside the default core packaging path.

```text
Swift apps / blazedb CLI
        │
        ▼
   BlazeDB / BlazeDBCore
        │
        ├── typed and raw APIs
        ├── queries and indexes
        ├── transactions + WAL recovery
        └── encrypted pages → disk

C / FFI hosts ──► BlazeDBC (documented C ABI) ──► same engine
```

Deeper design: [Docs/Architecture/README.md](Docs/Architecture/README.md).

---

## Cross-language C ABI

The C ABI can be used by C and by languages capable of calling C libraries, including Go, Rust, and Python. That is interoperability capability, not a claim that every host language has an official maintained wrapper. Published symbols are stability-governed; new functions may be added later. See [C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) for what that promise covers (stable symbols and signatures, documented behavior, opaque handles; not struct layout, universal binary drop-in, or major-version forever compatibility).

```c
#include <blazedb.h>

BlazeDB *db = blazedb_open("jobs.blaze", "DemoPass123!");
blazedb_put(db, "job:42", "hello", 5);
/* get / free / delete / close: Examples/C/hello_blazedb.c */
```

Interoperability rules and ownership: [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) · [Examples/C](Examples/C/).

---

## Go integration preview

The documented C ABI path works end to end through `BlazeDBC` (see the C sample and `BlazeDBCSmokeTests`). Go hosts can call the same surface via cgo. This repository documents that recipe; it does not yet include checked-in `.go` sources or a separately versioned Go module.
See [Examples/Go/README.md](Examples/Go/README.md) for setup and current limitations.

---

## Advanced but supported

These belong in the engine and are public, but they are not day-one onboarding. Prefer the [documentation index Advanced table](Docs/README.md#advanced-but-supported) for current entry points:

- Migrations, indexing, search tuning, manual mapping: [Developer Guide](Docs/DEVELOPER_GUIDE.md) · [API Reference](Docs/API/API_REFERENCE.md) · [Docs/MIGRATION.md](Docs/MIGRATION.md)
- Schema validation: supported APIs in the API Reference; dedicated guides are still under consolidation

After Getting Started works, deepen from those links rather than older Status snapshots.

---

## Tools and applications

| Tool | Role | Status |
|------|------|--------|
| `blazedb` | Interactive access, inspection, and REPL | Default shipped |
| [BlazeStudio](BlazeStudio/) | macOS database browser | Companion app |
| [BlazeDBVisualizer](BlazeDBVisualizer/) | Storage inspection UI | Developer tool |
| `BlazeDoctor` / `BlazeDump` / `BlazeInfo` | Maintenance utilities | Developer tools |
| `BlazeDBBenchmarks` | Release performance workloads | Developer tool |
| `./dev` | Contributor test, tier, and experiment commands | Contributor tooling |

Interactive IDE schemes and Archive notes: [Docs/Build/XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md).

---

## Examples

Curated entry points (full catalog: [Examples/README.md](Examples/README.md)):

| Example | Purpose | Command |
|---------|---------|---------|
| [HelloBlazeDB](Examples/HelloBlazeDB/) | Canonical open → put → get → query | `swift run HelloBlazeDB` |
| [CorePathSmoke](Examples/CorePathSmoke/) | Portable core path smoke | `swift run CorePathSmoke` |
| [MVVMPattern](Examples/MVVMPattern/) | Repository + ViewModel without SwiftUI | `swift run MVVMPattern` |
| [ReadmeSamples](Examples/ReadmeSamples/) | CI-verified README snippets | `swift run ReadmeSamples` |
| [C/hello_blazedb.c](Examples/C/hello_blazedb.c) | C ABI sample | see [Examples/C/README.md](Examples/C/README.md) |
| [Go preview](Examples/Go/README.md) | Documented cgo recipe (no checked-in Go module yet) | see that README |

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

Keep PRs narrow. Prefer `./dev` for focused tests and tiers. Use Xcode schemes for interactive Run, Profile, Analyze, and Archive. Storage-format, WAL, encryption, and recovery changes are high risk. Read the architecture and durability documentation, follow the [storage-change checklist](Docs/Contributing/STORAGE_CHANGE_CHECKLIST.md), and include the exact validation commands run in the PR description.

---

## Documentation map

The [documentation index](Docs/README.md) is the authority map for what is canonical, advanced, conditional, maintainer-only, internal, or historical. Use this table only as a short front door:

| Doc | Purpose |
|-----|---------|
| [Getting Started](Docs/GettingStarted/README.md) | First Swift path |
| [HOW_TO_USE](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Longer usage guide |
| [Docs/README.md](Docs/README.md) | Full navigation and support-state framing |
| [Architecture](Docs/Architecture/README.md) | Internals |
| [C ABI + byte KV](Docs/Architecture/C_ABI_BYTE_KV.md) | Documented C interoperability surface |
| [Compatibility](Docs/COMPATIBILITY.md) | Platforms |
| [Security](SECURITY.md) | Vulnerability reporting |
| [CHANGELOG](CHANGELOG.md) / [RELEASE](RELEASE.md) | History and current release |
| [ROADMAP](ROADMAP.md) | Directional priorities (not release guarantees) |
| [Product audit](Docs/Product/PRODUCT_AUDIT.md) | Evidence-based product/repo audit behind the roadmap |

---

## Conditional and deferred features

Distributed sync, discovery, server paths, and full telemetry packaging are outside the default OSS product. See [Distributed Transport Deferred](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) and the Conditional section in [Docs/README.md](Docs/README.md). Do not treat sync example files as the default onboarding path.

---

## Roadmap

See [ROADMAP.md](ROADMAP.md) for current priorities and exploratory work.
Planned items are directional and are not release guarantees.

Near-term direction includes contributor safety for storage changes, on-disk compatibility fixtures, truthful Go packaging (sources + CI, then a versioned module), and additive C ABI evolution such as iterators. Evidence: [Docs/Product/PRODUCT_AUDIT.md](Docs/Product/PRODUCT_AUDIT.md).

---

## Project status and limitations

**v2.8.x** is the current embedded core release: Swift apps, CLI, and the documented `BlazeDBC` interoperability surface. See [CHANGELOG.md](CHANGELOG.md) / [RELEASE.md](RELEASE.md) for shipped notes.

Known boundaries: single-process embedded model; password required; distributed modules are deferred from default packaging; some Status docs under `Docs/Status/` are historical and are not the contribution entry path.

---

## Security

Report vulnerabilities according to [SECURITY.md](SECURITY.md). Do not open public issues for sensitive reports.

---

## License

MIT. See [LICENSE](LICENSE).
