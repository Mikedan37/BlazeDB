# Architecture tours

Short, code-first walks for contributors. Read with [CODEBASE_MAP](../CODEBASE_MAP.md) and [LEARNING_PATHS](../../Contributing/LEARNING_PATHS.md).

| Tour | Topic |
|------|-------|
| [01_OPEN_AND_RECOVERY](01_OPEN_AND_RECOVERY.md) | Open, KDF, WAL replay, txn backup restore |
| [02_WRITE_PATH](02_WRITE_PATH.md) | Insert, fsync, batch, write profiler |
| [03_QUERY_PATH](03_QUERY_PATH.md) | Scan-based execute, explain, caches |
| [04_TRANSACTIONS](04_TRANSACTIONS.md) | begin/commit/rollback vs write-through |
| [05_BLAZEDBC](05_BLAZEDBC.md) | C ABI byte KV |
| [06_CLI](06_CLI.md) | `blazedb`, `./dev`, Doctor/Dump/Info |
| [07_TESTING_AND_BENCHMARKS](07_TESTING_AND_BENCHMARKS.md) | Tiers, filters, bench modes |

Extension ideas in tours are **not** GitHub issues until someone validates behavior, ownership, and tests.
