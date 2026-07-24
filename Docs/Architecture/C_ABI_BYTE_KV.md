# Stable C ABI + Byte KV Design

**Status:** Implemented (v0.1.0) — commit `ac689c1d`  
**Audience:** Engine maintainers and language-binding authors  
**Header:** [`BlazeDBC/include/blazedb.h`](../../BlazeDBC/include/blazedb.h)

## Goal

Make BlazeDB embeddable from any language that can call C, without exposing Swift types, JSON, or `BlazeStorable`. The first non-Swift consumer is expected to be a Go manager behind a `Storage` interface.

## Layering

```text
   Go     Rust     Python     Swift (typed)
     \      |        |         /
          BlazeDBC  (stable C ABI)
              │
        Swift Byte KV API
              │
        BlazeDB Engine
              │
             Disk
```

There is one storage implementation. The C ABI only speaks bytes. Typed Swift APIs remain available as a convenience on the same engine.

## Compatibility rule (day one)

Once a C function is published, its **signature and behavior never change**.

New capabilities only via:

- new functions
- new enum values
- new flags
- versioned option structs (`blazedb_open_ex`, etc.)

Never by changing what an existing argument means.

## Frozen C API (v0.1.0)

Opaque handles (implementation stays in Swift):

```c
typedef struct BlazeDB BlazeDB;
typedef struct BlazeDBIterator BlazeDBIterator; /* reserved; no functions in v0.1.0 */
```

```c
typedef enum {
    BLAZEDB_OK = 0,
    BLAZEDB_NOT_FOUND = 1,
    BLAZEDB_IO_ERROR = 2,
    BLAZEDB_CORRUPT = 3,
    BLAZEDB_INVALID_ARGUMENT = 4,
    BLAZEDB_AUTH_FAILED = 5,
    BLAZEDB_INTERNAL_ERROR = 6
} BlazeDBResult;

BlazeDB *blazedb_open(const char *path, const char *password);
void blazedb_close(BlazeDB *db);

BlazeDBResult blazedb_put(
    BlazeDB *db,
    const char *key,
    const void *data,
    size_t length);

BlazeDBResult blazedb_get(
    BlazeDB *db,
    const char *key,
    void **data,
    size_t *length);

BlazeDBResult blazedb_delete(BlazeDB *db, const char *key);

void blazedb_free(void *ptr);
```

### Open / password

- `password == NULL` → open returns `NULL`.
- `password == ""` → open returns `NULL`.
- Password must also satisfy the engine’s open-time strength policy (same as Swift `BlazeDB.open`).
- Do **not** overload `NULL` later to mean plaintext. Future plaintext/readonly/create flags go through `blazedb_open_ex` + `BlazeDBOpenOptions` (not in v0.1.0).

### Memory ownership

- `blazedb_get` allocates; caller must `blazedb_free` the buffer on `BLAZEDB_OK`.
- On non-OK, when `data`/`length` are non-NULL, sets `*data = NULL` and `*length = 0`.
- `blazedb_free(NULL)` is a no-op.
- Empty values (`length == 0`) are valid: `get` still returns `BLAZEDB_OK` with a non-NULL buffer that must be freed.

### Delete

- `blazedb_delete` returns `BLAZEDB_OK` if the key was absent (idempotent).

### Result meanings

| Code | Meaning |
|------|---------|
| `OK` | Success |
| `NOT_FOUND` | Key does not exist |
| `IO_ERROR` | OS / filesystem failure |
| `CORRUPT` | Database cannot be trusted |
| `INVALID_ARGUMENT` | Caller violated the API contract |
| `AUTH_FAILED` | Password incorrect / auth failure |
| `INTERNAL_ERROR` | Unexpected engine failure |

`blazedb_last_error` string detail is deferred (not in v0.1.0).

## Byte semantics

- Keys are UTF-8 strings (C: NUL-terminated `const char*`). Empty keys are invalid.
- After UTF-8 encoding, keys are opaque bytes for identity (SHA-256 → record id; original key stored for collision checks).
- Values are arbitrary binary blobs.
- `get` returns **exactly** the bytes `put` stored.
- The library **never** interprets value bytes (no JSON, Protobuf, Codable knowledge in the ABI).

## Swift surface (same milestone)

```swift
try db.put(key: "job:42", value: data)
let data = try db.get(key: "job:42") // Data?
try db.delete(key: "job:42")
```

Product: `BlazeDBC` (static library + `blazedb.h`), separate from the Android JSON demo bridge (`blazedb_bridge_*`).

Build artifact: `.build/release/libBlazeDBC.a` (includes engine objects for the C entry points).

## Explicitly out of v0.1.0

- Go / Rust / Python wrappers (planned: Go in 0.2.0)
- `blazedb_open_ex`, plaintext mode, iterators, prefix scans
- JSON / model C APIs
- Renaming or freezing `blazedb_bridge_*` as the long-term ABI
- Dynamic `.so` / `.dylib` product packaging

## Success smoke

```text
open → put → get → free → get → free → delete → get (NOT_FOUND) → close
```

Exercises allocation twice and verifies delete changes observable behavior.
