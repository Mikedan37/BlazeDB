# BlazeDB v2.8.1 — Dynamic BlazeDBC

**Tag:** `v2.8.1`  
**Date:** 2026-07-24

BlazeDBC is now built as a **shared library** so Go/cgo (and other FFI hosts) link `-lBlazeDBC` and pick up the Swift runtime through the dynamic loader—instead of unresolved `swift_retain` / `swift_release` from a static archive.

## Summary

v2.8.0 introduced the stable C ABI. v2.8.1 fixes how that ABI is packaged for embedding.

## Highlights

- **`BlazeDBC` product is `.dynamic`**
  - Linux: `libBlazeDBC.so`
  - macOS: `libBlazeDBC.dylib`
- Optional **`BlazeDBCStatic`** product remains for consumers that still want `libBlazeDBC.a`
- **ABI unchanged** — same `blazedb.h`, same symbols

## Breaking changes

None for the C API. Link line changes from static archive + manual Swift libs to:

```text
-L.build/release -lBlazeDBC -Wl,-rpath,.build/release
```

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

### Go / cgo sketch

```c
/*
#cgo CFLAGS: -I${SRCDIR}/../../BlazeDBC/include
#cgo LDFLAGS: -L${SRCDIR}/../../.build/release -lBlazeDBC -Wl,-rpath,${SRCDIR}/../../.build/release
#include "blazedb.h"
*/
import "C"
```

Adjust paths for your install prefix (`/usr/local/lib`, etc.).

SwiftPM:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

## Known limitations

- Host still needs a compatible Swift runtime available at load time (system or toolchain `rpath`)
- Official `blazedb-go` wrapper still planned for **v2.9.0**
