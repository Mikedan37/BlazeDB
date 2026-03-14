# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 1:12 AM

**Condition:** `mvcc_off` (`mvcc=off`, `wal=on`, `encryption=on`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| mvcc_off | supported | Insert (1K records) | 167 | 5.795 | 5.632 | 11.361 | 13.104 | 511750 | 0.001 | 0.001 | 0.002 | 0.002 | 1000 | Small records, sequential insert |
| mvcc_off | supported | Insert (10K records) | 18 | 54.483 | 51.556 | 99.599 | 107.684 | 578401 | 0.001 | 0.001 | 0.002 | 0.002 | 10000 | Medium records, sequential insert |
| mvcc_off | supported | Read (1K records) | 291798 | 0.003 | 0.003 | 0.005 | 0.008 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID |
| mvcc_off | supported | InsertMany (10K records, batch 100) | 199 | 497.570 | 510.684 | 919.450 | 989.313 | 524167 | 0.190 | 0.182 | 0.212 | 0.245 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) |
| mvcc_off | supported | DeleteMany (10K records, batch 100) | 824 | 121.229 | 126.568 | 210.605 | 218.676 | 1296359 | 0.072 | 0.066 | 0.075 | 0.157 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) |
| mvcc_off | supported | InsertMany (durable profile, batch 100) | 168 | 592.995 | 588.620 | 1095.203 | 1154.493 | 526704 | 0.190 | 0.180 | 0.226 | 0.447 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist |
| mvcc_off | supported | InsertMany (max profile, batch 1000) | 388 | 2535.989 | 2853.968 | 4447.802 | 4447.802 | 574747 | 1.739 | 1.685 | 1.887 | 1.887 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
| mvcc_off | supported | DeleteMany (durable profile, batch 100) | 434 | 230.155 | 231.546 | 412.358 | 430.712 | 1262299 | 0.074 | 0.067 | 0.074 | 0.215 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist |
| mvcc_off | supported | DeleteMany (max profile, batch 1000) | 6910 | 142.878 | 147.137 | 229.467 | 229.467 | 1393341 | 0.681 | 0.629 | 0.715 | 0.715 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) |
| mvcc_off | supported | Cold open | 16 | 62.470 | 52.042 | 52.773 | 52.773 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) |
