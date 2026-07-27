# Tour 07 — Testing and benchmarks

~15 minutes. Goal: run the smallest useful check for your change.

## Start here

1. `./dev` / `BlazeShell/DeveloperCommands.swift`
2. `Docs/Testing/CI_AND_TEST_TIERS.md`
3. `Package.swift` — `BlazeDB_Tier0` … `Tier3_*`
4. `BlazeDBBenchmarks/main.swift` — `BLAZEDB_BENCH_MODE`
5. `BlazeDBBenchmarks/WriteProfiler.swift`, `BlazeDBBenchmarks/OpenProfiler.swift`
6. `Docs/Benchmarks/WRITE_PATH_PROFILE.md`, `Docs/Benchmarks/README.md`

## Follow this symbol

Focused: `./dev tests <search>` → `./dev test <filter>` → SwiftPM `--filter`.  
Broad: `./dev tier0` (gate) → tier1+ as needed.  
Bench: `BLAZEDB_BENCH_MODE=throughput|open_profile|write_profile`.

## Invariants

- Tier0 is the durability/correctness gate — use it for storage/WAL/txn PRs.
- Compile-only Android/KMM checks ≠ runtime proof.
- Benchmark numbers are environment-specific; do not paste into docs as guarantees without metadata.
- Experimental B+ tests (`BPlusTreeNodeTests`) do not prove production indexes.

## Associated tests (examples)

| Area | Filter / path |
|------|----------------|
| Write profile | `WriteProfileCollectorTests` |
| Txn durability | `TransactionDurabilityTests` |
| C ABI | `BlazeDBCSmokeTests` |
| RLS | `RLSEnforcementClientTests` |
| CLI | `DeveloperCommandsTests` |

## Try it

```bash
./dev help
./dev tests Durability
./dev test WriteProfileCollectorTests
# Optional (slow): arch -arm64 ./dev tier0
BLAZEDB_BENCH_MODE=write_profile BLAZEDB_WRITE_PROFILE_RECORDS=10 \
  swift run -c release BlazeDBBenchmarks
```

## Open work

#263 (compat fixtures gate), #271 (bench attribution), #289 (arch mismatch), #291 (profile matrix).

## Extension ideas

1. Widen write-profile matrix — **already tracked** (#291).
2. Shorter CI bench smoke — **safe untracked exploration** until design agreed (see audit N11; not filed).
3. Replace headline LATENCY.md — **already tracked** (#272).
