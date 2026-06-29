# Android and Kotlin Multiplatform — support status

This document describes **what is verified today**, not what we plan to ship eventually.
For platform matrices and API stability, see [COMPATIBILITY.md](COMPATIBILITY.md).

**Not yet officially supported:** Android app integration and KMM are engineering targets, not supported product surfaces.

The `:shared` KMM module (`expect class BlazeDB`) is **runtime-verified locally on Android emulator and iOS simulator**, and **partially gated in PR CI** (iOS simulator test + Android Kotlin compile). That is integration scaffolding — not a shipped KMM SDK or “Kotlin Multiplatform supported” product claim.

---

## Confidence levels

What has been **proven** versus **assumed**:

| Confidence | Status |
|------------|--------|
| 🟢 **Compiler** | `BlazeDBCore` + `BlazeDBAndroidBridge` cross-compile for Android in PR gate CI (`./Scripts/ci-android-cross-compile.sh`) |
| 🟢 **Linker** | JNI bridge target and sample Gradle/CMake wiring **build** (Swift static libs linked into `libblazedb_android_bridge.so` locally) |
| 🟢 **Runtime (iOS)** | `BlazeDB.open` / `put` / `query` on iOS simulator — PR CI (`iosSimulatorArm64Test`) + `./Scripts/prove-kmm-ios-runtime.sh` |
| 🟢 **Runtime (Android)** | Same API verified on arm64 emulator — PR CI (`connectedDebugAndroidTest`) + `./Scripts/prove-kmm-android-runtime.sh` |
| 🟡 **Production** | Consumer packaging in CI (`package-kmm-artifacts.sh`); not Maven/CocoaPods publish yet |
| 🟡 **Ecosystem** | KMM `:shared` — runtime + packaging verified in CI; README “KMM supported” still pending publish story |

---

## Proof order (do not skip layers)

Prove each layer before adding the next. Wrapping an unverified stack in KMM only adds abstraction — and bugs distribute across every layer you invent.

| # | Layer | Confidence | Notes |
|---|-------|------------|-------|
| 1 | Swift library (`BlazeDBCore`) | 🟢 | OSS Swift 6.3.2 + NDK r27d; NDK clang/libc++ header path fixes in CI |
| 2 | C ABI (`BlazeDBAndroidBridge`) | 🟢 | `blazedb_bridge_*` exports cross-compile in CI |
| 3 | JNI (C shim → Kotlin `external`) | 🟢 compile / 🟡 runtime | Android `actual` — compile in CI; runtime verified locally |
| 4 | KMM `commonMain` API | 🟡 | `expect class BlazeDB` — `open` / `put` / `get` / `query` / `close` |
| 5 | iOS simulator runtime | 🟢 | `BlazeDBRuntimeSmokeTest` in PR CI |
| 6 | Android emulator runtime | 🟢 | `ci-kmm-android-emulator-smoke.sh` in macOS PR job + local prove script |
| 7 | CI (Gradle + emulator smoke) | 🟢 | iOS runtime + Android instrumentation in PR gate; Linux cross-compile + Kotlin compile |
| 8 | Packaging (AAR / XCFramework) | 🟡 | `package-kmm-artifacts.sh` in macOS PR job; not published to registries yet |

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
| JNI + KMM sample | 🟢 compile / 🟡 runtime | `Examples/android/` — Android runtime local; iOS runtime in CI |
| KMM integration | 🟡 | Same `commonMain` API on both platforms — **not** “KMM supported” product wording yet |
| Default Android database directory | — | Not defined; use `BlazeDB.open(at:password:)` with app-scoped path |

---

## Swift-on-Android vs KMM

These are **not** the same thing.

- **Swift-on-Android:** BlazeDB Swift source cross-compiled to native Android libraries. Kotlin/Java call in via JNI. This is the realistic near-term path — and the path the sample follows.
- **KMM (Kotlin Multiplatform):** Shared Kotlin (`Examples/android/shared`) calling BlazeDB through platform `actual` implementations — Android via JNI, iOS via cinterop → same Swift C ABI. **Runtime verified** on iOS simulator (CI) and Android emulator (local). BlazeDB does **not** claim full “Kotlin Multiplatform supported” until Android runtime is in CI and consumer packaging exists.

