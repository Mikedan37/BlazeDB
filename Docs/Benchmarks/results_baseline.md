# BlazeDB Benchmarks

**Date:** Mar 14, 2026 at 1:00 AM

**Condition:** `baseline` (`mvcc=on`, `wal=on`, `encryption=on`)

| Condition | Support | Benchmark | BlazeDB (ops/sec) | BlazeDB avg ms | BlazeDB p50 ms | BlazeDB p95 ms | BlazeDB p99 ms | SQLite (ops/sec) | SQLite avg ms | SQLite p50 ms | SQLite p95 ms | SQLite p99 ms | Dataset Size | Notes |
|-----------|---------|-----------|-------------------|----------------|----------------|----------------|----------------|------------------|---------------|---------------|---------------|---------------|--------------|-------|
| baseline | supported | Insert (1K records) | 163 | 5.938 | 6.167 | 11.217 | 12.154 | 453316 | 0.001 | 0.001 | 0.002 | 0.003 | 1000 | Small records, sequential insert |
| baseline | supported | Insert (10K records) | 16 | 61.402 | 60.843 | 114.865 | 122.258 | 636499 | 0.001 | 0.001 | 0.002 | 0.002 | 10000 | Medium records, sequential insert |
| baseline | supported | Read (1K records) | 324260 | 0.003 | 0.003 | 0.003 | 0.003 | N/A | N/A | N/A | N/A | N/A | 1000 | Indexed reads by UUID |
| baseline | supported | InsertMany (10K records, batch 100) | 184 | 537.712 | 521.469 | 1003.970 | 1083.476 | 539141 | 0.185 | 0.178 | 0.193 | 0.314 | 10000 | Throughput in records/sec; latency stats are per insertMany(batch) |
| baseline | supported | DeleteMany (10K records, batch 100) | 800 | 124.889 | 123.574 | 221.825 | 231.239 | 1283859 | 0.073 | 0.066 | 0.082 | 0.140 | 10000 | Throughput in records/sec; latency stats are per deleteMany(batch) |
| baseline | supported | InsertMany (durable profile, batch 100) | 154 | 648.817 | 639.536 | 1215.778 | 1256.710 | 539929 | 0.185 | 0.178 | 0.196 | 0.289 | 10000 | Persist after every batch; throughput in records/sec; latency is per insertMany(batch)+persist |
| baseline | supported | InsertMany (max profile, batch 1000) | 333 | 2962.696 | 3344.067 | 4895.406 | 4895.406 | 564145 | 1.772 | 1.768 | 1.953 | 1.953 | 10000 | Single persist at end; larger batches for peak throughput; latency is per insertMany(batch) |
| baseline | supported | DeleteMany (durable profile, batch 100) | 426 | 234.432 | 231.430 | 419.901 | 450.691 | 1233964 | 0.076 | 0.069 | 0.081 | 0.133 | 10000 | Persist after every batch; throughput in records/sec; latency is per deleteMany(batch)+persist |
| baseline | supported | DeleteMany (max profile, batch 1000) | 4326 | 229.745 | 242.627 | 326.851 | 326.851 | 1497912 | 0.631 | 0.629 | 0.659 | 0.659 | 10000 | Single persist at end; larger batches for peak throughput; latency is per deleteMany(batch) |
| baseline | supported | Cold open | 19 | 52.387 | 52.507 | 53.328 | 53.328 | N/A | N/A | N/A | N/A | N/A | 1000 | Average of 10 opens (opens/sec) |
