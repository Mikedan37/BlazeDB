# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 2:03 AM

**Condition:** `encryption_off_requested` (`mvcc=on`, `wal=on`, `encryption=off`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| encryption_off_requested | supported | Insert (1K records) | 156 | 6.227 | 6.479 | 11.605 | 13.767 | 514670 | 0.001 | 0.001 | 0.002 | 0.002 | 1000 | Small records, sequential insert |
| encryption_off_requested | supported | Insert (10K records) | 16 | 63.231 | 61.983 | 118.686 | 130.571 | 595063 | 0.001 | 0.001 | 0.002 | 0.002 | 10000 | Medium records, sequential insert |
| encryption_off_requested | supported | Read (1K records) | 293606 | 0.003 | 0.003 | 0.004 | 0.004 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID |
| encryption_off_requested | supported | InsertMany (10K records, batch 100) | 186 | 532.852 | 538.744 | 1013.571 | 1083.913 | 511666 | 0.195 | 0.178 | 0.268 | 0.407 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) |
| encryption_off_requested | supported | DeleteMany (10K records, batch 100) | 815 | 122.493 | 118.409 | 219.406 | 226.536 | 1196168 | 0.078 | 0.068 | 0.098 | 0.162 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) |
| encryption_off_requested | supported | InsertMany (durable profile, batch 100) | 154 | 648.263 | 641.844 | 1220.957 | 1387.281 | 363822 | 0.274 | 0.208 | 0.568 | 0.738 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist |
| encryption_off_requested | supported | InsertMany (max profile, batch 1000) | 347 | 2833.653 | 3215.981 | 4710.831 | 4710.831 | 577302 | 1.731 | 1.742 | 1.817 | 1.817 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
| encryption_off_requested | supported | DeleteMany (durable profile, batch 100) | 435 | 229.817 | 231.208 | 419.947 | 435.398 | 1271946 | 0.073 | 0.067 | 0.081 | 0.190 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist |
| encryption_off_requested | supported | DeleteMany (max profile, batch 1000) | 6693 | 147.359 | 153.535 | 235.145 | 235.145 | 1404092 | 0.672 | 0.622 | 0.672 | 0.672 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) |
| encryption_off_requested | supported | Cold open | 18 | 54.557 | 54.750 | 55.384 | 55.384 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) |
