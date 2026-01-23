# Extension Points

**Where to extend BlazeDB without touching frozen core.**

This document explicitly lists where persistence extensions, schema logic, and tooling hooks belong.

---

## Persistence Extensions

**Where:** `BlazeDB/Exports/BlazeDBClient+*.swift`

**What belongs here:**
- New CRUD operations
- Query builder extensions
- Migration logic
- Import/export functionality
- Health and statistics APIs

**Files:**
- `BlazeDBClient+Export.swift` - Export functionality
- `BlazeDBClient+Migration.swift` - Migration APIs
- `BlazeDBClient+Health.swift` - Health reporting
- `BlazeDBClient+Stats.swift` - Statistics
- `BlazeDBClient+EasyOpen.swift` - Convenience open methods
- `BlazeDBClient+Guardrails.swift` - Guardrails and validation

**DO:**
- Use public APIs only (`collection.fetchMeta()`, `collection.insert()`, etc.)
- Add new convenience methods
- Add validation and guardrails

**DON'T:**
- Access `PageStore` directly
- Modify `DynamicCollection` internals
- Change storage layout
- Add concurrency primitives

---

## Schema Logic

**Where:** `BlazeDB/Core/SchemaVersion.swift`, `BlazeDB/Core/BlazeDBMigration.swift`

**What belongs here:**
- Schema version definitions
- Migration protocol implementations
- Migration planning and execution

**Files:**
- `SchemaVersion.swift` - Version type
- `BlazeDBMigration.swift` - Migration protocol
- `MigrationPlan.swift` - Migration planning
- `MigrationExecutor.swift` - Migration execution

**DO:**
- Implement `BlazeDBMigration` protocol
- Use `getSchemaVersion()` and `setSchemaVersion()`
- Plan migrations with `MigrationPlanner`

**DON'T:**
- Modify storage layout directly
- Add implicit migrations
- Change metadata format

---

## Tooling Hooks

**Where:** `BlazeDB/Exports/` and CLI tools

**What belongs here:**
- CLI tools (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`)
- Diagnostic APIs
- Health monitoring
- Import/export tools

**Files:**
- `BlazeDoctor/main.swift` - Health diagnostics CLI
- `BlazeDump/main.swift` - Dump/restore CLI
- `BlazeInfo/main.swift` - Database info CLI
- `BlazeDBClient+Health.swift` - Health API
- `BlazeDBClient+Stats.swift` - Stats API

**DO:**
- Use public APIs only
- Add new CLI commands
- Add diagnostic features

**DON'T:**
- Access storage internals
- Modify core behavior
- Add background threads

---

## Query Extensions

**Where:** `BlazeDB/Query/QueryBuilder+*.swift`

**What belongs here:**
- New query operators
- Query validation
- Query optimization hints

**Files:**
- `QueryBuilder+Validation.swift` - Input validation
- `QueryBuilder+Vector.swift` - Vector queries
- `IndexHints.swift` - Index hints

**DO:**
- Add new query methods
- Validate input
- Provide optimization hints

**DON'T:**
- Change query execution semantics
- Modify `DynamicCollection` internals
- Add parallel execution

---

## Error Handling

**Where:** `BlazeDB/Exports/BlazeDBError+*.swift`

**What belongs here:**
- Error categorization
- User-friendly error messages
- Remediation guidance

**Files:**
- `BlazeDBError+Categories.swift` - Error categories and guidance

**DO:**
- Add new error cases
- Improve error messages
- Add remediation hints

**DON'T:**
- Change error throwing behavior in core
- Modify core error types

---

## What MUST NOT Be Touched

**Frozen Core (DO NOT MODIFY):**

- `BlazeDB/Storage/PageStore.swift` - Page storage engine
- `BlazeDB/Storage/PageCache.swift` - Page cache
- `BlazeDB/Storage/WriteAheadLog.swift` - WAL implementation
- `BlazeDB/Storage/StorageLayout.swift` - Storage layout (read-only access)
- `BlazeDB/Core/DynamicCollection.swift` - Core collection logic (use public APIs only)
- `BlazeDB/Utils/BlazeBinaryEncoder.swift` - Encoding (use public APIs)
- `BlazeDB/Utils/BlazeBinaryDecoder.swift` - Decoding (use public APIs)

**Why:** These are frozen for Phase 1. Changes require explicit approval and concurrency review.

---

## Extension Examples

### Adding a New Convenience Method

```swift
// File: BlazeDB/Exports/BlazeDBClient+MyExtension.swift
extension BlazeDBClient {
    public func myNewMethod() throws {
        // Use public APIs only
        let records = try fetchAll()
        // ... do something with records
    }
}
```

### Adding a New Query Operator

```swift
// File: BlazeDB/Query/QueryBuilder+MyOperator.swift
extension QueryBuilder {
    public func myNewOperator(_ field: String) -> QueryBuilder {
        filters.append { record in
            // Filter logic
        }
        return self
    }
}
```

### Adding a New CLI Tool

```swift
// File: MyTool/main.swift
import BlazeDB

let db = try BlazeDB.openDefault(name: "mydb", password: "password")
let stats = try db.stats()
print(stats.prettyPrint())
```

---

## Summary

**Extend via:**
- `BlazeDB/Exports/` - New APIs and convenience methods
- `BlazeDB/Query/QueryBuilder+*.swift` - Query extensions
- CLI tools - New command-line tools
- `BlazeDB/Core/` (schema/migration) - Schema evolution

**Never touch:**
- `BlazeDB/Storage/` - Storage engine (frozen)
- `BlazeDB/Core/DynamicCollection.swift` internals - Use public APIs only

**Rule:** If you need to modify `PageStore` or `DynamicCollection` internals, that's a different phase. Use public APIs instead.
