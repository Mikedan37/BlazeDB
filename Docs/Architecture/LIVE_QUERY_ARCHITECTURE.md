# Live query architecture

Design document for ``BlazeLiveQuery`` — the core observation primitive behind typed live queries in BlazeDB.

This is **not** a tutorial. For runnable examples, see [Examples/MVVMPattern](../../Examples/MVVMPattern/README.md) and [Examples/CorePathSmoke](../../Examples/CorePathSmoke/README.md). For Android/KMM status, see [android-status.md](../android-status.md).

---

## Why `BlazeLiveQuery` exists

BlazeDB already had everything needed for reactive UIs at the storage layer:

1. **Typed queries** — `query().where().orderBy().execute()` with `BlazeStorable` decode
2. **Change notifications** — `db.observe(_:)` with batched delivery via ``ObserverToken``

What was missing was a **single, reusable composition** of those two primitives. That logic originally lived inside SwiftUI property wrappers (`@BlazeStorableQuery`, `BlazeQueryObserver`). Any non-SwiftUI consumer — CLI tools, server processes, headless ViewModels, tests, future UI frameworks — had to reimplement the same pipeline:

```
observe(change) → re-run query → decode rows → deliver to caller
```

``BlazeLiveQuery`` extracts that pipeline into core so it is written once and composed everywhere.

**The magic is in the observation layer, not the database.** Storage APIs are already platform-agnostic. Live queries add the glue between writes and read models.

---

## Layer diagram

### Before (SwiftUI owned the behavior)

```text
SwiftUI (@BlazeStorableQuery)
    └── BlazeStorableQueryObserver
            └── db.observe → manual refresh → decode → @Published
```

### After (core owns the behavior)

```text
SwiftUI (@BlazeStorableQuery)     MVVMPattern / CLI / future adapters
         ↓                                    ↓
              BlazeLiveQuery  (core)
                    ↓
         db.observe → refresh() → runQuery() → onResults
                    ↓
              ObserverToken
                    ↓
         ChangeNotificationManager
```

SwiftUI adds **convenience, not capability**: property wrappers, environment injection, and `@Published` wiring. The behavioral contract lives in core.

---

## Relationship to `ObserverToken`

| Layer | Responsibility |
|-------|----------------|
| ``BlazeDBClient/observe(_:)`` | Register a callback for database changes; returns an ``ObserverToken`` |
| ``ObserverToken`` | RAII handle — invalidates on `deinit` or explicit `invalidate()` |
| ``ChangeNotificationManager`` | Batches changes (~50ms), delivers observer callbacks on the main queue |
| ``BlazeLiveQuery`` | **Owns** one ``ObserverToken``; maps any change notification to `refresh()` |

``BlazeLiveQuery`` does not replace ``ObserverToken``. It **composes** it:

- `start()` registers exactly one observer (calling `stop()` first if re-starting)
- `stop()` invalidates the token
- `deinit` calls `stop()`

Lower-level observation tests (`ChangeObservationTests`) verify token semantics and change types. ``BlazeLiveQueryTests`` verify the **typed refresh pipeline** built on top — without duplicating CRUD or raw observe coverage.

---

## Why it lives in core

``BlazeLiveQuery`` is in `BlazeDB/Core/BlazeLiveQuery.swift` and ships with `BlazeDBCore` (the `BLAZEDB_LINUX_CORE` path used by Linux and Android cross-compiles).

It belongs in core because:

1. **No UI dependency** — Foundation only; no SwiftUI, Combine, or platform UI frameworks
2. **Same compile path as portable storage** — CLI, server, and cross-platform targets can import it today
3. **Single source of truth** — SwiftUI wrappers compose it; Android/JNI adapters would compose the same type, not a fork
4. **Testable in Tier 1 PR gate** — `BlazeLiveQueryTests` runs with `BlazeDB_Tier1`, independent of SwiftUI

Platform-specific code should be thin adapters that translate `onResults` into the local reactive primitive (`@Published`, `StateFlow`, `AsyncStream`, print callbacks, etc.).

---

## Lifecycle

