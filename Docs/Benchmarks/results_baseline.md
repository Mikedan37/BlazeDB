# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 1:36 AM

**Condition:** `baseline` (`mvcc=on`, `wal=on`, `encryption=on`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| baseline | supported | Insert (1K records) | 162 | 5.999 | 6.032 | 11.305 | 14.814 | 489703 | 0.001 | 0.001 | 0.002 | 0.002 | 1000 | Small records, sequential insert |
| baseline | supported | Insert (10K records) | 16 | 61.841 | 60.925 | 113.924 | 128.836 | 642589 | 0.001 | 0.001 | 0.002 | 0.002 | 10000 | Medium records, sequential insert |
| baseline | supported | Read (1K records) | 314663 | 0.003 | 0.003 | 0.003 | 0.004 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID |
| baseline | supported | InsertMany (10K records, batch 100) | 193 | 514.313 | 522.712 | 925.493 | 990.908 | 566702 | 0.176 | 0.169 | 0.189 | 0.227 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) |
| baseline | supported | DeleteMany (10K records, batch 100) | 810 | 123.357 | 122.901 | 215.263 | 224.654 | 1390823 | 0.067 | 0.064 | 0.070 | 0.147 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) |
| baseline | supported | InsertMany (durable profile, batch 100) | 159 | 625.991 | 625.524 | 1139.999 | 1208.928 | 560410 | 0.178 | 0.171 | 0.192 | 0.249 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist |
| baseline | supported | InsertMany (max profile, batch 1000) | 341 | 2892.608 | 3149.518 | 4680.696 | 4680.696 | 580149 | 1.722 | 1.683 | 1.823 | 1.823 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
| baseline | supported | DeleteMany (durable profile, batch 100) | 355 | 281.517 | 275.137 | 536.757 | 583.420 | 1343553 | 0.069 | 0.067 | 0.077 | 0.120 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist |
| baseline | supported | DeleteMany (max profile, batch 1000) | 4117 | 241.410 | 258.686 | 333.789 | 333.789 | 1406069 | 0.673 | 0.616 | 0.670 | 0.670 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) |
| baseline | supported | Cold open | 18 | 54.684 | 54.663 | 56.637 | 56.637 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) |
