# Go wrapper preview (official package in v2.9.0)

Until then, call [`blazedb.h`](../../BlazeDBC/include/blazedb.h) via cgo against the **shared** library from v2.8.1+.

## Intended API

```go
package main

import (
    "log"

    "github.com/Mikedan37/blazedb-go" // planned
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

## Manager pattern

```go
type Storage interface {
    Put(key string, value []byte) error
    Get(key string) ([]byte, error)
    Delete(key string) error
}
```

## cgo sketch (v2.8.1+)

```go
/*
#cgo CFLAGS: -I/path/to/BlazeDB/BlazeDBC/include
#cgo LDFLAGS: -L/path/to/BlazeDB/.build/release -lBlazeDBC -Wl,-rpath,/path/to/BlazeDB/.build/release
#include "blazedb.h"
*/
import "C"
```

Do **not** link `libBlazeDBC.a` from Go unless you are prepared to pull in the entire Swift runtime by hand.
