# Android and Kotlin Multiplatform — support status

This document describes **what is verified today**, not what we plan to ship eventually.
For platform matrices and API stability, see [COMPATIBILITY.md](COMPATIBILITY.md).

**Not yet officially supported:** Android app integration and KMM are engineering targets, not supported product surfaces.

Having source in the tree (C ABI, JNI shim, Kotlin `Flow` adapter, Gradle sample) is **not** the same as Android support. Those layers **compile**; they have **not** been exercised end-to-end on a device in an automated way.

---

## Confidence levels

What has been **proven** versus **assumed**:

| Confidence | Status |
|------------|--------|
| 🟢 **Compiler** | `BlazeDBCore` + `BlazeDBAndroidBridge` cross-compile for Android in PR gate CI (`./Scripts/ci-android-cross-compile.sh`) |
| 🟢 **Linker** | JNI bridge target and sample Gradle/CMake wiring **build** (Swift static libs linked into `libblazedb_android_bridge.so` locally) |
| 🟡 **Runtime** | Verified locally on arm64 emulator via `prove-android-runtime.sh` — not yet in CI |
| 🔴 **Production** | No automated emulator/device CI yet |
| ⚪ **Ecosystem** | KMM `:shared` — **iOS runtime test in CI**; Android runtime via local emulator script |

**Important distinction:** CI proves cross-compilation and that the bridge **compiles**. It does **not** prove the JNI → Swift → database path works at runtime on Android.

---

## Proof order (do not skip layers)

Prove each layer before adding the next. Wrapping an unverified stack in KMM only adds abstraction — and bugs distribute across every layer you invent.

| # | Layer | Confidence | Notes |
|---|-------|------------|-------|
| 1 | Swift library (`BlazeDBCore`) | 🟢 | OSS Swift 6.3.2 + NDK r27d; NDK clang/libc++ header path fixes in CI |
| 2 | C ABI (`BlazeDBAndroidBridge`) | 🟢 | `blazedb_bridge_*` exports cross-compile in CI |
| 3 | JNI (C shim → Kotlin `external`) | 🟢 compile / 🟡 runtime | `blazedb_jni_shim.c` + `BlazeDBBridge.kt` — builds, not yet smoke-tested on device |
| 4 | Kotlin API (`Flow` adapter, Repository) | 🟡 | `Examples/android/shared` — smoke + live query + add/mark done; local emulator verified |
| 5 | Emulator / device | 🟡 | `./Scripts/prove-android-runtime.sh` — manual; not automated in CI |
| 6 | CI (Gradle + emulator smoke) | 🔴 | PR gate cross-compiles bridge only |
| 7 | KMM `shared` module | 🟡 | `expect class BlazeDB`; Android JNI; **iOS cinterop + framework link**; device/simulator runtime proof pending |

The toolchain work (OSS Swift against Android NDK, libc++ include paths, cross-compilation reliability) is the substantive systems engineering here. KMM is a later ergonomics layer, not the proof.

---

## The core insight

**BlazeDB’s storage API is already platform-agnostic. The primary difference between SwiftUI and Android is the observation layer.**

SwiftUI adds **convenience, not capability**. Property wrappers hide `db.observe`, query refresh, lifecycle, and main-thread dispatch. Android would implement the same behavior explicitly — or through a small helper such as ``BlazeLiveQuery`` (core) and a future Kotlin `Flow` adapter.

The magic is in the **observation layer**, not the database.

For the full design of ``BlazeLiveQuery`` (lifecycle, threading, adapters, evidence hierarchy), see [Architecture/LIVE_QUERY_ARCHITECTURE.md](Architecture/LIVE_QUERY_ARCHITECTURE.md).

---

## Current status (detail)

| Item | Confidence | Notes |
|------|------------|-------|
| Core with `BLAZEDB_LINUX_CORE` (same path as Linux) | 🟢 | Host CI + `CorePathSmoke` |
| Portable database APIs (`open`, `put`, `get`, `query`, `observe`, …) | 🟢 | Core path; advanced APIs gated off |
| ``BlazeLiveQuery`` | 🟢 | Tier 1 tests, `MVVMPattern`, SwiftUI wrappers |
| Swift-on-Android cross-compile | 🟢 | hello-world + `BlazeDBCore` + `BlazeDBAndroidBridge` in PR gate |
| Requires **OSS Swift** (not Xcode `swift`) | 🟢 | Apple Swift fails with Foundation module mismatch |
| C ABI + JNI + Kotlin sample **source** | 🟢 compile | `Examples/BlazeDBAndroidBridge`, `Examples/android/` |
| JNI smoke on device/emulator | 🟡 | `nativeSmoke` + live query + add/mark done verified locally; not in CI |
| Gradle APK in CI | 🔴 | Not wired |
| KMM | 🟡 | `:shared` scaffold — **do not claim full KMM support** until iOS links and runs |
| Default Android database directory | — | Not defined; use `BlazeDB.open(at:password:)` with app-scoped path |

---

## Swift-on-Android vs KMM

These are **not** the same thing.

- **Swift-on-Android:** BlazeDB Swift source cross-compiled to native Android libraries. Kotlin/Java call in via JNI. This is the realistic near-term path — and the path the sample follows.
- **KMM (Kotlin Multiplatform):** Shared Kotlin business logic calling BlazeDB directly. Requires a stable, **runtime-verified** bridge on Android first. BlazeDB does **not** support KMM today.

