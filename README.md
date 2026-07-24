# BlazeDB

BlazeDB is an encrypted embedded key-value database written in Swift with a stable C ABI, making it embeddable from Swift, Go, Rust, Python, and other native languages. One process, one library, no server.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![C ABI](https://img.shields.io/badge/C%20ABI-v0.1.0-green.svg)](BlazeDBC/include/blazedb.h)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20Linux%20%7C%20Android-lightgrey.svg)](Docs/COMPATIBILITY.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Embeddable ABI:** [v0.1.0](RELEASE.md) · **Swift package:** 2.7.x · [Getting started (Swift apps)](Docs/GettingStarted/README.md)

---

## Features

- **Encrypted** — AES-256-GCM at rest; password required in v0.1.0
- **Embedded** — runs in your process; no external database server
- **Byte-oriented KV** — UTF-8 keys, opaque value bytes
- **Swift-native engine** — one implementation, not a port per language
- **Stable C ABI** — `blazedb.h` is the contract for every wrapper
- **Cross-language** — Go, Rust, Python, Zig, C#… anything that can call C
- **No server** — open a file path and go
- **Durable** — WAL-backed crash recovery; ACID transactions on the Swift API
- **Raspberry Pi ready** — build once with Swift for Linux (aarch64), link from Go/C

---

## Architecture

Every language talks to BlazeDB through the same C ABI. The manager never needs to know Swift exists; the engine never needs to know Go exists.

```text
   Go     Rust     Python     Swift
     \      |        |         /
      \     |        |        /
       ▼    ▼        ▼       ▼
          BlazeDBC
       (stable C ABI)
              │
              ▼
        Swift Byte KV
              │
              ▼
        BlazeDB Engine
              │
              ▼
             Disk
```

Typed Swift models (`BlazeStorable`) are a convenience layer on top of the same engine. The embeddable path is bytes only.

Design contract: [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md)

---

## Five-minute start (C)

```c
#include <stdio.h>
#include <string.h>
#include <blazedb.h>

int main(void) {
    BlazeDB *db = blazedb_open("jobs.blaze", "DemoPass123!");
    if (!db) { fprintf(stderr, "open failed\n"); return 1; }

    const char *payload = "hello";
    if (blazedb_put(db, "job:42", payload, strlen(payload)) != BLAZEDB_OK) {
        fprintf(stderr, "put failed\n");
        blazedb_close(db);
        return 1;
    }

    void *data = NULL;
    size_t len = 0;
    if (blazedb_get(db, "job:42", &data, &len) == BLAZEDB_OK) {
        fwrite(data, 1, len, stdout);
        putchar('\n');
        blazedb_free(data);
    }

    blazedb_delete(db, "job:42");
    blazedb_close(db);
    return 0;
}
```

Full compileable sample: [Examples/C/hello_blazedb.c](Examples/C/hello_blazedb.c)

---

## Installation / build

Requires a Swift 6+ toolchain ([swift.org](https://www.swift.org/install/) on Linux/macOS, or Xcode on Apple platforms).

### Build the C library

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift build -c release --product BlazeDBC
```

### Artifacts

| Artifact | Location |
|----------|----------|
| Static library | `.build/release/libBlazeDBC.a` |
| Public header | `BlazeDBC/include/blazedb.h` (source tree; copy this) |

`libBlazeDBC.a` is a **static** archive that includes the BlazeDB engine objects needed by the C ABI. Linking a C or Go program also requires the **Swift runtime** / Foundation that your toolchain provides (same Swift used to build the archive).

### Install on a machine (e.g. Raspberry Pi)

```bash
sudo mkdir -p /usr/local/include /usr/local/lib
sudo cp BlazeDBC/include/blazedb.h /usr/local/include/
sudo cp .build/release/libBlazeDBC.a /usr/local/lib/
# On Linux, also ensure the Swift runtime libraries from your toolchain are on the link/rpath.
```

There is no separate `.so` in v0.1.0 — the published `BlazeDBC` product is static. Dynamic packaging can follow later without changing the ABI.

### Swift Package Manager (Swift apps)

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.5")
```

Then depend on `BlazeDB` (typed apps) or `BlazeDBC` (C ABI).

---

## Go example (wrapper coming next)

The official Go package is **not shipped in v0.1.0**. Target API for `blazedb-go`:

```go
db, err := blazedb.Open("manager.blaze", "DemoPass123!")
if err != nil {
    log.Fatal(err)
}
defer db.Close()

err = db.Put("job:42", []byte(`{"status":"queued"}`))
job, err := db.Get("job:42")
err = db.Delete("job:42")
```

Your manager should depend on a small `Storage` interface, not on BlazeDB types:

```go
type Storage interface {
    Put(key string, value []byte) error
    Get(key string) ([]byte, error)
    Delete(key string) error
}
```

Roadmap: **v0.2.0** ships `blazedb-go` as a thin cgo wrapper over `blazedb.h`. Until then, you can call the C API directly via cgo against `libBlazeDBC.a`.

Preview sketch: [Examples/Go/README.md](Examples/Go/README.md)

---

## ABI guarantees

Frozen in [`BlazeDBC/include/blazedb.h`](BlazeDBC/include/blazedb.h):

| Rule | Detail |
|------|--------|
| Opaque handle | `typedef struct BlazeDB BlazeDB;` — never inspect fields |
| Ownership | Buffers from `blazedb_get` must be released with `blazedb_free` |
| Password | `NULL` or `""` is invalid; open returns `NULL` |
| Stability | Published function signatures and behavior **never change** |
| Evolution | New capability only via new functions, enum values, flags, or versioned option structs (`blazedb_open_ex`, …) |

Byte semantics: keys are UTF-8; values are opaque; `get` returns exactly what `put` stored.

---

## Swift apps (typed API)

If you are writing a Swift app, you can stay on the typed facade:

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let db = try BlazeDB.open(name: "demo", password: "DemoPass123!")
try db.put(Bug(title: "Crash on launch", status: "open"))
```

Or use the same byte KV surface the C ABI wraps:

```swift
try db.put(key: "job:42", value: Data("hello".utf8))
let data = try db.get(key: "job:42")
try db.delete(key: "job:42")
```

More: [Docs/GettingStarted/README.md](Docs/GettingStarted/README.md) · `swift run HelloBlazeDB`

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [RELEASE.md](RELEASE.md) | v0.1.0 release notes |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md) | ABI + byte KV contract |
| [COMPATIBILITY.md](Docs/COMPATIBILITY.md) | Platform matrix |
| [Getting Started](Docs/GettingStarted/README.md) | Swift onboarding |

---

## Versioning

| Track | Current | Meaning |
|-------|---------|---------|
| **Embeddable C ABI** | **0.1.0** | `blazedb.h` stability track |
| Swift package | 2.7.x | App / SPM consumers |

Planned: **0.2.0** Go wrapper · **0.3.0** iterators / scans · **1.0.0** long-term ABI commitment

---

## License

MIT — see [LICENSE](LICENSE).
