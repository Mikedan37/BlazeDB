# BlazeDB Benchmarks

**Date:** Jun 30, 2026 at 11:38 PM

**Condition:** `baseline` (`mvcc=off`, `wal=on`, `encryption=on`)

> **Reading SQLite columns:** Plain SQLite (no encryption). `journal_mode=WAL`, `synchronous=FULL`. Per-row insert rows: BlazeDB `insert()` vs SQLite `BEGIN IMMEDIATE` + `INSERT` + `COMMIT` per row (one fsync boundary each). Batch rows: BlazeDB `insertMany(batch)` vs SQLite `BEGIN` + N× `INSERT` + `COMMIT` per batch. BlazeDB `baseline` includes AES-256-GCM + PBKDF2 (600k) on cold open. Use condition `encryption_off_requested` (compile flag) for engine-only overhead.

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| baseline | supported | InsertMany (max profile, batch 1000) | 3431 | 273.952 | 302.529 | 464.374 | 464.374 | 1330321 | 0.694 | 0.680 | 0.710 | 0.710 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
