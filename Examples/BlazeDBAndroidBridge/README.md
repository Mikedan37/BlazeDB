# BlazeDBAndroidBridge

C ABI exports for Android JNI integration.

| C function | Purpose |
|------------|---------|
| `blazedb_bridge_smoke` | open → put → get → query → observe → close |
| `blazedb_bridge_live_query_start` | `BlazeLiveQuery` with JSON callback |
| `blazedb_bridge_live_query_stop` | Stop live query handle |

Header: `include/blazedb_android_bridge.h`

Consumer: `examples/android/app/src/main/cpp/blazedb_jni_shim.c`

Cross-compile:

```bash
./Scripts/ci-android-cross-compile.sh
```

Builds this target for `aarch64-unknown-linux-android28` after toolchain smoke.
