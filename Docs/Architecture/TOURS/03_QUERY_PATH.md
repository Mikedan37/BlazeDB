# Tour 03 — Query path

~15 minutes. Goal: understand that the public query path scans, then filters in memory.

## Start here

1. `BlazeDB/Exports/BlazeDBClient.swift` — `query()`
2. `BlazeDB/Query/QueryBuilder.swift` — `execute`, `_executeStandard`
3. `BlazeDB/Query/QueryExplain.swift`
4. `BlazeDB/Core/DynamicCollection.swift` — `fetchAll`, `runQuery*`
5. `BlazeDB/Core/DynamicCollection+Optimized.swift` — fetchAll cache
6. `BlazeDB/Query/QueryCache.swift`

## Follow this symbol

`db.query().where(…).execute()` → `QueryBuilder.execute` → `_executeStandard` → `collection.fetchAll()` → apply `filters` / sort / limit → `QueryResult`.

Index creation may update secondary structures; **default `_executeStandard` does not probe them**.

## Invariants

- Do not document O(log n) public execution until indexes are wired (#261/#274/#292).
- Cache hits must not return stale snapshots after mutations (#280).
- Nested `queue.sync` from `runQuery*` into `fetchAll` can deadlock (#279).

## Associated tests

- `BlazeDBTests/Tier0Core/CoreCorrectness/QueryPlannerStrategyContractTests.swift`
- `BlazeDBTests/Tier1Core/Query/` (QueryBuilder / live query)
- `BlazeDBTests/Tier1Core/Core/DXQueryExplainTests.swift`

## Try it

```bash
./dev test QueryPlannerStrategyContractTests
./dev tests Query
```

## Open work

#261, #274, #279, #280, #292.

## Extension ideas

1. Soften planner docs — **already tracked** (#292).
2. Wire range indexes into `_executeStandard` — **already tracked** (#274); design-heavy.
3. Iterator-style query API — **requires maintainer design**.
