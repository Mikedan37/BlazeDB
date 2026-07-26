# BlazeDB

BlazeDB is an **encrypted embedded database written in Swift**. One process, one library, no server.

Use it:

- directly from **Swift applications**
- through the **`blazedb` CLI**
- from other languages through the **stable C ABI**

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/badge/release-v2.8.1-green.svg)](RELEASE.md)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Current release:** [v2.8.1](RELEASE.md) · [Getting started](Docs/GettingStarted/README.md) · [Contributing](CONTRIBUTING.md)

---

## Why BlazeDB

- **Encrypted local persistence** — AES-256-GCM at rest; password required
- **Typed Swift models** — `BlazeStorable` with put / get / query
- **Transactions + WAL** — crash-safe recovery; ACID on the Swift API
- **CLI tools** — inspect and maintain databases without writing an app
- **Cross-language C ABI** — same engine from Go, Rust, Python, C, and more

---

<a id="start-here-new-users"></a>

## Start Here (new users)

Add the package:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

Depend on `"BlazeDB"`, then:

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
try db.put(Bug(title: "Crash on launch", status: "open"))
let openBugs: [Bug] = try db.query("bug")
    .where("status", equals: "open")
    .all()
```

From this repo:

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

More: [Docs/GettingStarted/README.md](Docs/GettingStarted/README.md)

**Also:** [CLI usage](#cli) · [C embedding](#cross-language-embedding-c-abi) · [Contributing](#contributing-in-five-minutes)

---

## CLI

Build and run the interactive CLI:

```bash
swift build --product blazedb
.build/debug/blazedb help
.build/debug/blazedb start          # pick a database → REPL
```

Or from a checkout after the first build: `swift run blazedb`.

Contributors use the repo wrapper (rebuilds the CLI only when needed):

```bash
./dev help
```

---

## Installation

Requires Swift 6+ ([swift.org](https://www.swift.org/install/) or Xcode on Apple platforms).

### Swift apps (SPM)

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

Then depend on `BlazeDB` (typed apps) or `BlazeDBC` (C ABI shared library).

### Embeddable C library

```bash
swift build -c release --product BlazeDBC
```

| Artifact | Location |
|----------|----------|
| Shared library | `.build/release/libBlazeDBC.dylib` (macOS) / `libBlazeDBC.so` (Linux) |
| Header | `BlazeDBC/include/blazedb.h` |

Link with `-lBlazeDBC` and an appropriate rpath. Details: [BlazeDBC/README.md](BlazeDBC/README.md) · [RELEASE.md](RELEASE.md)

---

## Cross-language embedding (C ABI)

Every non-Swift language talks to the same engine through [`blazedb.h`](BlazeDBC/include/blazedb.h):

```text
   Go     Rust     Python     Swift apps
     \      |        |         /
      \     |        |        /
       ▼    ▼        ▼       ▼
          BlazeDBC  (stable C ABI)
              │
        Swift engine → disk
```

### C (five minutes)

```c
#include <blazedb.h>

BlazeDB *db = blazedb_open("jobs.blaze", "DemoPass123!");
blazedb_put(db, "job:42", "hello", 5);
/* get / delete / blazedb_close — see Examples/C/hello_blazedb.c */
```

Full sample: [Examples/C/hello_blazedb.c](Examples/C/hello_blazedb.c)

### Go

Official `blazedb-go` is **not** in v2.8.1 yet (planned for **v2.9.0**). Until then, call the C API via cgo against `libBlazeDBC`. Preview: [Examples/Go/README.md](Examples/Go/README.md)

### ABI rules (short)

Opaque `BlazeDB *` handle · buffers from `blazedb_get` freed with `blazedb_free` · passwords required · published signatures do not change — evolve only via new symbols. Full contract: [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md)

---

## Tools and applications

| Tool | Role |
|------|------|
| `blazedb` | Interactive picker + REPL |
| [BlazeStudio](BlazeStudio/) | macOS app for browsing databases |
| [BlazeDBVisualizer](BlazeDBVisualizer/) | Visualization / inspection |
| `BlazeDoctor` / `BlazeDump` / `BlazeInfo` | Maintenance utilities |
| `BlazeDBBenchmarks` | Performance workloads (Profile in Xcode) |
| `./dev` | Contributor test / tier / experiment interface |

Docs: [Docs/Tools/README.md](Docs/Tools/README.md) · [Docs/Build/XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md)

---

## Contributing in five minutes

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
./dev help
./dev test BPlusTreeNodeTests.createsSimpleTree
./dev tier0
```

| Next | Link |
|------|------|
| Full contributor guide | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Test tiers / CI | [Docs/Testing/CI_AND_TEST_TIERS.md](Docs/Testing/CI_AND_TEST_TIERS.md) |
| Lean Xcode schemes | [Docs/Build/XCODE_SCHEMES.md](Docs/Build/XCODE_SCHEMES.md) |
| Architecture | [Docs/Architecture/README.md](Docs/Architecture/README.md) |
| Experiments | [Experiments/README.md](Experiments/README.md) |
| Benchmarks | [Docs/Benchmarks/README.md](Docs/Benchmarks/README.md) |

Keep PRs narrow. Prefer `./dev` for focused tests and tiers; use Xcode schemes for interactive Run / Profile / Analyze / Archive.

---

## Documentation map

| Doc | Purpose |
|-----|---------|
| [Getting Started](Docs/GettingStarted/README.md) | First Swift app |
| [Docs/README.md](Docs/README.md) | Full documentation index |
| [C ABI + byte KV](Docs/Architecture/C_ABI_BYTE_KV.md) | Embedder contract |
| [COMPATIBILITY.md](Docs/COMPATIBILITY.md) | Platform matrix |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [RELEASE.md](RELEASE.md) | Current release notes |

---

## Project status / roadmap

| Version | Focus |
|---------|--------|
| **2.8.x** | Encrypted embedded core · Swift apps · CLI · stable C ABI (`BlazeDBC` shared library) |
| **2.9.0** | Official `blazedb-go` wrapper |
| **2.10.0** | Additional C APIs (iterators / scans) |
| **3.0.0** | Intentional breaking API or on-disk format change |

Default OSS product: embedded encrypted engine, typed/raw Swift APIs, durability, CLI. Distributed sync / full telemetry are conditional or deferred — see [Docs/README.md](Docs/README.md).

---

## License

MIT — see [LICENSE](LICENSE).
