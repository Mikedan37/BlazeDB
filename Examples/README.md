# BlazeDB Examples

Runnable examples from basic to advanced.

---

## Start Here (Recommended Order)

| Order | Example | What You'll Learn | Run Command |
|-------|---------|-------------------|-------------|
| 1 | HelloBlazeDB | Open, insert, query, close | `swift run HelloBlazeDB` |
| 2 | BasicExample | CRUD operations | `swift run BasicExample` |
| 3 | QueryBuilderExample | Queries and filters | See file |
| 4 | MigrationExamples | Schema migrations | See file |

---

## All Examples by Category

### Getting Started
| File | Description |
|------|-------------|
| `HelloBlazeDB/main.swift` | Complete walkthrough (best first example) |
| `BasicExample/main.swift` | Basic CRUD operations |
| `QuickStart.swift` | Minimal working example |
| `BasicUsageExample.swift` | Common patterns |

### Queries
| File | Description |
|------|-------------|
| `QueryBuilderExample.swift` | Fluent query builder |
| `KeyPathQueriesExample.swift` | Type-safe queries with key paths |
| `JoinExample.swift` | Joining data from multiple queries |

### Data Modeling
| File | Description |
|------|-------------|
| `CodableExample.swift` | Using Codable types |
| `TypeSafeModels.swift` | Defining type-safe models |
| `TypeSafeUsageExample.swift` | Using type-safe models |
| `DynamicSchemaExample.swift` | Schema-less flexible storage |

### Advanced Features
| File | Description |
|------|-------------|
| `MigrationExamples.swift` | Schema migrations |
| `EventTriggersExample.swift` | Database triggers |
| `LazyDecodingExample.swift` | Lazy field loading |
| `VectorIndexExample.swift` | Vector similarity search |
| `DataSeedingExample.swift` | Generating test data |

### Monitoring and Debugging
| File | Description |
|------|-------------|
| `MonitorDatabases.swift` | Health monitoring |
| `PrettyPrintExample.swift` | Debug output |
| `TelemetryBasicExample.swift` | Performance metrics |
| `ProgressMonitorExample.swift` | Long operation progress |

### Sync (Experimental)
| File | Description |
|------|-------------|
| `SyncExample_SameApp.swift` | In-memory sync (same process) |
| `SyncExample_CrossApp.swift` | Unix socket sync (cross-process) |
| `SyncExample_RemoteServer.swift` | TCP server |
| `SyncExample_RemoteClient.swift` | TCP client |

See `SYNC_EXAMPLES_INDEX.md` for complete sync documentation.

### Integration
| File | Description |
|------|-------------|
| `SwiftUIExample.swift` | SwiftUI integration |
| `VaporServer/main.swift` | Vapor web server |
| `ReferenceConsumer/main.swift` | Production lifecycle example |

### Security
| File | Description |
|------|-------------|
| `RLSExample.swift` | Row-level security (under development; not available in this release) |
| `AshPileWithRLS.swift` | RLS with real app patterns (under development; not available in this release) |

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
