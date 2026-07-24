# Go wrapper preview (not shipped in v0.1.0)

Official package target: **`blazedb-go`** in **v0.2.0**.

Until then, call [`blazedb.h`](../../BlazeDBC/include/blazedb.h) via cgo against `libBlazeDBC.a`, or wait for the wrapper.

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

Keep BlazeDB behind an interface so tests can swap in memory storage:

```go
type Storage interface {
    Put(key string, value []byte) error
    Get(key string) ([]byte, error)
    Delete(key string) error
}
```

The Go wrapper’s only job is Open / Put / Get / Delete / Close over the C ABI. No manager logic belongs there.

## Layout (planned)

```text
blazedb-go/
  cgo.go      # only file that imports "C"
  db.go
  errors.go
```

```c
/* #cgo LDFLAGS: -L/usr/local/lib -lBlazeDBC …Swift runtime… */
/* #include <blazedb.h> */
```
