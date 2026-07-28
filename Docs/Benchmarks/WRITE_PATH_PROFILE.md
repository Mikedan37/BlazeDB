# Write path profile

Opt-in stage instrumentation for durable writes. **Not product telemetry.**

**Context:** BlazeDB is [read-optimized, but durable writes currently scale poorly with database size](HONEST_PERFORMANCE.md). Secure ≈ engine-only in prior profiles (AES is not the whole SQLite gap). Open [`performance`](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3Aperformance) issues track publishing stage-% evidence (including **versus DB size**) before optimizing.

## Enable

```bash
export BLAZEDB_WRITE_PROFILE=1
# or run the harness:
BLAZEDB_BENCH_MODE=write_profile \
BLAZEDB_WRITE_PROFILE_RECORDS=50 \
BLAZEDB_WRITE_PROFILE_OUT=benchmark_results/write_profile \
swift run -c release BlazeDBBenchmarks
```

## Stages recorded (when enabled)

| Stage | Meaning |
|-------|---------|
| `encode` | Record binary encoding |
| `transaction.setup` | Layout / page allocation setup |
| `wal.append` | WAL framed entry write (bytes + write syscall counted) |
| `wal.fsync` | WAL `fsync` |
| `page.write` | Main-file page write (bytes + write syscall) |
| `page.fsync` | Data-file `synchronize` |
| `metadata.publish` | Catalog / secondary index / meta save (single insert) |
| `insert.total` / `insertMany.total` / `transaction.total` | Wall wrappers |

Operation metadata: path (`singleInsert` / `insertMany` / `transactionPuts`), batch size, durability mode label, steady-state flag.

## Compare three paths

The harness profiles:

1. single durable `insert` (first + steady)
2. `insertMany` (N records, one flush)
3. `beginTransaction` + N `insert` + `commitTransaction`

Use fsync/write counts and stage % to see whether InsertMany batches durability or repeats the expensive path.

## Rule

**No optimization PR until one or two stages explain most of the observed latency** (see open [`performance`](https://github.com/Mikedan37/BlazeDB/issues?q=is%3Aissue+is%3Aopen+label%3Aperformance) issues).

Hypotheses (not conclusions): repeated fsync, per-record metadata publish, serialization copies, transaction setup inside a loop.

## Distinction

| Flag | Purpose |
|------|---------|
| `BLAZEDB_WRITE_PROFILE=1` | This investigation profiler |
| `BLAZEDB_FORENSICS=1` | Older insert JSONL forensics |
| `BLAZEDB_PROFILE_OPEN=1` | Cold-open spans |

Keep production inserts free of documentary overhead unless a flag is set.
