# BlazeDB Android sample (Swift-on-Android + Kotlin)

Minimal **Repository + ViewModel + Compose** sample wired to Swift `BlazeDBCore` through a C ABI and JNI shim.

**KMM:** `:shared` is a Kotlin Multiplatform module (`commonMain` + `androidMain`). The Android `actual` uses JNI; iOS/other targets can be added later without changing the app shell.

**Present in this tree (compile-time wiring — not runtime-verified in CI)**

| Layer | Location | Confidence |
|-------|----------|------------|
| KMM `expect` repository | `shared/src/commonMain/` | 🟡 android actual only |
| Swift C ABI (`blazedb_bridge_*`) | `Examples/BlazeDBAndroidBridge/` | 🟢 cross-compiles in CI |
| JNI shim | `app/src/main/cpp/blazedb_jni_shim.c` | 🟢 links locally |
| Kotlin bridge + Flow | `shared/src/androidMain/.../bridge/` | 🟡 runtime pending |
| Compose app shell | `app/` | 🟡 runtime pending |

CI proves cross-compilation; it does **not** exercise `nativeSmoke()` on a device. See [Docs/android-status.md](../../Docs/android-status.md) for the full confidence ladder.

## Architecture

```text
Compose UI (:app)  →  TodoViewModel
                          ↓
                    BlazeDBRepository (:shared commonMain expect / androidMain actual)
                          ↓ BlazeLiveQueryFlow (Kotlin Flow)
                       BlazeDBBridge (JNI, shared/androidMain)
                          ↓ blazedb_jni_shim.c (:app CMake → .so)
                       BlazeDBAndroidBridge (Swift C exports)
                          ↓ BlazeLiveQuery + BlazeDBClient
                       BlazeDBCore
```

Same shape as `Examples/MVVMPattern` and `@BlazeStorableQuery` on Apple platforms.

## Build steps

### 1. Cross-compile Swift for Android (OSS Swift 6.3.2+)

From the repo root on Linux or macOS with OSS Swift:

```bash
./Scripts/ci-android-cross-compile.sh
```

This runs hello-world toolchain smoke, then builds `BlazeDBCore` and `BlazeDBAndroidBridge` for `aarch64-unknown-linux-android28`.

### 2. Build the Android app

```bash
cd Examples/android
./scripts/build-swift-lib.sh          # cross-compile Swift from repo root

# Requires JDK 17+, Android SDK, Gradle wrapper (Android Studio import or `gradle wrapper`)
./gradlew :app:assembleDebug -PBLAZEDB_SWIFT_BUILD=/absolute/path/to/BlazeDB/.build
./gradlew :app:installDebug -PBLAZEDB_SWIFT_BUILD=...

# Or from repo root (adb + emulator required):
./Scripts/run-android-runtime-smoke.sh
```

## KMM status

This sample is **Swift-on-Android + Kotlin**, not KMM-native BlazeDB. A KMM `shared` module is intentionally **deferred** until device/emulator runtime and CI smoke pass — only then wrap this JNI bridge via `expect`/`actual`.

See [Docs/android-status.md](../../Docs/android-status.md).
