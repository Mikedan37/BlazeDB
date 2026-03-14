# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 12:33 AM

**Condition:** `wal_off_requested` (`mvcc=on`, `wal=on`, `encryption=on`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| wal_off_requested | partially_supported | Insert (1K records) | 164 | 5.919 | 6.137 | 11.111 | 12.172 | 120642 | 0.008 | 0.007 | 0.008 | 0.013 | 1000 | Small records, sequential insert | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | Insert (10K records) | 16 | 61.284 | 61.165 | 114.417 | 122.121 | 129995 | 0.007 | 0.007 | 0.009 | 0.010 | 10000 | Medium records, sequential insert | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | Read (1K records) | 318474 | 0.003 | 0.003 | 0.003 | 0.003 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | InsertMany (10K records, batch 100) | 183 | 540.788 | 540.631 | 984.785 | 1036.882 | 534245 | 0.187 | 0.179 | 0.205 | 0.339 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | DeleteMany (10K records, batch 100) | 798 | 125.225 | 124.390 | 219.517 | 228.615 | 1242241 | 0.076 | 0.063 | 0.073 | 0.150 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | InsertMany (durable profile, batch 100) | 153 | 652.748 | 649.303 | 1159.329 | 1219.728 | 557257 | 0.179 | 0.172 | 0.192 | 0.252 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | InsertMany (max profile, batch 1000) | 337 | 2919.700 | 3087.047 | 4817.542 | 4817.542 | 572934 | 1.744 | 1.721 | 1.859 | 1.859 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | DeleteMany (durable profile, batch 100) | 422 | 237.183 | 236.915 | 430.022 | 441.930 | 1409045 | 0.066 | 0.065 | 0.071 | 0.075 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | DeleteMany (max profile, batch 1000) | 4105 | 241.305 | 253.718 | 343.242 | 343.242 | 1344996 | 0.705 | 0.634 | 0.746 | 0.746 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) | Requested WAL=off, effective=on |
| wal_off_requested | partially_supported | Cold open | 18 | 55.213 | 55.417 | 56.158 | 56.158 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) | Requested WAL=off, effective=on |
