# BlazeDB v0.1.0 — Embeddable C ABI

**Tag:** `v0.1.0`  
**Date:** 2026-07-24  
**Foundation commit:** `ac689c1d`

This is the first **embeddable** release: a frozen byte-oriented C ABI so non-Swift languages can link BlazeDB without knowing Swift. The Swift package continues on the 2.7.x line for app consumers; **0.x** is the C ABI stability track.

## Summary

BlazeDB can now be embedded like a small systems library: open a path, put/get/delete opaque bytes, close. The contract is [`BlazeDBC/include/blazedb.h`](BlazeDBC/include/blazedb.h). Swift still owns the engine; every other language speaks C.

## Highlights

- **Stable C ABI** — `blazedb_open` / `put` / `get` / `delete` / `close` / `free`
- **Swift byte KV** — `put(key:value:)` / `get(key:)` / `delete(key:)` on `BlazeDBClient`
- **`BlazeDBC` product** — static `libBlazeDBC.a` via SwiftPM
- **Opaque handles** — `BlazeDB*`; reserved `BlazeDBIterator` (unimplemented)
- **`BlazeDBResult`** — typed error codes, no magic integers
- **Design doc** — [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md)
- **Smoke tests** — ownership sequence: put → get → free → get → free → delete → NOT_FOUND

## Breaking changes

None for prior C consumers — this is the first published ABI.

Swift app APIs are unchanged. Prefer existing `BlazeDB` / `BlazeDBClient` docs for typed models.

## Known limitations

- **Password required** — `NULL` / empty password rejected; no plaintext mode yet
- **Static library only** — no shipped `.so` / `.dylib` product in 0.1.0
- **No Go/Rust/Python packages yet** — call C directly or wait for 0.2.0
- **No iterators / prefix scan** — reserved type only
- **No `blazedb_last_error`** — result codes only
- **Linking needs Swift runtime** — C/Go hosts must link the toolchain that built `libBlazeDBC.a`
- **Sidecar files** — encryption may create `.salt` / `.meta` / WAL next to the DB path

## Future roadmap

| Version | Focus |
|---------|--------|
| **0.2.0** | Official Go wrapper (`blazedb-go`) implementing a tiny Storage-friendly API |
| **0.3.0** | Iterators, prefix scans |
| **later** | `blazedb_open_ex` (flags: readonly, create, optional plaintext) |
| **1.0.0** | Long-term ABI stability commitment |

## Install / try

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift build -c release --product BlazeDBC
# Header: BlazeDBC/include/blazedb.h
# Library: .build/release/libBlazeDBC.a
```

C sample: [Examples/C](Examples/C) · README: [README.md](README.md)