Do **not** rush KMM. “Supports KMM” is a buzzword; wrapping an unproven runtime path makes debugging miserable because you cannot tell which layer is lying.

---

## Architecture vs implementation

Forum questions often mix two layers:

1. **Architecture (portable, proven on host):** One `BlazeDBClient` per app, Repository, ViewModel, observation-driven query refresh, explicit `close()`. Demonstrated in `MVVMPattern` and ``BlazeLiveQuery`` tests.
2. **Implementation (Android runtime, partially built):** Cross-compile ✅, bridge source ✅, device smoke ⏳, CI smoke ❌, KMM ❌.

You can adopt the architecture pattern before BlazeDB ships verified Android integration; you cannot depend on KMM-native BlazeDB without building and proving the bridge yourself.

### Same architecture, different UI glue

```text
SwiftUI (Apple)                         Android (target wiring)

App                                     Application
 └── BlazeDBClient (once)               └── BlazeDBClient (once, explicit path)
       │                                       │
       ├── @BlazeStorableQuery                  └── Repository
       │     (wraps BlazeLiveQuery)                  │   writes + explicit reads
       ├── @Environment(\.blazeDBClient)            └── ViewModel
       └── SwiftUI View                                  │   BlazeLiveQuery / Flow
             (reads property wrapper)                     │   StateFlow
                                                         └── Compose UI
```

### Same engine, different adapter (execution flow)

```text
put() → PageStore → notifyObservers() → ObserverToken
  → BlazeLiveQuery.refresh() → query() + decode
  → SwiftUI @Published  |  Android StateFlow (via JNI, when runtime-verified)
```

---

## What the examples demonstrate

| Example | Proves | Does **not** prove |
|---------|--------|---------------------|
| `CorePathSmoke` | CRUD, `observe`, portable core on **host** | Android runtime, JNI |
| `MVVMPattern` | Repository + ViewModel + ``BlazeLiveQuery`` on **host** | Android runtime, JNI |
| `Examples/android/` | Bridge **compiles**; wiring shape for JNI → Flow → Compose | End-to-end runtime on device; CI smoke |

```bash
swift run CorePathSmoke
swift run MVVMPattern
```

---

## Local verification

### Portable core path (host)

Runs `BLAZEDB_LINUX_CORE` on macOS/Linux — **not** an Android binary:

```bash
swift run CorePathSmoke
```

### Android cross-compile (contributors)

OSS Swift 6.3.2+, [Swift SDK for Android](https://swift.org/documentation/articles/swift-sdk-for-android-getting-started.html), NDK r27d+:

```bash
./Scripts/ci-android-cross-compile.sh
```

**Do not use Xcode’s `swift`** for `--swift-sdk …-android…` builds.

### Android runtime (next milestone)

After cross-compile succeeds, build and install the sample (manual, not in CI yet):

```bash
cd Examples/android
./scripts/build-swift-lib.sh
./gradlew :app:assembleDebug -PBLAZEDB_SWIFT_BUILD=/absolute/path/to/BlazeDB/.build
./gradlew :app:installDebug
```

Confirm `nativeSmoke()` returns a positive row count on arm64 emulator/device (API 28+).

---

## Observation helpers (core vs platform)

| Layer | Role | Confidence |
|-------|------|------------|
| ``BlazeDBClient/observe(_:)`` | Change notifications | 🟢 core |
| ``BlazeLiveQuery`` | observe → refresh → decode | 🟢 core |
| ``@BlazeStorableQuery`` | SwiftUI adapter | 🟢 Apple |
| Kotlin `Flow` adapter | ``BlazeLiveQuery`` over JNI | 🟡 source only |

---

## Engineering roadmap (remaining work)

| # | Work | Why |
|---|------|-----|
| 1 | Keep cross-compile CI green | Prevents toolchain drift |
| 2 | Document Android storage paths (`open(at:)`) | `PathResolver` falls back to temp on unknown OS |
| 3 | Local device/emulator smoke (`nativeSmoke`) | First 🟡 → 🟢 runtime proof |
| 4 | Gradle + emulator smoke in CI | 🔴 → production confidence |
| 5 | AAR / `.so` packaging story | Repeatable consumer integration |
| 6 | Only then: KMM `shared` wrapper | ⚪ — same JNI bridge, not a rewrite |

---

## Forum-ready answer

> BlazeDB’s storage and observation model **maps cleanly** onto Android Repository + ViewModel — that’s architecture, not shipped Android support.
>
> **Proven in CI:** `BlazeDBCore` cross-compiles for Android; the JNI bridge **compiles**.
> **Not yet proven:** end-to-end runtime on device/emulator in CI; KMM.
>
> SwiftUI’s `@BlazeStorableQuery` is a convenience adapter over ``BlazeLiveQuery`` in core. On Android the same primitive would sit behind JNI and Kotlin `Flow` — sample code exists, runtime verification is the next milestone.

---

## Related docs

- [COMPATIBILITY.md](COMPATIBILITY.md) — platform matrix and OSS vs Xcode Swift
- [CONTRIBUTING.md](../CONTRIBUTING.md) — Android cross-compile notes for contributors
- [Examples/android/README.md](../Examples/android/README.md) — sample build steps
- [SYSTEM_MAP.md](SYSTEM_MAP.md) — feature inventory and CI ownership
