# Tour 05 — BlazeDBC

~15 minutes. Goal: see the C ABI as a thin byte-KV façade over the Swift engine.

## Start here

1. `BlazeDBC/include/blazedb.h`
2. `BlazeDBC/BlazeDBC.swift`
3. `Docs/Architecture/C_ABI_BYTE_KV.md`
4. `Examples/C/hello_blazedb.c`
5. `Examples/Go/README.md` (recipe; `.go` sources not in tree yet)
6. `BlazeDBTests/Tier1Core/API/BlazeDBCSmokeTests.swift`

## Follow this symbol

`blazedb_open` → `@_cdecl` → `BlazeDBCBox` / `OpaquePointer` → engine open/put/get/delete → `BlazeDBResult` → `blazedb_free` / `blazedb_close`.

## Invariants

- Header declarations must match exported symbols.
- Caller frees buffers from `blazedb_get` via `blazedb_free`.
- Do not change struct layouts or symbol names without compatibility process.
- C ABI is byte KV — not the full typed Swift document API.

## Associated tests

- `BlazeDBTests/Tier1Core/API/BlazeDBCSmokeTests.swift` (`testOpenPutGetFreeDeleteClose`, `testOpenRejectsNullAndEmptyPassword`)
- Related: `BlazeDBTests/Tier1Core/API/ByteKVAPITests.swift`

## Try it

```bash
swift test --filter BlazeDBCSmokeTests
swift build -c release --product BlazeDBC
# See Examples/C/README.md for linking hello_blazedb.c
```

## Open work

#264 (Go smoke + CI), #265 (artifacts + C example in CI), #267 (`blazedb_last_error`).

## Extension ideas

1. `blazedb_last_error` — **already tracked** (#267).
2. Checked-in Go smoke — **already tracked** (#264).
3. Iterator-based C ABI — **requires maintainer design** (do not file until ownership model is written).
