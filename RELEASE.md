# BlazeDB v2.8.0 — Embeddable C ABI

**Tag:** `v2.8.0`  
**Date:** 2026-07-24  
**Foundation commits:** `ac689c1d` (ABI), `b55e742c` (docs)

BlazeDB can now be embedded from multiple native languages through a stable C ABI. This release introduces **BlazeDBC**, a byte-oriented API designed for long-term compatibility and language bindings such as Go, Rust, and Python.

## Summary

One version stream. One engine. A frozen contract (`blazedb.h`) so wrappers never need to know Swift exists.

## Highlights

- **Stable C ABI** — `blazedb_open` / `put` / `get` / `delete` / `close` / `free`
- **Swift byte KV** — `put(key:value:)` / `get(key:)` / `delete(key:)` on `BlazeDBClient`
- **`BlazeDBC` product** — static `libBlazeDBC.a` via SwiftPM
- **Opaque handles** — `BlazeDB*`; reserved `BlazeDBIterator` (unimplemented)
- **`BlazeDBResult`** — typed error codes
- **Design doc** — [Docs/Architecture/C_ABI_BYTE_KV.md](Docs/Architecture/C_ABI_BYTE_KV.md)
- **Smoke tests** — ownership sequence: put → get → free → get → free → delete → NOT_FOUND
- **Docs** — README, C/Go examples, ABI guarantees

## Breaking changes

None. Existing Swift APIs are unchanged.

## Known limitations

- **Password required** — `NULL` / empty password rejected; no plaintext mode yet
- **Static library only** — no shipped `.so` / `.dylib` product in 2.8.0
- **No official Go/Rust/Python packages yet** — call C directly or wait for 2.9.0
- **No iterators / prefix scan** — reserved type only
- **No `blazedb_last_error`** — result codes only
- **Linking needs Swift runtime** — C/Go hosts must link the toolchain that built `libBlazeDBC.a`
- **Sidecar files** — encryption may create `.salt` / `.meta` / WAL next to the DB path

## Future roadmap

| Version | Focus |
|---------|--------|
| **2.9.0** | Official Go wrapper (`blazedb-go`) |
| **2.10.0** | Iterators, prefix scans, additional C APIs |
| **later** | `blazedb_open_ex` (readonly, create, optional plaintext) |
| **3.0.0** | Intentional breaking API or on-disk format change |

## Install / try

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
git checkout v2.8.0
swift build -c release --product BlazeDBC
# Header: BlazeDBC/include/blazedb.h
# Library: .build/release/libBlazeDBC.a
```

SwiftPM:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.0")
```

C sample: [Examples/C](Examples/C) · README: [README.md](README.md)
