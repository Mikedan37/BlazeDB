# BlazeDB Performance

**Benchmarks, methodology, and performance invariants.**

> **Canonical numbers:** [`Docs/Benchmarks/RESULTS.md`](../Benchmarks/RESULTS.md) and [`Docs/Benchmarks/COMPARISON.md`](../Benchmarks/COMPARISON.md) (refreshed June 2026, release build, 600k PBKDF2). Figures elsewhere in this repo may be design targets or pre-hardening measurements — verify against the benchmark harness before citing.

---

## Measured performance (release, encrypted baseline)

From `./Scripts/run_comparison_benchmarks.sh --release` on Apple Silicon (June 2026):

| Operation | BlazeDB (secure) | SQLite (reference) | Notes |
|-----------|-----------------:|-------------------:|-------|
| Insert 1K (sequential) | **2.5 ms** (~276 ops/s) | **0.0007 ms** | SQLite is unencrypted; BlazeDB pays AES-GCM per page |
| Read 1K (indexed UUID) | **0.009 ms** (~110k ops/s) | **0.001 ms** | ~7× slower than SQLite; still sub-10µs per read |
| Cold open | **~1.12 s** | **~0.6 ms** | 600k PBKDF2 dominates (~97% of cold wall time) |
| Warm reopen (session cache) | **~26 ms** | N/A | Same process; skips PBKDF2 after first verified open |
| InsertMany 10K (max profile, batch 1000) | **~334 ms** | **~0.6 ms** | Single persist at end |

**Takeaway:** BlazeDB engine work (layout, PageStore, migration) is ~**28 ms** on warm open. The ~1.1 s cold-open cost is intentional KDF work, not a storage regression. See [DATABASE_SESSION_KEY_LIFECYCLE.md](../Security/DATABASE_SESSION_KEY_LIFECYCLE.md).

---

## Design targets (not current harness measurements)

The table below describes **engineering goals** for future optimization. They are **not** reproduced by the current encrypted benchmark harness.

| Operation | Target latency | Target throughput | Notes |
|-----------|---------------|-------------------|-------|
| Insert (single) | 0.4–0.8 ms | 1,200–2,500 ops/sec | With WAL fsync |
| Insert (batch 100) | 15–30 ms | 3,300–6,600 ops/sec | Amortized fsync |
| Fetch (by ID) | 0.2–0.4 ms | 2,500–5,000 ops/sec | Index lookup |
| Query (indexed) | 2–5 ms | 200–500 queries/sec | With index selection |
| Update / delete | 0.3–1.0 ms | 1,000–3,300 ops/sec | With index maintenance |

---

## Multi-core scaling (design goal)

BlazeDB is designed to scale with core count under concurrent workloads:

- **2 cores**: ~2× throughput (target)
- **4 cores**: ~3.5× throughput (target)
- **8 cores**: ~6× throughput (target)

The comparison harness is single-threaded; validate multi-core claims with workload-specific benchmarks.

---

## Query performance characteristics

**Indexed reads:** Measured at ~0.009 ms (see RESULTS.md). Hash-based indexes provide O(1) lookups.

**Full scans:** Linear with dataset size; memory-mapped I/O.

**Cached queries:** TTL-based expiration (60s) with smart invalidation for repeated query patterns.

---

## Performance invariants

### Guaranteed characteristics

1. **Sub-millisecond indexed lookups** at read benchmark scale (warm path, post-KDF)
2. **Predictable latency** under normal single-threaded load
3. **Bounded memory** — session keys and caches scoped per process

### Regression testing

- No operation degrades >10% between versions (where benchmarks exist)
- Open-profile spans documented for KDF policy decisions
- Benchmark docs aligned with `KeyManager` iteration count

---

## Methodology

Run benchmarks with:

```bash
./Scripts/run_comparison_benchmarks.sh --release
python3 Scripts/publish_benchmark_results.py
```

See [`Docs/Benchmarks/README.md`](../Benchmarks/README.md) for the full matrix, SQLite comparison rules, and historical notes.

---

## Comparison with other databases (honest harness)

### Insert 1K (sequential, June 2026)

| Database | Avg latency | Notes |
|----------|------------:|-------|
| BlazeDB (encrypted) | 2.5 ms | AES-256-GCM + WAL |
| SQLite | 0.0007 ms | WAL, no encryption |

SQLite wins raw insert throughput. BlazeDB trades speed for encryption-by-default.

### Read 1K (indexed UUID)

| Database | Avg latency | Notes |
|----------|------------:|-------|
| BlazeDB (encrypted) | 0.009 ms | Decrypt + index lookup |
| SQLite | 0.001 ms | Plain B-tree |

Both are fast at this scale; BlazeDB is ~7× slower, still sub-10µs per read.

### Deprecated comparison block (pre-harness, do not cite)

The following appeared in earlier doc drafts and mixed frameworks without a common harness:

```
BlazeDB: 142ms total for 1K inserts  ← NOT from BlazeDBBenchmarks
SQLite: 156ms                          ← NOT comparable (different stack, no encryption)
```

Use [`COMPARISON.md`](../Benchmarks/COMPARISON.md) instead.

---

## Optimization techniques

### Query caching

- TTL: 60 seconds
- Smart invalidation on writes

### Batch operations

- Amortize WAL fsync costs
- `insertMany` / `deleteMany` with batch profiles (see RESULTS.md durable vs max)

### Memory-mapped I/O

- OS-level page caching for reads

---

## Bottlenecks and limitations

### Current bottlenecks

1. **PBKDF2 on cold open** — ~1.1 s at 600k iterations (by design)
2. **Per-page encryption** — insert/read overhead vs plain SQLite
3. **WAL fsync** — durability guarantee adds latency per write

### Future optimizations

- OS keychain wrapping to avoid repeated PBKDF2 across app restarts (policy TBD)
- Async I/O with completion handlers
- Batch fsync for better throughput

---

## Performance tuning

### Best practices

1. **Use batch operations** — `insertMany` with max profile for peak throughput
2. **Create indexes** on frequently queried fields
3. **Reuse process session** — avoid `clearSessionKeys()` between handle reopens in the same app session
4. **Call `clearSessionKeys()`** when the user locks the app or switches accounts

---

For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).
For transaction performance, see [TRANSACTIONS.md](TRANSACTIONS.md).
