# BlazeDB v2.8.2

**Tag:** `v2.8.2`  
**Date:** 2026-08-31

Patch release since 2.8.1. Lots of contributor commits landed: cache isolation, RLS holes closed, safer CLI passwords, docs that match the real KDF story, and CI that is less flaky on GitHub runners.

C ABI is unchanged. Same `blazedb.h`, same packaging story as 2.8.1 (dynamic `BlazeDBC` + optional static product).

## Highlights

- Async query cache invalidates on writes (no more stale `queryAsync` after update)
- Doctor probe cleanup is durable before exit
- LazyField / JOIN / query cache isolation across DB instances
- RANK() ties fixed
- RLS gaps closed on graph/update/stats paths
- CLI prefers `BLAZEDB_PASSWORD` over argv
- Sensitive file perms + less secret logging
- Docs tell the truth about PBKDF2

## Validation on this tag tip

- PR Gate green on `d104cf5f` (macOS, Linux Tier0, Apple/Android/KMM)
- Nightly Confidence green on the same commit (Tier1 Linux, Tier2, Tier0 TSan, README, clean checkout)

Deep Validation weekly was still red on an older SHA before the CI de-flake. Default release workflow does not require that lane.

## Install

SwiftPM:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.2")
```

Checkout + build:

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
git checkout v2.8.2
swift build -c release
```

## Thanks

@Nitjsefnie, @VedantMadane, @yu010101, @jlonsdalen, and @finagolfin (Android #21). Roster: [Docs/Release/CONTRIBUTORS.md](Docs/Release/CONTRIBUTORS.md).

## Full changelog

See [CHANGELOG.md](CHANGELOG.md) for the detailed list, and compare:

https://github.com/Mikedan37/BlazeDB/compare/v2.8.1...v2.8.2