```text
                    ┌─────────────┐
                    │   created   │
                    └──────┬──────┘
                           │ onResults = { ... }
                           ▼
                    ┌─────────────┐
         start() ──►│   active    │◄── db.observe registered
                    │             │    initial refresh() runs
                    └──────┬──────┘
                           │
              write/delete │ observer fires
                           ▼
                    ┌─────────────┐
                    │  refreshing │──► runQuery() ──► onResults
                    └──────┬──────┘
                           │
              stop() /     │
              deinit       ▼
                    ┌─────────────┐
                    │   stopped   │── observer unregistered
                    └─────────────┘
                           │
              refresh()    │ (manual only — no observer callbacks)
                           ▼
                    onResults still invoked
```

**Idempotence:**

- `start()` is idempotent — replaces the existing observer; observer count stays at 1
- `stop()` is idempotent — safe to call multiple times
- After `stop()`, observer-driven refresh does not occur; manual `refresh()` still runs the query

**Retain cycles:** The `@Sendable` observe closure captures a ``RefreshBridge`` with a **weak** reference to the live query, not the query itself. The handler is copied under lock and invoked without retaining `BlazeLiveQuery` through the callback path.

---

## Threading model

Two delivery stages, both main-queue oriented:

| Stage | Behavior |
|-------|----------|
| ``ChangeNotificationManager`` | Batches writes for ~50ms; flushes observer callbacks on `DispatchQueue.main` |
| ``BlazeLiveQuery/deliver(_:)`` | Copies `onResults` under `NSLock`; invokes on main thread (sync if already on main, else `DispatchQueue.main.async`) |

**Implications for non-UI consumers:**

- CLI and XCTest code must **pump `RunLoop.main`** (or run on the main actor) to receive observer-driven callbacks within a bounded time. See `CorePathSmoke` and `BlazeLiveQueryTests` for the ~150ms pump pattern.
- Query execution (`runQuery()`) runs on whatever thread calls `refresh()` — typically the main queue callback chain after a write notification.
- Future adapters (JNI/Flow) may need a configurable dispatch target; today delivery matches UI-safe defaults.

---

## Query execution (what `refresh()` does)

``BlazeLiveQuery`` does not maintain an incremental index or diff. On each refresh it:

1. Builds a namespace-filtered query for `T: BlazeStorable`
2. Applies stored filter tuples (equals, ranges, contains, etc.)
3. Applies sort and limit
4. Executes the query and decodes rows (`try? T.fromBlazeRecord` — malformed rows are skipped)

This is intentional: correctness comes from re-querying authoritative storage, not from caching a materialized view. Consistency with a manual query is the correctness property tested in ``BlazeLiveQueryTests``.

---

## Platform adapters (present and future)

| Adapter | Status | Role |
|---------|--------|------|
| **SwiftUI** — `@BlazeStorableQuery` | Shipped | Composes ``BlazeLiveQuery``; exposes `[T]` via `@Published` and environment |
| **Headless ViewModel** — `MVVMPattern` | Demonstrated | Repository + ViewModel; ``BlazeLiveQuery`` in ViewModel, no SwiftUI |
| **CLI / smoke tests** — `CorePathSmoke` | Verified | Raw `db.observe` (lower level); live-query pattern available via ``BlazeLiveQuery`` |
| **AppKit / UIKit** | Not shipped | Would compose ``BlazeLiveQuery`` like SwiftUI — `@Published` or delegate callbacks |
| **AsyncStream** | Not shipped | Thin wrapper: `onResults` → `yield`; structured concurrency lifecycle |
| **JNI → Kotlin Flow** | Not shipped | Swift ``BlazeLiveQuery`` behind JNI; Kotlin collects as `Flow<List<T>>` |
| **Compose** | Not shipped | Collects Flow/StateFlow — UI binding only; no BlazeDB logic in Compose layer |

Adapters should not reimplement observe → refresh → decode. They translate delivery semantics only.

---

---

## Public API contract

``BlazeLiveQuery`` is a supported core abstraction. External adapters should depend on these guarantees.

| Topic | Guarantee |
|-------|-----------|
| **Lifecycle** | ``start()`` registers one observer + initial ``refresh()``; ``stop()`` / ``deinit`` unregister; ``start()`` is idempotent (replaces token) |
| **Threading** | ``onResults`` always on main queue; ``runQuery()`` on caller of ``refresh()`` |
| **Callback ordering** | Initial delivery from ``start()`` first; then batched write notifications (~50ms) in commit order |
| **Coalescing** | Change notifications coalesce within ~50ms → one ``refresh()`` per flush; **no** coalescing of overlapping ``refresh()`` calls |
| **``stop()``** | No observer-driven refresh after stop; in-flight refresh may still deliver; manual ``refresh()`` still works |