Do **not** rush KMM. “Supports KMM” is a buzzword; wrapping an unproven runtime path makes debugging miserable because you cannot tell which layer is lying.

---

## Architecture vs implementation

Forum questions often mix two layers:

1. **Architecture (portable, proven on host):** One `BlazeDBClient` per app, Repository, ViewModel, observation-driven query refresh, explicit `close()`. Demonstrated in `MVVMPattern` and ``BlazeLiveQuery`` tests.
2. **Implementation (KMM integration):** Cross-compile ✅, bridge ✅, iOS/Android runtime in CI ✅, packaging ✅, typed sample + Flow ✅, registry publish ❌.

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
| `Examples/android/` | KMM `BlazeDB` API + sample app wiring | Consumer packaging; Android CI runtime |

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

### KMM runtime (local + CI)

**iOS (also in PR CI on macOS):**

```bash
./Scripts/prove-kmm-ios-runtime.sh
# or: cd Examples/android && ./gradlew :shared:iosSimulatorArm64Test
```

**Android (local emulator; Docker cross-compile on macOS if `.so` missing):**

```bash
./Scripts/prove-kmm-android-runtime.sh
# or both: ./Scripts/prove-kmm-runtime.sh
```

**Android cross-compile only (same as Linux CI):**

```bash
./Scripts/ci-android-cross-compile.sh
```

**Do not use Xcode’s `swift`** for `--swift-sdk …-android…` builds.

### Android sample app (manual)

```bash
cd Examples/android
./scripts/build-swift-lib.sh   # or Docker cross-compile on macOS
./gradlew :app:assembleDebug -PBLAZEDB_SWIFT_BUILD=/absolute/path/to/BlazeDB/.build
./gradlew :app:installDebug
```

Confirm UI shows `KMM RUNTIME OK` and `kmm-commonMain` in the query JSON.

---

## Observation helpers (core vs platform)

| Layer | Role | Confidence |
|-------|------|------------|
| ``BlazeDBClient/observe(_:)`` | Change notifications | 🟢 core |
| ``BlazeLiveQuery`` | observe → refresh → decode | 🟢 core |
| ``@BlazeStorableQuery`` | SwiftUI adapter | 🟢 Apple |
| Kotlin KMM `BlazeDB` | `commonMain` API over JNI / cinterop | 🟡 iOS CI + local Android |

---

## Engineering roadmap (remaining work)

| # | Work | Why |
|---|------|-----|
| 1 | Keep cross-compile + KMM CI green | Prevents toolchain drift |
| 2 | Android KMM runtime in CI (emulator job) | Match iOS PR gate confidence |
| 3 | AAR / XCFramework packaging | Repeatable consumer integration |
| 4 | Document Android storage paths (`open(at:)`) | `PathResolver` falls back to temp on unknown OS |
| 5 | Live query / observation on Android KMM | Optional; core CRUD path proven |

---

## Forum-ready answer

> BlazeDB’s storage and observation model **maps cleanly** onto Android Repository + ViewModel — that’s architecture, not shipped Android support.
>
> **Proven in CI:** cross-compile; KMM iOS + Android runtime; AAR/XCFramework packaging; typed `Todo` + live Flow sample.
> **Not yet:** Maven Central / CocoaPods trunk; full SwiftUI-parity API surface.
>
> SwiftUI’s `@BlazeStorableQuery` is a convenience adapter over ``BlazeLiveQuery`` in core. On Android the same primitive would sit behind JNI and Kotlin `Flow` — sample code exists, runtime verification is the next milestone.

---

## Related docs

- [COMPATIBILITY.md](COMPATIBILITY.md) — platform matrix and OSS vs Xcode Swift
- [CONTRIBUTING.md](../CONTRIBUTING.md) — Android cross-compile notes for contributors
- [Examples/android/README.md](../Examples/android/README.md) — sample build steps
- [SYSTEM_MAP.md](SYSTEM_MAP.md) — feature inventory and CI ownership
