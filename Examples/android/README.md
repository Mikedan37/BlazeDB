# BlazeDB KMM sample (`Examples/android/shared`)

Minimal **Kotlin Multiplatform** module with the same `commonMain` API on Android and iOS.

## Status (conservative)

| Check | Status |
|-------|--------|
| `commonMain` `expect class BlazeDB` | Done |
| Android `actual` → JNI → Swift | Done |
| iOS `actual` → cinterop → Swift static lib | Done |
| iOS `BlazeDBKMM.framework` links | Done (macOS + Xcode) |
| iOS simulator `put` + `query` runtime | Done (`iosSimulatorArm64Test`) |
| Android emulator `put` + `query` runtime | Local + PR CI (`connectedDebugAndroidTest`) |
| AAR + XCFramework packaging | `./Scripts/package-kmm-artifacts.sh` (CI + local) |
| README “Kotlin Multiplatform supported” | **Not yet** — no Maven/CocoaPods publish |

```kotlin
val db = BlazeDB.open(path, password)
db.put("todo", """{"title":"example"}""")
val rows = db.query("todo")
db.close()
```

## Build

### Android (`:shared` + sample app)

```bash
./Scripts/ci-android-cross-compile.sh
cd Examples/android
./gradlew :shared:compileDebugKotlinAndroid :app:assembleDebug \
  -PBLAZEDB_SWIFT_BUILD=/path/to/BlazeDB/.build
```

### iOS (KMM framework)

```bash
./Scripts/build-kmm-ios-bridge.sh
cd Examples/android
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64 :shared:linkDebugFrameworkIosArm64
```

Output: `Examples/android/shared/build/bin/iosSimulatorArm64/debugFramework/BlazeDBKMM.framework`

CI (macOS PR gate) runs bridge build + iOS link; Linux Android job compiles `:shared:compileDebugKotlinAndroid`.

See [Docs/android-status.md](../../Docs/android-status.md).