See doc comments on ``BlazeLiveQuery`` in `BlazeDB/Core/BlazeLiveQuery.swift` for full detail.

---

## Android, KMM, and MVVM

**Precise claim:**

> BlazeDB's storage and observation model maps cleanly onto Android's Repository + ViewModel architecture.

**Do not claim:**

> BlazeDB supports Android MVVM.

The first statement describes **demonstrated fit** (storage API, observation API, lifecycle). It does not imply Compose navigation, DI frameworks, SavedStateHandle, WorkManager, or other Android ecosystem pieces.

The second implies a shipped integration layer (Gradle, JNI, device sample) that does not exist today.

Once JNI and a Kotlin facade exist, the intended wiring is:

```text
Compose UI
    ↓ collectAsState()
ViewModel (StateFlow)
    ↓ BlazeLiveQuery.onResults  (via JNI)
Repository
    ↓ BlazeDBClient.put / query
BlazeDB core
```

That is the same shape as ``MVVMPattern``, with different UI binding. See [android-status.md](../android-status.md) for the engineering roadmap and what is verified vs future work.

KMM integration (`expect class BlazeDB` in `Examples/android/shared`) is **in progress**: iOS simulator runtime is in PR CI; Android emulator runtime is verified locally via `./Scripts/prove-kmm-android-runtime.sh`. BlazeDB does **not** claim full “Kotlin Multiplatform supported” until Android runtime is in CI and packaging exists.

---

## Evidence hierarchy

Each tier proves something distinct. Higher tiers do not substitute for lower ones.

| Tier | What it proves |
|------|----------------|
| Unit tests (`BlazeLiveQueryTests`) | ``BlazeLiveQuery`` behaves correctly |
| `CorePathSmoke` | Portable core APIs work |
| `MVVMPattern` | Storage + observation map cleanly to Repository + ViewModel |
| Linux CI | Core has no Apple-framework dependencies |
| Android cross-compile CI | `BlazeDBCore` compiles to an Android binary |
| JNI smoke test *(future)* | Kotlin can call BlazeDB through JNI (`open` / `put` / `query` / `close`) |
| Compose sample *(future)* | Android developers can use BlazeDB ergonomically |

Cross-compilation is a **build** milestone, not an **integration** milestone. Until the JNI smoke test exists, keep wording at “maps cleanly” — not “supports Android.”

```text
BlazeLiveQueryTests → CorePathSmoke → MVVMPattern → Linux CI
    → Android cross-compile → JNI smoke → Compose sample
```

Until `examples/android/` exists, forum answers should point to **MVVMPattern** and this document for architecture, not to a clone-and-run Android project.

---

## Related source and docs

| Resource | Purpose |
|----------|---------|
| `BlazeDB/Core/BlazeLiveQuery.swift` | Implementation |
| `BlazeDB/Core/ChangeObservation.swift` | ``ObserverToken``, batching, main-queue delivery |
| `BlazeDB/SwiftUI/BlazeStorableLiveQuery.swift` | SwiftUI adapter |
| `BlazeDBTests/Tier1Core/Query/BlazeLiveQueryTests.swift` | Focused unit tests |
| [android-status.md](../android-status.md) | Platform status and roadmap |
| [Examples/MVVMPattern](../../Examples/MVVMPattern/README.md) | Headless MVVM demonstration |

---

## Design principles

1. **Core owns observation.** The observe → refresh → decode pipeline lives in ``BlazeLiveQuery``, not in UI frameworks.
2. **UI frameworks own presentation.** SwiftUI, Compose, AppKit, and UIKit bind results to views; they do not reimplement change subscription or query refresh.
3. **Observation is platform-agnostic.** ``BlazeLiveQuery`` ships with `BlazeDBCore` and has no UI dependencies.
4. **Integrations compose ``BlazeLiveQuery`.** SwiftUI property wrappers, ViewModels, AsyncStream, JNI/Flow adapters, and CLI callbacks should wrap the core primitive — not fork it.
5. **Platform adapters add ergonomics, not database capabilities.** Convenience wrappers do not change what BlazeDB can store, query, or observe.

These invariants apply to all future adapters (Combine, OpenCombine, AppKit, UIKit, JNI, Kotlin Flow, etc.). If a proposed change puts observation logic into an adapter instead of core, refer back here.
