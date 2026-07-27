# Learning paths

Pick a path that matches your background. Each path ends at **existing** open issues: this guide does not create tickets.

Hub: [CODEBASE_MAP](../Architecture/CODEBASE_MAP.md) · [ISSUE_CODE_INDEX](ISSUE_CODE_INDEX.md) · [ISSUE_GUIDE](ISSUE_GUIDE.md) · [Tours](../Architecture/TOURS/)

---

## Path A: First documentation contribution

**Expected time:** 30–90 minutes  
**Difficulty:** starter

### Read

1. [README.md](../../README.md): supported product
2. [Docs/README.md](../README.md): doc authority map
3. [ISSUE_GUIDE.md](ISSUE_GUIDE.md)
4. Tour: none required; optionally [01_OPEN_AND_RECOVERY](../Architecture/TOURS/01_OPEN_AND_RECOVERY.md) for vocabulary

### Good issues (current)

| Issue | Why safe |
|-------|----------|
| #173 | Convenience guide → non-deprecated `open` |
| #174 | `put` → upsert docs |
| #259 | Stop advertising `blazedb doctor` as subcommand |
| #261 / #292 | Soften O(log n) query docs |
| #272 | Stale `Docs/Benchmarks/LATENCY.md` |
| #273 | `SECURITY.md` KDF claims vs 600k PBKDF2 |
| #286 / #287 / #288 | Migration/RLS doc honesty (288 is docs-only) |
| #293 / #294 | Durability / SAFETY_MODEL wording |

### Validation

```bash
# Docs-only PRs: prove claims against code
rg -n "enableRLS|shouldEnforceRLS" BlazeDB/Exports/BlazeDBClient.swift BlazeDB/Exports/BlazeDBClient+RLS.swift
rg -n "func put|upsert" BlazeDB/Exports/PublicFacadeAPI.swift
# No Tier0 required for pure markdown
```

### What you learn

Product boundaries, which docs are canonical vs historical, how to ground claims in symbols.

---

## Path B: CLI contribution

**Expected time:** 1–3 hours  
**Difficulty:** starter → intermediate

### Read

1. `BlazedbCLI/BlazedbEntry.swift`: `@main` routing
2. `BlazeShell/CLIHelp.swift`, `BlazeShell/DeveloperCommands.swift`
3. `BlazeDoctor/main.swift`, `BlazeDump/main.swift`, `BlazeInfo/main.swift` (separate tools)
4. Tour: [06_CLI](../Architecture/TOURS/06_CLI.md)
5. Tests: `BlazeDBCLITests/DeveloperCommandsTests.swift`, `BlazeDBCLITests/BlazeCLICoreTests.swift`

### Good issues

| Issue | Notes |
|-------|-------|
| #258 | `blazedb --version` SemVer |
| #259 | Docs: doctor is not a top-level subcommand |
| #290 | `--json` for Dump/Info |
| #289 | Host/tool arch mismatch diagnostics in `./dev` |

### Validation

```bash
./dev help
swift run blazedb help
# After #258: swift run blazedb --version
swift test --filter DeveloperCommandsTests
```

### Safe extensions

Version output, JSON formatting, help consistency.

### Maintainer-review boundaries

Destructive restore/repair, password-on-argv handling, anything that mutates DB files without clear confirmation.

---

## Path C: Query and indexing

**Expected time:** half day+  
**Difficulty:** intermediate → advanced

### Read

1. `BlazeDB/Query/QueryBuilder.swift`: `execute` / `_executeStandard`
2. `BlazeDB/Query/QueryExplain.swift`
3. `BlazeDB/Core/DynamicCollection.swift`: `fetchAll`, `runQuery*`
4. `BlazeDB/Core/DynamicCollection+Optimized.swift`: fetchAll cache
5. Tour: [03_QUERY_PATH](../Architecture/TOURS/03_QUERY_PATH.md)

### Related issues

| Issue | Kind |
|-------|------|
| #261, #292 | **Docs**: O(log n) honesty |
| #274 | **Enhancement / design**: wire indexes or honest explain |
| #280 | **Correctness**: stale fetchAll cache |
| #279 | **Correctness**: nested `queue.sync` deadlock (not beginner) |

Default public execution is **`fetchAll` + in-memory filter**: do not assume indexed execution.

### Validation

```bash
./dev test QueryPlannerStrategyContractTests
./dev tests Query
```

---

## Path D: Transactions and durability

**Expected time:** multi-day  
**Difficulty:** advanced / maintainer-sensitive

