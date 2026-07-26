# Go integration preview

The documented C ABI path works end to end through the `BlazeDBC` shared library (C sample + `BlazeDBCSmokeTests`). Go hosts can call the same surface via cgo.

This folder currently documents the **cgo linking recipe** and a **target wrapper API shape**. It does **not** yet contain checked-in `.go` sources, and there is **no** separately versioned Go module.

Productization (checked-in smoke sources, CI gate, then an official module) is directional work; see [ROADMAP.md](../../ROADMAP.md) and [PRODUCT_AUDIT.md](../../Docs/Product/PRODUCT_AUDIT.md).

Homepage: [Go integration preview](../../README.md#go-integration-preview).

## Build BlazeDBC first

```bash
swift build -c release --product BlazeDBC
# Header:  BlazeDBC/include/blazedb.h
# Shared:  .build/release/libBlazeDBC.dylib   (macOS)
#          .build/release/libBlazeDBC.so      (Linux)
```

## cgo linking (local checkout)

```go
/*
#cgo CFLAGS: -I/path/to/BlazeDB/BlazeDBC/include
#cgo LDFLAGS: -L/path/to/BlazeDB/.build/release -lBlazeDBC -Wl,-rpath,/path/to/BlazeDB/.build/release
#include "blazedb.h"
*/
import "C"
```

Adjust paths for your install prefix. Do **not** link `libBlazeDBC.a` from Go unless you are prepared to pull in the entire Swift runtime by hand. Prefer the shared library product.

Call the C functions from [`blazedb.h`](../../BlazeDBC/include/blazedb.h) (`blazedb_open`, `blazedb_put`, `blazedb_get`, `blazedb_free`, `blazedb_delete`, `blazedb_close`) and follow ownership rules in [C_ABI_BYTE_KV.md](../../Docs/Architecture/C_ABI_BYTE_KV.md).

Installed applications should use a loader path or install prefix appropriate for their deployment environment (for example `@rpath` / `@loader_path` on macOS, or `$ORIGIN`-relative paths on Linux).

## Target wrapper API (not a published module)

The following shows the intended shape of a future official package. The import path is not installable until a real module exists and is versioned.

```go
package main

import (
    "log"

    blazedb "github.com/Mikedan37/blazedb-go" // planned module name; not published yet
)

func main() {
    db, err := blazedb.Open("manager.blaze", "DemoPass123!")
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    if err := db.Put("job:42", []byte(`{"status":"queued"}`)); err != nil {
        log.Fatal(err)
    }

    job, err := db.Get("job:42")
    if err != nil {
        log.Fatal(err)
    }
    log.Printf("job=%s", job)

    if err := db.Delete("job:42"); err != nil {
        log.Fatal(err)
    }
}
```

## Current support boundaries

- C ABI byte-KV surface is the supported cross-language contract
- Go is a documented cgo consumer of that surface; no checked-in Go module yet
- Not a claim of full Go API coverage beyond `blazedb.h`
- Swift runtime must still be available at load time for `BlazeDBC`
