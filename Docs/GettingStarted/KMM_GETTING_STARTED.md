# BlazeDB with Kotlin Multiplatform (KMM)

Use BlazeDB from **shared Kotlin** (`commonMain`) on **Android and iOS**. This is the KMM counterpart to the SwiftUI onboarding path — same architecture (Repository + live query + UI), different UI glue (Compose / SwiftUI).

**Status:** Integration scaffolding with CI runtime proof and local Maven/XCFramework packaging. Not yet a one-line Maven Central / CocoaPods release — see [Honest product scope](#honest-product-scope).

For Swift-only apps, start at [SWIFTUI_DATABASE_PATTERNS.md](SWIFTUI_DATABASE_PATTERNS.md). For engineering status, see [android-status.md](../android-status.md).

---

## Mental model: SwiftUI vs KMM

| SwiftUI (Apple) | KMM (Android + iOS) |
|-----------------|---------------------|
| `BlazeDB.open(name:password:)` | `BlazeDB.open(path, password)` — **explicit file path** |
| `BlazeStorable` models | `Todo` + `putTodo` / `queryTodos` (sample; extend with your types) |
| `@BlazeStorableQuery` | `Flow<List<Todo>>` via `observeOpenTodos()` |
| `.blazeDBEnvironment` | Open once in ViewModel / `Application` |
| Repository + ViewModel | `TodoRepository` in `commonMain` + platform ViewModel |

Architecture reference (no UI): Swift [MVVMPattern](../../Examples/MVVMPattern/README.md) — same layers, Kotlin/Compose on Android.

---

## Quick proof (copy/paste)

From a BlazeDB repo clone on **macOS** (Android needs arm64 emulator; iOS needs Xcode):

```bash
# Both platforms — iOS simulator test + Android instrumentation test
./Scripts/prove-kmm-runtime.sh

# Packaging — AAR + native .so bundle + BlazeDBKMM.xcframework + local Maven repo
./Scripts/package-kmm-artifacts.sh
```

**CI:** PR gate runs iOS `iosSimulatorArm64Test`, Android `connectedDebugAndroidTest`, and packaging on `main`. See [CI_AND_TEST_TIERS.md](../Testing/CI_AND_TEST_TIERS.md).

---

## Project layout

```text
Examples/android/
  shared/          ← KMM library (:shared) — put this in your app
    commonMain/    ← BlazeDB, Todo, TodoRepository, Flow helpers
    androidMain/   ← JNI actual
    iosMain/       ← cinterop actual
  app/             ← Compose sample (TodoViewModel + MainActivity)
```

Core API (`commonMain`):

```kotlin
import com.blazedb.kmm.*

val db = BlazeDB.open("/path/to/app.blazedb", "YourPassword123!")
db.putTodo(Todo(title = "Ship KMM"))
val open: List<Todo> = db.queryTodos().filter { !it.isDone }

db.observeOpenTodos().collect { todos -> /* update UI */ }
db.close()
```

Lower level (JSON strings — same as bridge):

```kotlin
db.put("todo", """{"title":"example","isDone":false}""")
val json = db.query("todo")
```

---

## Android + Compose (step by step)

### 1. Build the Swift bridge (arm64)

```bash
./Scripts/ci-android-cross-compile.sh
# macOS without OSS Swift: ./Scripts/prove-android-runtime-docker-crosscompile.sh
```

Produces `.build/aarch64-unknown-linux-android28/debug/libBlazeDBAndroidBridge.so`.

### 2. Wire Gradle (sample app)

The sample under `Examples/android/` shows the full wiring:

- `:shared` — KMM module
- `:app` — copies Swift `.so` files + CMake JNI shim (`libblazedb_android_bridge.so`)
- Pass `-PBLAZEDB_SWIFT_BUILD=/absolute/path/to/BlazeDB/.build`

```bash
cd Examples/android
./gradlew :app:assembleDebug -PBLAZEDB_SWIFT_BUILD=/path/to/BlazeDB/.build
```

### 3. ViewModel + Compose (same pattern as SwiftUI)

See [TodoViewModel.kt](../../Examples/android/app/src/main/kotlin/com/blazedb/example/TodoViewModel.kt):

```kotlin
class TodoViewModel(dbFile: File) : ViewModel() {
    private val db = BlazeDB.open(dbFile.absolutePath, password)
    private val repo = TodoRepository(db)

    val openTodos: StateFlow<List<Todo>> = db.observeOpenTodos()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun addTodo(title: String) = repo.add(title)

    override fun onCleared() {
        db.close()
        super.onCleared()
    }
}
```

UI collects `StateFlow` with `collectAsState()` — parallel to SwiftUI `@BlazeStorableQuery`.

### 4. Run on emulator

```bash
./Scripts/prove-kmm-android-runtime.sh
# or
./gradlew :app:connectedDebugAndroidTest -PBLAZEDB_SWIFT_BUILD=...
```

### 5. Install the sample APK

```bash
./gradlew :app:installDebug -PBLAZEDB_SWIFT_BUILD=...
```

App shows **KMM RUNTIME OK** and open todos when live query + typed CRUD succeed.

---

## iOS (KMM framework)

### 1. Build static Swift bridge

```bash
./Scripts/build-kmm-ios-bridge.sh
```

### 2. Link KMM framework

```bash
cd Examples/android
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64 :shared:linkDebugFrameworkIosArm64
```

Output: `shared/build/bin/iosSimulatorArm64/debugFramework/BlazeDBKMM.framework`

### 3. Run simulator test

```bash
./Scripts/prove-kmm-ios-runtime.sh
```

### 4. CocoaPods (local integration)

After `./Scripts/package-kmm-artifacts.sh`, use `Examples/android/shared/BlazeDBKMM.podspec` with the generated XCFramework under `dist/kmm/ios/`. Build the static bridge first (`build-kmm-ios-bridge.sh`).

---

## Consumer packaging

`./Scripts/package-kmm-artifacts.sh` produces:

| Artifact | Path |
|----------|------|
| Android AAR | `dist/kmm/android/BlazeDBKMM-release.aar` |
| Android native libs | `dist/kmm/android/jni/arm64-v8a/*.so` |
| iOS XCFramework | `dist/kmm/ios/BlazeDBKMM.xcframework` |
| Local Maven repo | `dist/maven/com/blazedb/blazedb-kmm/0.1.0/` |

Publish to local Maven from Gradle:

```bash
cd Examples/android
./gradlew :shared:publishReleasePublicationToBlazeDBLocalRepository \
  -PBLAZEDB_SWIFT_BUILD=/path/to/BlazeDB/.build
```

**Android consumers** must ship the AAR **and** copy `jni/arm64-v8a/*.so` into `jniLibs` (see `dist/kmm/android/README.txt`).

---

## Password policy

Use the same demo password as Swift samples: **`DemoPass123!`** (12+ chars, mixed case, digit, Good strength). Production apps should use your own policy-compliant secret.

---

## Honest product scope

**Proven in CI**

- Same `commonMain` CRUD + typed `Todo` helpers on iOS simulator and Android emulator
- AAR + XCFramework packaging layout verified

**Not yet**

- Maven Central / CocoaPods trunk publish
- Generic typed models beyond the sample `Todo`
- Full parity with `@BlazeStorableQuery` (KeyPath queries, all record kinds)
- Default Android/iOS app storage paths (pass explicit `open(path, …)`)

Do **not** claim “Kotlin Multiplatform fully supported” in release notes until registry publish and consumer docs are stable — but you **can** integrate today using `Examples/android/` and the proof scripts above.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `BlazeDB.open failed` | Password policy; use `DemoPass123!` for samples |
| Missing `libBlazeDBAndroidBridge.so` | Run `./Scripts/ci-android-cross-compile.sh`; pass `-PBLAZEDB_SWIFT_BUILD` |
| Apple Swift on macOS for Android | Use OSS Swift or Docker cross-compile script |
| iOS test dylib | CI runs `embedSwiftConcurrencyIosSimulatorArm64Test` automatically |
| Live query empty on iOS | Uses polling in `iosMain`; Android uses JNI callback |

---

## Related docs

- [android-status.md](../android-status.md) — roadmap and confidence table
- [LIVE_QUERY_ARCHITECTURE.md](../Architecture/LIVE_QUERY_ARCHITECTURE.md) — observation layer design
- [Examples/android/README.md](../../Examples/android/README.md) — build commands
- [CI_AND_TEST_TIERS.md](../Testing/CI_AND_TEST_TIERS.md) — CI matrix