> **Not beginner work.** Wrong changes lose committed data or weaken crash recovery.

### Read

1. Tours: [02_WRITE_PATH](../Architecture/TOURS/02_WRITE_PATH.md), [04_TRANSACTIONS](../Architecture/TOURS/04_TRANSACTIONS.md), [01_OPEN_AND_RECOVERY](../Architecture/TOURS/01_OPEN_AND_RECOVERY.md)
2. `BlazeDBClient.beginTransaction` / `commitTransaction` / `rollbackTransaction` / `performSafeWrite`
3. `PageStore.synchronize`, `WriteAheadLog.appendDeferred` / `sync`
4. `Docs/Benchmarks/WRITE_PATH_PROFILE.md`
5. `BlazeDBTests/Tier0Core/Durability/TransactionDurabilityTests.swift`

### Related issues

| Issue | Role |
|-------|------|
| #276 | Write-through under txn; amortize **blocked on #291** |
| #277 | Crash after commit can restore pre-txn backup |
| #281 | insertBatch secondary indexes before synchronize |
| #283 | Linux overflow write without barrier |
| #291 | Widen write-profile matrix + external fsync check |

### Required invariants

- Rollback restores pre-txn visible state
- Crash **before** successful commit must not publish partial txn as committed
- Crash **after** successful commit must not resurrect pre-txn backup (#277)
- Durability modes remain as documented in `Docs/Status/DURABILITY_MODE_SUPPORT.md` (fix when docs lag code)
- Do not silently drop fsyncs to “win” benchmarks

### Validation

```bash
./dev test TransactionDurabilityTests
./dev test WriteProfileCollectorTests
BLAZEDB_BENCH_MODE=write_profile BLAZEDB_WRITE_PROFILE_RECORDS=10 \
  swift run -c release BlazeDBBenchmarks
# Prefer arch -arm64 ./dev tier0 before claiming durability PRs ready
```

---

## Path E: BlazeDBC / language bindings

**Expected time:** half day+  
**Difficulty:** intermediate → maintainer-sensitive (ABI)

### Read

1. `BlazeDBC/include/blazedb.h`
2. `BlazeDBC/BlazeDBC.swift`
3. [C_ABI_BYTE_KV](../Architecture/C_ABI_BYTE_KV.md)
4. `Examples/C/hello_blazedb.c`, `Examples/Go/README.md` (Go sources not checked in yet: #264)
5. Tour: [05_BLAZEDBC](../Architecture/TOURS/05_BLAZEDBC.md)
6. `BlazeDBTests/Tier1Core/API/BlazeDBCSmokeTests.swift`

### Related issues

| Issue | Notes |
|-------|-------|
| #264 | Checked-in Go/cgo smoke + CI |
| #265 | Curate BlazeDBC artifacts + CI-link C example |
| #267 | `blazedb_last_error` |

### Safe extensions

Better examples, smoke tests, bounded error reporting (#267).

### Maintainer-review boundaries

Exported symbol changes, ownership/`free` semantics, struct layout, thread-safety guarantees.

### Validation

```bash
swift test --filter BlazeDBCSmokeTests
swift build -c release --product BlazeDBC
```

---

## Path F: Performance investigation

**Expected time:** hours → days  
**Difficulty:** intermediate → advanced

### Read

1. Tour: [07_TESTING_AND_BENCHMARKS](../Architecture/TOURS/07_TESTING_AND_BENCHMARKS.md)
2. `BlazeDBBenchmarks/main.swift`, `BlazeDBBenchmarks/WriteProfiler.swift`, `BlazeDBBenchmarks/OpenProfiler.swift`
3. `Docs/Benchmarks/WRITE_PATH_PROFILE.md`
4. `BlazeDB/Diagnostics/WriteProfileCollector.swift`

### Related issues

| Issue | Notes |
|-------|-------|
| #270 | Platform PBKDF2 (keep 600k iterations) |
| #271 | `engine_only` cold open still pays KDF: attribution |
| #275 | LiveQuery refresh cost |
| #291 | Widen write-profile + external fsync validation |
| #276 | Optimize only after #291 |

### Rules

- Measure before optimizing
- Preserve durability and correctness
- Record machine/environment metadata
- Use external syscall verification when relevant (`fs_usage` / `strace`)

### Validation

```bash
BLAZEDB_BENCH_MODE=write_profile swift run -c release BlazeDBBenchmarks
BLAZEDB_BENCH_MODE=open_profile swift run -c release BlazeDBBenchmarks
./dev test WriteProfileCollectorTests
```
