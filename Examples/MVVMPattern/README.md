# MVVM pattern (no SwiftUI)

Plain Swift proof that BlazeDB’s **core APIs** map onto Repository + ViewModel without SwiftUI property wrappers.

Uses ``BlazeLiveQuery`` (core) for observe → refresh → decode — the same primitive ``@BlazeStorableQuery`` composes on Apple platforms.

**Demonstrated:** CRUD, observation, Repository + ViewModel lifecycle, ``BlazeLiveQuery``.

**Not demonstrated:** Android runtime, JNI, Kotlin, Compose.

Design rationale and adapter roadmap: [Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md](../../Docs/Architecture/LIVE_QUERY_ARCHITECTURE.md).

```bash
swift run MVVMPattern
```

On Kotlin/Android, the same layers exist; only the observation glue and UI binding differ. See [Docs/android-status.md](../../Docs/android-status.md).
