# Stable C ABI + Byte KV Design

**Status:** Approved for implementation (2026-07-24)  
**Audience:** Engine maintainers and language-binding authors

## Goal

Make BlazeDB embeddable from any language that can call C, without exposing Swift types, JSON, or `BlazeStorable`. The first non-Swift consumer is expected to be a Go manager behind a `Storage` interface.

## Layering

```text
Typed Models (BlazeStorable)     ← convenience (Swift)
         │
    Byte KV API (Data)           ← language-neutral core
         │
   Storage Engine
         │
       C ABI (blazedb.h)         ← forever contract
```

There is one storage implementation. Typed APIs serialize to bytes (or, in v1, share the same page engine via a reserved KV namespace). The C ABI only speaks bytes.

## Compatibility rule (day one)

Once a C function is published, its **signature and behavior never change**.

New capabilities only via:

- new functions
- new enum values
- new flags
- versioned option structs (`blazedb_open_ex`, etc.)

Never by changing what an existing argument means.

## Frozen C API (v1)

Opaque handles (implementation stays in Swift):

```c
typedef struct BlazeDB BlazeDB;
typedef struct BlazeDBIterator BlazeDBIterator; /* reserved; no functions in v1 */
```

```c
typedef enum {
    BLAZEDB_OK = 0,
    BLAZEDB_NOT_FOUND,
    BLAZEDB_IO_ERROR,
    BLAZEDB_CORRUPT,
    BLAZEDB_INVALID_ARGUMENT,
    BLAZEDB_AUTH_FAILED,
    BLAZEDB_INTERNAL_ERROR
} BlazeDBResult;

BlazeDB* blazedb_open(const char* path, const char* password);
void blazedb_close(BlazeDB* db);

BlazeDBResult blazedb_put(
    BlazeDB* db,
    const char* key,
    const void* data,
    size_t length);

BlazeDBResult blazedb_get(
    BlazeDB* db,
    const char* key,
    void** data,
    size_t* length);

BlazeDBResult blazedb_delete(BlazeDB* db, const char* key);

void blazedb_free(void* ptr);
```

### Open / password

- `password == NULL` → open fails (`NULL` return); caller violated contract (`INVALID_ARGUMENT` semantics).
- `password == ""` → same.
- Do **not** overload `NULL` later to mean plaintext. Future plaintext/readonly/create flags go through `blazedb_open_ex` + `BlazeDBOpenOptions` (not in v1).

### Memory ownership

- `blazedb_get` allocates; caller must `blazedb_free` the buffer on `BLAZEDB_OK`.
- On non-OK, `*data` is set to `NULL` and `*length` to `0` when the out-params are non-NULL.
- `blazedb_free(NULL)` is a no-op.

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

`blazedb_last_error` string detail is deferred to v1.1.

## Byte semantics

- Keys are UTF-8 strings (C: NUL-terminated `const char*`).
- After UTF-8 encoding, keys are opaque bytes for hashing/identity.
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

## Explicitly out of v1

- Go / Rust / Python wrappers (build after ABI is real)
- `blazedb_open_ex`, plaintext mode, iterators
- JSON / model C APIs
- Renaming or freezing `blazedb_bridge_*` as the long-term ABI

## Success smoke

```text
open → put → get → free → get → free → delete → get (NOT_FOUND) → close
```

Exercises allocation twice and verifies delete changes observable behavior.
