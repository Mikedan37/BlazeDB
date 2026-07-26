# BlazeDB v2.8.1 — Dynamic BlazeDBC

**Tag:** `v2.8.1`  
**Date:** 2026-07-24

BlazeDBC is now built as a **shared library** so Go/cgo (and other FFI hosts) link `-lBlazeDBC` and pick up the Swift runtime through the dynamic loader—instead of unresolved `swift_retain` / `swift_release` from a static archive.

This release changes the library packaging and link workflow, not the published C ABI.

## Summary

v2.8.0 introduced the documented [C ABI interoperability surface](Docs/Architecture/C_ABI_BYTE_KV.md). v2.8.1 makes that ABI practical to embed dynamically.

## Highlights

- **`BlazeDBC` product is `.dynamic`**
  - Linux: `libBlazeDBC.so`
  - macOS: `libBlazeDBC.dylib`
- Optional **`BlazeDBCStatic`** SwiftPM product remains for consumers that still want `libBlazeDBC.a`
- **ABI unchanged** — same `blazedb.h`, same symbols; packaging and link workflow changed

## Compatibility and migration

There are no C API or ABI breaking changes. This release changes the library packaging and link workflow, not the published symbols or header.

Consumers that previously linked the static archive and manually supplied Swift runtime libraries should instead link the shared library:

```text
-L.build/release -lBlazeDBC -Wl,-rpath,.build/release
```

The example above is for local checkout testing. Installed applications should use an rpath or library install location appropriate for their deployment environment (for example `@rpath` / `@loader_path` and install names on macOS, or `$ORIGIN`-relative paths on Linux).

## Install / try

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
git checkout v2.8.1
swift build -c release --product BlazeDBC
# Header:  BlazeDBC/include/blazedb.h
# Shared:  .build/release/libBlazeDBC.dylib   (macOS)
#          .build/release/libBlazeDBC.so      (Linux)
```

### Go / cgo linking

For local checkout testing:

```c
/*
#cgo CFLAGS: -I${SRCDIR}/../../BlazeDBC/include
#cgo LDFLAGS: -L${SRCDIR}/../../.build/release -lBlazeDBC -Wl,-rpath,${SRCDIR}/../../.build/release
#include "blazedb.h"
*/
import "C"
```

Installed applications should use a loader path or install prefix appropriate for their deployment environment. See [Examples/Go/README.md](Examples/Go/README.md).

SwiftPM:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

## Known limitations

- Host still needs a compatible Swift runtime available at load time (system or toolchain `rpath`). The dynamic library reduces manual Swift-runtime link configuration; it does not eliminate the runtime dependency.
- Official versioned `blazedb-go` packaging is directional work after checked-in Go/cgo smoke sources exist; not a guarantee of a particular release (see [ROADMAP.md](ROADMAP.md) and [Examples/Go/README.md](Examples/Go/README.md))
