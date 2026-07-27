# Tour 02 — Write path

~15 minutes. Goal: see every stage of a durable insert and how batching differs.

## Start here

1. `BlazeDB/Exports/BlazeDBClient.swift` — `insert`, `performSafeWrite`
2. `BlazeDB/Core/DynamicCollection.swift` — `insert`
3. `BlazeDB/Storage/PageStore.swift` — write + `synchronize`
4. `BlazeDB/Storage/WriteAheadLog.swift` — `appendDeferred`, `sync`
5. `BlazeDB/Core/DynamicCollection+Batch.swift` — `insertBatch`
6. `BlazeDB/Diagnostics/WriteProfileCollector.swift`
7. `Docs/Benchmarks/WRITE_PATH_PROFILE.md`

## Follow this symbol

`insert` → `performSafeWrite` → `collection.insert` → encode → page write (`appendDeferred`) → `synchronize` (WAL fsync + data fsync) → metadata save → `clearFetchAllCache` / `QueryCache.notifyWrite`.

Contrast: `insertBatch` writes many pages unsynchronized, then **one** `synchronize`, then applies pending indexMap updates.

## Invariants

- Successful public insert returns only after durability boundary for that path.
- Do not publish secondary indexes as durable if `synchronize` failed (#281).
- Profiler counters must not invent fake fsyncs (two FDs ⇒ two counts is expected).

## Associated tests

- `BlazeDBTests/Tier0Core/Diagnostics/WriteProfileCollectorTests.swift` (`testEnabledCollectorRecordsStagesBytesAndSyscalls`)
- `BlazeDBTests/Tier0Core/Durability/TransactionDurabilityTests.swift`
- `BlazeDBTests/Tier1Core/API/ByteKVAPITests.swift`
- Persistence suites under `BlazeDBTests/Tier1Core/Persistence/`

## Try it

```bash
./dev test WriteProfileCollectorTests
BLAZEDB_WRITE_PROFILE=1 BLAZEDB_BENCH_MODE=write_profile \
  BLAZEDB_WRITE_PROFILE_RECORDS=10 \
  swift run -c release BlazeDBBenchmarks
```

## Open work

#276 (txn write-through), #281, #284 (`updateBatch`), #291 (matrix).

## Extension ideas

1. More write_profile stages — **already tracked** (#291).
2. Share one commit boundary helper — **requires maintainer design** (not filed as refactor).
3. Docs-only SAFETY_MODEL honesty — **already tracked** (#294).
