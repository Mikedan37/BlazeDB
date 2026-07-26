# Stable C ABI + Byte KV Design

**Status:** Implemented (v2.8.0), commit `ac689c1d`  
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

Once a C function is published in `blazedb.h` for a given major line, its **caller-visible signature and documented behavior do not change** within that line. New capabilities appear only via:

- new functions
- new enum values
- new flags
- versioned option structs (for example `blazedb_open_ex`)

Never by changing what an existing argument means.

### What this stability promise covers

| Covered | Meaning |
|---------|---------|
| Exported symbol names | Published `blazedb_*` names remain available |
| Function signatures | Parameter types, counts, and return types for published functions stay the same |
| Documented behavior | Semantics described for those functions stay the same (same success/error meaning for the same inputs) |
| Opaque handles | `BlazeDB *` stays opaque; callers must not depend on layout |

| Not covered / not promised by this document | Meaning |
|---------------------------------------------|---------|
| Opaque struct memory layout | Callers must not inspect or serialize internal fields |
| Binary drop-in across OS/ABI/toolchain | Rebuild and relink against the matching `libBlazeDBC` for your platform |
| Swift typed APIs | `BlazeStorable` / `BlazeDB` Swift surface evolves under normal SwiftPM versioning |
| Android `blazedb_bridge_*` demo exports | Separate from the long-term `blazedb.h` surface (see out-of-scope below) |
| Major-version breaks | A future 3.x may intentionally change the C surface; that requires a new major and a migration note |

If a change would break an existing published signature or its documented meaning, it does not ship as a silent patch: it waits for a new symbol, a new option struct, or an intentional major version.

## Published C API (v2.8.0)

Opaque handles (implementation stays in Swift):

```c
typedef struct BlazeDB BlazeDB;
typedef struct BlazeDBIterator BlazeDBIterator; /* reserved; no functions in v2.8.0 */
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
- Do **not** overload `NULL` later to mean plaintext. Future plaintext/readonly/create flags go through `blazedb_open_ex` + `BlazeDBOpenOptions` (not in v2.8.0).

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

`blazedb_last_error` string detail is deferred (not in v2.8.0).

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

Product: `BlazeDBC` (dynamic shared library + `blazedb.h`; optional `BlazeDBCStatic`), separate from the Android JSON demo bridge (`blazedb_bridge_*`).

Build artifacts:

- Preferred: `.build/release/libBlazeDBC.dylib` / `libBlazeDBC.so`
- Optional: `.build/release/libBlazeDBC.a` via `--product BlazeDBCStatic`

## Explicitly out of v2.8.x

- Dynamic `.so` / `.dylib` product packaging ✅ (v2.8.1)
- Go / Rust / Python wrappers (planned: Go in 2.9.0)
- `blazedb_open_ex`, plaintext mode, iterators, prefix scans
- JSON / model C APIs
- Renaming or freezing `blazedb_bridge_*` as the long-term ABI

## Success smoke

```text
open → put → get → free → get → free → delete → get (NOT_FOUND) → close
```

Exercises allocation twice and verifies delete changes observable behavior.
