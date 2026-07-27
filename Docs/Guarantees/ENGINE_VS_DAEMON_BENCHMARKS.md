# Engine benchmarks vs daemon-mediated access

You can put BlazeDB behind a single owning daemon. That is useful. It measures a **different system boundary**.

## Two different measurements

**In-process (engine) path**

application call → BlazeDB API → storage engine → filesystem

**Daemon path**

client → IPC/network → daemon queue → BlazeDB → response

Those answer different questions. Do not mix the numbers.

## What current benchmarks measure

Existing stress tests and benchmarks do not reveal one universal “BlazeDB limit.” They reveal the limit of a particular combination: hardware, filesystem, durability mode, encryption, database size, record size, indexes, read/write mix, transaction size, concurrency, API path, warm/cold cache, and sync frequency.

A result like “20,000 writes/sec” means: this workload hit 20,000 writes/sec under this configuration on this machine. Numbers without that context are noise.

## What a daemon can improve

The daemon does **not** make the storage engine multi-writer. There is still one serialized writer inside BlazeDB.

It can still help the overall system by coordinating work:

- **Batching / group commit** — many small client writes become one transaction and one WAL/fsync cycle
- **Connection multiplexing** — one process owns the open DB, keys, caches, indexes, and file descriptors
- **Backpressure** — bound the write queue so latency stays stable under load
- **Read concurrency** — serve concurrent reads while serializing writes, without letting clients touch the file

Honest claim:

> Daemon-mediated batching can raise effective application throughput while preserving BlazeDB’s single-writer ownership model.

Not:

> BlazeDB supports 1,000 concurrent writers.

Clients may be concurrent. The engine writer stays serialized.

## What a daemon cannot remove

One serialized mutation path, WAL bandwidth, fsync latency, encryption cost, index maintenance, device bandwidth, and lock duration for large transactions.

A socket in front of BlazeDB does not turn it into a parallel-write engine.

## Benchmark both layers

**Engine benchmarks** (in-process): put/get/delete, transactional batches, indexed queries, encryption on/off, WAL/fsync modes, size scaling, cold vs warm cache, recovery time, concurrent readers plus one writer.

**Daemon benchmarks** (many clients, one owner): requests/sec, end-to-end latency (p50/p95/p99), queue depth, batch size, group-commit interval, client count, read/write mix, overload/backpressure, daemon crash/restart recovery.

Stress limits measured in-process are real for that path. They are not necessarily the best achievable **system** throughput. A coordinated daemon may extract more from the same engine through batching, group commit, queueing, and cache reuse. That experiment fits BlazeDB’s design better than letting multiple processes fight over one encrypted WAL file.

See also: [WHY_SINGLE_WRITER.md](WHY_SINGLE_WRITER.md) · [Benchmarks README](../Benchmarks/README.md)
