# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 1:48 AM

**Condition:** `mvcc_off` (`mvcc=off`, `wal=on`, `encryption=on`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| mvcc_off | supported | Insert (1K records) | 147 | 6.599 | 6.205 | 12.276 | 14.764 | 533321 | 0.001 | 0.001 | 0.002 | 0.002 | 1000 | Small records, sequential insert |
| mvcc_off | supported | Insert (10K records) | 18 | 54.820 | 52.416 | 97.269 | 103.854 | 648927 | 0.001 | 0.001 | 0.002 | 0.002 | 10000 | Medium records, sequential insert |
| mvcc_off | supported | Read (1K records) | 286203 | 0.003 | 0.003 | 0.004 | 0.005 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID |
| mvcc_off | supported | InsertMany (10K records, batch 100) | 201 | 493.892 | 479.952 | 935.599 | 974.842 | 552485 | 0.181 | 0.171 | 0.214 | 0.273 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) |
| mvcc_off | supported | DeleteMany (10K records, batch 100) | 880 | 113.534 | 111.296 | 206.124 | 217.224 | 1345363 | 0.069 | 0.066 | 0.077 | 0.136 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) |
| mvcc_off | supported | InsertMany (durable profile, batch 100) | 166 | 598.727 | 596.381 | 1111.660 | 1151.946 | 535846 | 0.186 | 0.178 | 0.221 | 0.421 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist |
| mvcc_off | supported | InsertMany (max profile, batch 1000) | 382 | 2575.766 | 2915.454 | 4396.211 | 4396.211 | 558723 | 1.789 | 1.746 | 1.808 | 1.808 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
| mvcc_off | supported | DeleteMany (durable profile, batch 100) | 430 | 232.718 | 225.870 | 466.554 | 603.933 | 1219221 | 0.076 | 0.069 | 0.078 | 0.156 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist |
| mvcc_off | supported | DeleteMany (max profile, batch 1000) | 6800 | 144.959 | 156.277 | 232.721 | 232.721 | 1483685 | 0.637 | 0.616 | 0.714 | 0.714 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) |
| mvcc_off | supported | Cold open | 15 | 67.009 | 56.129 | 59.140 | 59.140 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) |
