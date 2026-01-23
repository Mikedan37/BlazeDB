# API Stability Policy

## Overview

This document defines which BlazeDB APIs are stable vs experimental, and our commitment to maintaining stability.

---

## Stable APIs (v0.1.0+)

These APIs are **stable** and will not change in breaking ways:

### Core CRUD Operations
```swift
func insert(_ record: BlazeDataRecord) throws -> UUID
func fetch(id: UUID) throws -> BlazeDataRecord?
func update(id: UUID, with: BlazeDataRecord) throws
func delete(id: UUID) throws
func fetchAll() throws -> [BlazeDataRecord]
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Deprecation:** Will warn before removal

### Query Builder
```swift
func query() -> QueryBuilder
func where(_ field: String, equals: BlazeDocumentField) -> QueryBuilder
func orderBy(_ field: String, descending: Bool) -> QueryBuilder
func execute() throws -> QueryResult
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Note:** Query validation and error messages may improve, but API remains stable

### Statistics API
```swift
func stats() throws -> DatabaseStats
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Note:** New fields may be added, but existing fields remain

### Health API
```swift
func health() throws -> HealthReport
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Note:** Health thresholds may be refined, but API remains stable

### Migration System
```swift
protocol BlazeDBMigration {
    var from: SchemaVersion { get }
    var to: SchemaVersion { get }
    func up(db: BlazeDBClient) throws
    func down(db: BlazeDBClient) throws
}

struct SchemaVersion: Comparable, Codable {
    let major: Int
    let minor: Int
}

func planMigration(to: SchemaVersion, migrations: [BlazeDBMigration]) throws -> MigrationPlan
func executeMigration(plan: MigrationPlan, dryRun: Bool) throws -> MigrationResult
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Note:** Migration protocol is stable; migration execution is explicit and controlled

### Import/Export APIs
```swift
func export(to: URL) throws
static func restore(from: URL, to: BlazeDBClient, allowSchemaMismatch: Bool) throws
static func verify(_ dumpURL: URL) throws -> DumpHeader
```

**Stability:**  Stable  
**Breaking Changes:** None planned  
**Note:** Dump format v1 is stable; future versions will be backward compatible

---

## Experimental APIs

These APIs are **experimental** and may change:

### Distributed Sync Modules
- `BlazeSyncEngine`
- `CrossAppSync`
- `DiscoveryProvider`
- Network transport layers

**Status:**  Experimental  
**Reason:** Not Swift 6 compliant, excluded from core  
**Breaking Changes:** May occur without notice  
**Use:** At your own risk

### Advanced Query Features
- Spatial queries
- Vector similarity search
- Window functions

**Status:**  Experimental  
**Reason:** Platform-specific (disabled on Linux)  
**Breaking Changes:** May occur  
**Use:** Check platform support first

### Telemetry APIs
- Metrics collection
- Performance monitoring

**Status:**  Experimental  
**Reason:** Actor isolation issues  
**Breaking Changes:** May occur  
**Use:** May not work reliably

---

## Versioning Strategy

### Semantic Versioning
We follow [Semantic Versioning](https://semver.org/):
- **MAJOR:** Breaking changes
- **MINOR:** New features, backward compatible
- **PATCH:** Bug fixes, backward compatible

### Current Version: 0.1.0
- **0.x:** Pre-1.0, may include breaking changes
- **Breaking changes:** Documented in CHANGELOG.md
- **Migration paths:** Provided where possible

### v1.0.0 Target
- **Stable APIs:** Locked, no breaking changes
- **Experimental APIs:** Clearly marked
- **Breaking changes:** Major version bump only

---

## Deprecation Policy

### Process
1. **Deprecation Warning:** API marked `@available(*, deprecated)`
2. **Documentation:** CHANGELOG.md notes deprecation
3. **Migration Guide:** Provided for deprecated APIs
4. **Removal:** After at least one minor version

### Example
```swift
@available(*, deprecated, message: "Use newMethod() instead. Will be removed in v0.2.0")
func oldMethod() { ... }
```

---

## Migration Guarantees

### Storage Format
- **Current:** v1.0 (stable)
- **Breaking Changes:** None planned
- **Migration:** Schema versioning system supports upgrades

### Dump Format
- **Current:** v1.0 (stable)
- **Future Versions:** Backward compatible
- **Migration:** Automatic during import

### Schema Versions
- **Versioning:** Explicit (`SchemaVersion`)
- **Migrations:** Explicit (`BlazeDBMigration`)
- **Breaking Changes:** Major version increment

---

## Breaking Change Examples

### What IS a Breaking Change
- Removing a public API
- Changing method signatures
- Changing return types
- Changing behavior (e.g., error types)

### What IS NOT a Breaking Change
- Adding new methods
- Adding optional parameters
- Improving error messages
- Performance improvements
- New fields in structs (Codable)

---

## Stability Timeline

### v0.1.0 (Current)
- Core APIs: Stable
- Migration system: Stable
- Import/export: Stable
- Health API: Stable

### v0.2.0 (Planned)
- No breaking changes planned
- May add new features
- May improve error messages

### v1.0.0 (Target)
- All stable APIs locked
- Breaking changes require major version
- Long-term support begins

---

## Recommendations

### For Production Use
-  Use stable APIs only
-  Pin to specific versions
-  Test migrations before deploying
-  Monitor health reports

### For Experimentation
-  Experimental APIs OK
-  Expect changes
-  Don't rely on stability
-  Test thoroughly

---

## Summary

**Stable:**
- Core CRUD
- Query builder
- Statistics
- Health
- Migrations
- Import/export

**Experimental:**
- Distributed sync
- Advanced queries
- Telemetry

**Policy:**
- Stable APIs: No breaking changes
- Experimental: May change
- Deprecation: Warnings before removal
- Versioning: Semantic versioning

For questions, see `SUPPORT_POLICY.md`.
