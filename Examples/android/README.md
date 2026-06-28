# BlazeDB Android sample (Swift-on-Android + Kotlin)

Minimal **Repository + ViewModel + Compose** sample wired to Swift `BlazeDBCore` through a C ABI and JNI shim.

**Demonstrated in this tree**

| Layer | Location |
|-------|----------|
| Swift C ABI (`blazedb_bridge_*`) | `Examples/BlazeDBAndroidBridge/` |
| JNI shim | `app/src/main/cpp/blazedb_jni_shim.c` |
| Kotlin bridge | `bridge/BlazeDBBridge.kt` |
| `Flow` adapter over `BlazeLiveQuery` | `bridge/BlazeLiveQueryFlow.kt` |
| Repository + ViewModel | `data/`, `ui/` |

**Not yet verified on device in CI** — requires linking Swift static libraries into the `.so` (see below).

## Architecture

```text
Compose UI  →  TodoViewModel (StateFlow)
                  ↓ BlazeLiveQueryFlow (Kotlin Flow)
               BlazeDBBridge (JNI)
                  ↓ blazedb_jni_shim.c
               BlazeDBAndroidBridge (Swift, C exports)
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
cd examples/android
chmod +x scripts/build-swift-lib.sh   # optional helper
./scripts/build-swift-lib.sh          # runs step 1 + prints Gradle hint

./gradlew :app:assembleDebug \
  -PBLAZEDB_SWIFT_BUILD=/absolute/path/to/BlazeDB/.build
```

Install on arm64 device/emulator (API 28+):

```bash
./gradlew :app:installDebug
```

## KMM status

This sample is **Swift-on-Android + Kotlin**, not KMM-native BlazeDB. A future KMM `shared` module could wrap the same JNI bridge via `expect`/`actual` on Android.

See [Docs/android-status.md](../../Docs/android-status.md).
