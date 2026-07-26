# BlazeDB Examples

Runnable examples from basic to advanced. Prefer the curated order below for onboarding. Support-state labels match the [documentation index](../Docs/README.md).

---

## Start Here (recommended order)

| Order | Example | What you learn | Run command |
|-------|---------|----------------|-------------|
| 1 | [HelloBlazeDB](HelloBlazeDB/) | Canonical `open → put → get → query` | `swift run HelloBlazeDB` |
| 2 | [CorePathSmoke](CorePathSmoke/) | Portable core path (`BLAZEDB_LINUX_CORE`) | `swift run CorePathSmoke` |
| 3 | [MVVMPattern](MVVMPattern/) | Repository + ViewModel without SwiftUI | `swift run MVVMPattern` |
| 4 | [BasicExample](BasicExample/) | CRUD operations | `swift run BasicExample` |
| 5 | [ReferenceConsumer](ReferenceConsumer/) | Lifecycle example | `swift run ReferenceConsumer` |
| 6 | [ReadmeSamples](ReadmeSamples/) | CI-verified README snippets | `swift run ReadmeSamples` |

---

## Embeddable C ABI

| Example | What you learn |
|---------|----------------|
| [C/hello_blazedb.c](C/hello_blazedb.c) | Stable C ABI: open → put → get → free → delete → close |
| [Go/README.md](Go/README.md) | Preview of the upcoming `blazedb-go` wrapper API |

See [C/README.md](C/README.md) for link flags after `swift build -c release --product BlazeDBC`.

---

## All examples by support state

### Core embedded examples (default shipped path)
| File | Description |
|------|-------------|
| `HelloBlazeDB/main.swift` | Minimal default API path (`BlazeDB.open`, `put`, `get`, `query`) |
| `CorePathSmoke/main.swift` | Portable core-path smoke test (Linux/Android compile mode; runs on host) |
| `BasicExample/main.swift` | Core CRUD operations |
| `QuickStart.swift` | Minimal typed working example |
| `BasicUsageExample.swift` | Common embedded usage patterns |
| `KeyPathQueriesExample.swift` | Type-safe queries with key paths |
| `QueryBuilderExample.swift` | Raw/fluent query usage |
| `MonitorDatabases.swift` | Health/stats oriented operations |
| `ReferenceConsumer/main.swift` | Production lifecycle example |

### Advanced but core-supported examples
| File | Description |
|------|-------------|
| `MigrationExamples.swift` | Schema migration workflow |
| `DynamicSchemaExample.swift` | Schemaless + evolving fields |
| `CodableExample.swift` | Codable model storage |
| `TypeSafeModels.swift` | Type-safe model patterns |
| `TypeSafeUsageExample.swift` | Type-safe API usage |
| `EventTriggersExample.swift` | Trigger-style hooks |
| `LazyDecodingExample.swift` | Lazy field loading |
| `DataSeedingExample.swift` | Test/seed data generation |
| `PrettyPrintExample.swift` | Debug formatting and inspection |

### Conditional / deferred / platform-gated examples
| File | Description |
|------|-------------|
| `SyncExample_*.swift` | Sync/distributed examples; deferred from default OSS runtime packaging |
| `TelemetryBasicExample.swift` | Telemetry API walkthrough; full telemetry behavior is build-configuration dependent |
| `VectorIndexExample.swift` | Advanced indexing with platform/build caveats |
| `SwiftUIExample.swift` | SwiftUI integration with `@BlazeQuery` / `@BlazeQueryTyped` |
| `VaporServer/main.swift` | Server integration example; optional deployment model |

See `SYNC_EXAMPLES_INDEX.md` for sync design docs and caveats.

### Experimental / under-development examples
| File | Description |
|------|-------------|
| `RLSExample.swift` | Row-level security samples; confirm availability against current release notes |
| `AshPileWithRLS.swift` | RLS app pattern sample |
| `AshPileExample.swift`, `AshPileDebugMenu.swift` | Companion app / experimental workflows |

---

## How to Run

**Executable examples** (in Package.swift):
```bash
swift run HelloBlazeDB
swift run BasicExample
swift run ReferenceConsumer
```

**Single-file examples:**
```bash
# Copy into your project or run with swift-sh
swift Examples/QuickStart.swift
```

---

## Adding Examples to Your Project

1. Copy the example file to your project
2. Add `import BlazeDB` at the top
3. Ensure your target depends on `BlazeDB`

---

## Need Help?

- [Getting Started Guide](../Docs/GettingStarted/README.md) - 5-minute setup
- [Complete Reference](../Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) - Full usage guide
- [Developer Guide](../Docs/DEVELOPER_GUIDE.md) - API reference
