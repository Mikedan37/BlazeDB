# Android and Kotlin Multiplatform — support status

This document describes **what is verified today**, not what we plan to ship eventually.
For platform matrices and API stability, see [COMPATIBILITY.md](COMPATIBILITY.md).

**Not yet officially supported:** Android app integration and KMM are engineering targets, not supported product surfaces.

---

## The core insight

**BlazeDB’s storage API is already platform-agnostic. The primary difference between SwiftUI and Android is the observation layer.**

SwiftUI adds **convenience, not capability**. Property wrappers hide `db.observe`, query refresh, lifecycle, and main-thread dispatch. Android would implement the same behavior explicitly — or through a small helper such as ``BlazeLiveQuery`` (core) and a future Kotlin `Flow` adapter.

The magic is in the **observation layer**, not the database.

For the full design of ``BlazeLiveQuery`` (lifecycle, threading, adapters, evidence hierarchy), see [Architecture/LIVE_QUERY_ARCHITECTURE.md](Architecture/LIVE_QUERY_ARCHITECTURE.md).

---

## Current status

| Item | Status |
|------|--------|
| Core compiles with `BLAZEDB_LINUX_CORE` (same path as Linux core) | Verified in CI (Linux host cross-compile) and locally via `CorePathSmoke` |
| Portable database APIs (`open`, `put`, `get`, `query`, `observe`, RLS, stats, health, export) | Verified on the core path; advanced APIs gated off |
| ``BlazeLiveQuery`` (observe → refresh → decode in core) | Verified via `BlazeLiveQueryTests` (Tier 1 PR gate), `MVVMPattern`, and SwiftUI wrappers |
| Swift-on-Android cross-compile | CI: hello-world smoke + `BlazeDBCore` + `BlazeDBAndroidBridge` (`./Scripts/ci-android-cross-compile.sh`) |
| Requires **OSS Swift** toolchain (not Xcode `swift`) | Verified — Apple Swift fails with Foundation module mismatch |
| Android CI | Present in PR gate (`ci.yml`) |
| C ABI + JNI sample | `Examples/BlazeDBAndroidBridge` + `examples/android/` (Gradle, Flow adapter) |
| Runnable example on device/emulator | Scaffold present; link Swift libs with `-PBLAZEDB_SWIFT_BUILD` |
| Kotlin bindings / JNI wrapper | Not yet |
| KMM sample or Gradle integration | Not yet |
| Default database directory on Android | Not defined — use `BlazeDB.open(at:password:)` with an app-scoped path |

---

## Swift-on-Android vs KMM

These are **not** the same thing.

