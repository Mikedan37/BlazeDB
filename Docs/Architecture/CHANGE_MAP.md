# CHANGE_MAP

Mechanical blast-radius map. No vision. Update when entry points or contracts move.

---

## Query path

### Public entry points
- `BlazeDBClient.query()` → `QueryBuilder`
- `QueryBuilder.execute()` / `all()` / `first()` / `exists()`
- `TypeSafeQueryBuilder.all()` (builds a `QueryBuilder`, then `all()`)
- `BlazeLiveQuery` refresh (Apple) → `db.query()…execute()`
- `BlazeQueryContext.execute()` (collection-level convenience)
- C ABI (`BlazeDBC`): byte KV only — **no query API today**
- KMM / Android bridge: packaging surface; does not own a separate query planner

### Core flow (standard path today)
1. load visible records (`collection.fetchAll()` + soft-delete filter)
2. predicate evaluation (in-memory filter closures)
3. index selection — **not used** by default standard path
4. sort
5. offset
6. limit
7. wrap as `QueryResult.records` (typed decode happens at typed/SwiftUI edges)

Join / aggregation / planner / optimizer / vector paths still branch inside `QueryBuilder.execute()` and do **not** yet go through the standard seam.

### Primary implementation files
- `BlazeDB/Exports/BlazeDBClient.swift` — `query()`
- `BlazeDB/Query/QueryBuilder.swift` — builder + `execute()` dispatch
- `BlazeDB/Query/QueryExecuting.swift` — `QueryRequest` / `QueryExecuting` / `LegacyQueryExecutor`
- `BlazeDB/Core/DynamicCollection.swift` — `fetchAll` / scan source
- `BlazeDB/Query/QueryBuilderKeyPath.swift` — typed adapter
- `BlazeDB/Core/BlazeLiveQuery.swift` — live refresh
- `BlazeDB/Query/QueryResult.swift` — result envelope
- `BlazeDB/Core/BlazeRecord+Extensions.swift` — `all()` / `first()` shortcuts

### Internal seam (standard path only)
```
Public query APIs
  → QueryBuilder.execute()  (type detect)
  → _executeStandard()
  → QueryBuilder.standardQueryExecutor  (QueryExecuting)
  → LegacyQueryExecutor
  → fetchAll → filter → sort → offset → limit
```

Default executor: `LegacyQueryExecutor`. Do not change public signatures when swapping implementations behind `QueryExecuting`.

### Behavioral tests
- `BlazeDBTests/Tier0Core/CoreCorrectness/QueryExecutionSeamTests.swift`
- `BlazeDBTests/Tier0Core/CoreCorrectness/QueryNotEqualsMissingFieldTests.swift`
- `BlazeDBTests/Tier0Core/CoreCorrectness/QueryPlannerStrategyContractTests.swift`
- `BlazeDBTests/Tier0Core/CoreCorrectness/NestedQueueSyncQueryTests.swift`
- `BlazeDBTests/Tier1Core/Query/` (`BlazeQueryTests`, ergonomics, result conversion, DX)

### Platform coverage
- macOS local: `./dev test QueryExecutionSeamTests` / Tier0 + Tier1 Query
- Linux Tier0 / Tier1 CI
- Apple SwiftUI live query: `BlazeDB_SwiftUITests` (not Linux)
- Android/KMM: compile/packaging only for query semantics today

### Contracts that must not change
- Public Swift signatures on `BlazeDBClient.query` / `QueryBuilder` / `QueryResult`
- Missing-field predicate semantics (see `#327` / `QueryNotEqualsMissingFieldTests`)
- Soft-deleted records excluded from standard results (`isDeleted`)
- Transaction visibility as exposed by `fetchAll` at execute time
- C ABI byte-KV behavior (orthogonal; do not invent query ABI here)
- Default path remains scan-based until indexes are intentionally wired

### Out of scope for this map section
- Redesigning planner/optimizer
- Storage format
- Join/aggregation internal seams (add when those paths get a boundary)
