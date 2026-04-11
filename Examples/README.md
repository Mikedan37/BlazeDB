# BlazeDB Examples

Runnable examples from basic to advanced.

---

## Start Here (Recommended Order)

| Order | Example | What You'll Learn | Run Command |
|-------|---------|-------------------|-------------|
| 1 | HelloBlazeDB | Canonical `open → put → get → query` flow | `swift run HelloBlazeDB` |
| 2 | BasicExample | CRUD operations | `swift run BasicExample` |
| 3 | QueryBuilderExample | Fluent query filters | See file |
| 4 | ReferenceConsumer | Lifecycle example | `swift run ReferenceConsumer` |

---

## All Examples by Support State

### Core Embedded Examples (Default Shipped Path)
| File | Description |
|------|-------------|
| `HelloBlazeDB/main.swift` | Minimal default API path (`BlazeDB.open`, `put`, `get`, `query`) |
| `BasicExample/main.swift` | Core CRUD operations |
| `QuickStart.swift` | Minimal typed working example |
| `BasicUsageExample.swift` | Common embedded usage patterns |
| `KeyPathQueriesExample.swift` | Type-safe queries with key paths |
| `QueryBuilderExample.swift` | Raw/fluent query usage |
| `MonitorDatabases.swift` | Health/stats oriented operations |
| `ReferenceConsumer/main.swift` | Production lifecycle example |

### Advanced but Core-Supported Examples
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

### Conditional / Deferred / Platform-Gated Examples
| File | Description |
|------|-------------|
| `SyncExample_*.swift` | Sync/distributed examples; deferred from default OSS runtime packaging |
| `TelemetryBasicExample.swift` | Telemetry API walkthrough; full telemetry behavior is build-configuration dependent |
| `VectorIndexExample.swift` | Advanced indexing with platform/build caveats |
| `SwiftUIExample.swift` | SwiftUI integration with `@BlazeQuery` / `@BlazeQueryTyped` and DB-change-driven query refresh |
| `VaporServer/main.swift` | Server integration example; optional deployment model |

See `SYNC_EXAMPLES_INDEX.md` for full sync design docs and caveats.

### Experimental / Under-Development Examples
| File | Description |
|------|-------------|
| `RLSExample.swift` | Row-level security (under development; not available in this release) |
| `AshPileWithRLS.swift` | RLS app pattern sample (under development; not available in this release) |
| `AshPileExample.swift`, `AshPileDebugMenu.swift` | Companion app/experimental workflows |

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