- **Swift-on-Android:** BlazeDB is Swift source cross-compiled to a native Android library. Kotlin/Java call into it via JNI (for example [swift-java](https://github.com/swiftlang/swift-java)). This is the realistic near-term path.
- **KMM (Kotlin Multiplatform):** Shared Kotlin business logic calling BlazeDB directly. That requires Kotlin bindings or a stable C/FFI surface BlazeDB does not ship today.

BlazeDB **does not support KMM** today. It **may** support Swift-on-Android once cross-compile CI stays green and a minimal sample app exists.

---

## Architecture vs implementation

Forum questions often mix two layers:

1. **Architecture (portable):** One `BlazeDBClient` per app, Repository wrapping the client, ViewModel exposing query state refreshed via observation, explicit `close()` on shutdown. BlazeDB’s storage and observation model maps cleanly onto Repository + ViewModel — not Compose, DI, or other Android ecosystem pieces. SwiftUI integrations are Apple-only **ergonomics**.
2. **Implementation (not built yet):** Gradle module, `.aar`/`.so` packaging, JNI entrypoints, Kotlin-facing API, device smoke test, documentation claiming full Android support.

You can adopt the architecture pattern before BlazeDB ships Kotlin integration; you cannot depend on KMM-native BlazeDB without building the bridge yourself.

### Same architecture, different UI glue

```text
SwiftUI (Apple)                         Android (manual wiring today)

App                                     Application
 └── BlazeDBClient (once)               └── BlazeDBClient (once, explicit path)
       │                                       │
       ├── @BlazeStorableQuery                  └── Repository
       │     (wraps BlazeLiveQuery)                  │   writes + explicit reads
       ├── @Environment(\.blazeDBClient)            └── ViewModel
       └── SwiftUI View                                  │   BlazeLiveQuery / manual observe
             (reads property wrapper)                     │   StateFlow / LiveData
                                                         └── Compose UI
                                                               (collectAsState)
```

Android does **not** lose database features. It loses property wrappers, environment injection, and automatic observation wiring — those are ergonomics, not storage functionality.

### Same engine, different adapter (execution flow)

Both platforms run the same pipeline after a write:

```text
SwiftUI path                          Android path (today)

put()                                 put()
  ↓                                     ↓
PageStore / collection                PageStore / collection
  ↓                                     ↓
notifyObservers()                     notifyObservers()
  ↓                                     ↓
ObserverToken                         ObserverToken
  ↓                                     ↓
BlazeLiveQuery.refresh()              BlazeLiveQuery.refresh()   (or manual equivalent)
  ↓                                     ↓
query() + decode                      query() + decode
  ↓                                     ↓
@Published → SwiftUI redraw           StateFlow → Compose recomposes
```

``@BlazeStorableQuery`` is a SwiftUI adapter over ``BlazeLiveQuery``. A future Kotlin adapter would wrap the same core primitive as `Flow`.

---

## What the examples demonstrate

| Example | What it verifies | What it does **not** verify |
|---------|------------------|------------------------------|
| `CorePathSmoke` | CRUD, `observe`, portable core path | Android runtime, JNI, Compose |
| `MVVMPattern` | Repository + ViewModel + ``BlazeLiveQuery`` using public APIs | Android runtime, JNI, Kotlin interop |
| `examples/android/` | JNI shim + Kotlin `Flow` adapter + Compose UI scaffold | End-to-end device smoke in CI |

The Repository + ViewModel pattern is **demonstrated** in `MVVMPattern` using only BlazeDB’s public APIs. Android-specific integration (JNI, Kotlin, Compose) follows the same architecture but is **not yet implemented**.

```bash
swift run CorePathSmoke
swift run MVVMPattern
```

---

## Local verification

### Portable core path (host smoke test)

Runs the `BLAZEDB_LINUX_CORE` code path on macOS/Linux — **not** an Android binary:

```bash
swift run CorePathSmoke
```

See [Examples/CorePathSmoke/README.md](../Examples/CorePathSmoke/README.md).

### Android cross-compile (contributors)

Use **OSS Swift 6.3.2+**, the [Swift SDK for Android](https://swift.org/documentation/articles/swift-sdk-for-android-getting-started.html), and NDK r27d+. `./Scripts/ci-android-cross-compile.sh` runs hello-world smoke, then cross-compiles `BlazeDBCore` and `BlazeDBAndroidBridge` using NDK clang + libc++ headers (required for `swift-crypto`).

```bash
./Scripts/ci-android-cross-compile.sh
```

**Do not use Xcode’s `swift`** for `--swift-sdk …-android…` builds. You will see errors like “compiled module was created by an older version of the compiler” for `Foundation.swiftmodule`.

---

## Observation helpers (core vs platform)

| Layer | Role |
|-------|------|
| ``BlazeDBClient/observe(_:)`` | Change notifications (batched, main-queue delivery) |
| ``BlazeLiveQuery`` | observe → refresh → typed decode (core, platform-agnostic) |
| ``@BlazeStorableQuery`` | SwiftUI adapter over ``BlazeLiveQuery`` |
| Future Kotlin adapter | ``BlazeLiveQuery`` → `Flow` via JNI (not shipped) |

---

## What it would take to support KMM well (engineering roadmap)

| # | Work | Why |
|---|------|-----|
| 1 | Keep Android cross-compile CI green | Prevents “works on my Mac” drift |
| 2 | Define Android storage paths (or document required `open(at:)`) | `PathResolver` currently falls back to temp on unknown OS |
| 3 | Minimal Swift library target packaged for Android (`*.so` per ABI) | `BlazeDBAndroidBridge` cross-compiles in CI; Gradle sample links static Swift libs locally |
| 4 | JNI bridge ([swift-java](https://github.com/swiftlang/swift-java) or hand-rolled) | Hand-rolled C shim in `examples/android/app/src/main/cpp/` |
| 5 | Thin Kotlin API (`observeQuery<T>().asFlow()`) over ``BlazeLiveQuery`` | `BlazeLiveQueryFlow.kt` over JNI |
| 6 | Gradle/AAR publishing story | Sample Gradle project under `examples/android/` |
| 7 | JNI smoke test (`open` / `put` / `query` / `close` from Kotlin) | `BlazeDBBridge.nativeSmoke()` + `MainActivity` |
| 8 | Device/emulator smoke test | Build with `-PBLAZEDB_SWIFT_BUILD`; not yet automated in CI |
| 9 | `examples/android/` sample (Swift-on-Android first) | **Scaffold added** — verify on device |
| 10 | Compose sample (optional, after JNI) | Ergonomic Android developer experience |
| 11 | Only then update README / claim “Android supported” | Avoid soufflé documentation |

**KMM-specific addition (after 1–7):** `shared` module depending on the published Android artifact via expect/actual — still not “Kotlin calls BlazeDB natively.”

---

## Forum-ready answer

> BlazeDB’s **storage and observation model** maps cleanly onto Android’s Repository + ViewModel architecture — not the full Android ecosystem (Compose navigation, DI, WorkManager, etc.). SwiftUI’s `@BlazeStorableQuery` is a convenience adapter over ``BlazeLiveQuery`` in core (observe → refresh → decode). On Android you’d wire the same layers explicitly, or through a future Kotlin `Flow` adapter over JNI. We don’t have a Kotlin SDK or KMM integration yet.
>
> **Demonstrated today:** portable core APIs (`CorePathSmoke`), Repository + ViewModel pattern (`MVVMPattern`), ``BlazeLiveQuery`` unit tests, Linux core CI, Android cross-compile CI. **Not yet shipped:** JNI smoke test, Kotlin facade, device sample.

---

## Related docs

- [COMPATIBILITY.md](COMPATIBILITY.md) — platform matrix and OSS vs Xcode Swift
- [CONTRIBUTING.md](../CONTRIBUTING.md) — Android cross-compile notes for contributors
- [SYSTEM_MAP.md](SYSTEM_MAP.md) — feature inventory and CI ownership
