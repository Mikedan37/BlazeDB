# Engine benchmarks vs daemon-mediated access

You can put BlazeDB behind a single owning daemon. That is useful. It measures a **different system boundary**.

## The pattern is already proven

BlazeAgent (and similar owning services) already demonstrate:

```text
agent clients → daemon / agent service → one BlazeDB owner
```

That is evidence, not speculation:

- BlazeDB can sit behind a long-lived service
- multiple callers can interact indirectly with one database owner
- the database file remains single-writer
- the daemon can manage lifecycle, queues, and persistence
- the pattern works in a real project, not only on a whiteboard

So “other processes talk to one owner” is not merely a FAQ workaround. It is an architecture BlazeDB already supports through embedding and application-owned services.

Keep the three roles distinct:

| Role | What it is |
|------|------------|
| BlazeAgent (or any owning service) | A real application that owns BlazeDB through a daemon |
| `Experiments/DaemonBatching` | Measures ownership and batching strategies |
| BlazeDB daemon product | Does not exist and is not currently justified |

## Decision rule

**No product promotion without both measured benefit and demonstrated demand.**

| Question | Status |
|----------|--------|
| Can BlazeDB run inside a service? | Already yes (apps, Vapor, Docker, C ABI / Go, BlazeAgent-style owners) |
| Can one owner coordinate many clients? | Already proven as an architecture |
| How much do batching / group commit / queue coordination add vs direct embed and unbatched daemon access? | Worth measuring |
| Should that become a supported BlazeDB daemon product? | Not without evidence |

Strong batching numbers without a generalized multi-process product need produce a clever artifact nobody needs. An application-specific owner (BlazeAgent, a Vapor service, Go via the C ABI) may already be the right shape.

Until both product gates pass, the architecture stays:

```text
one process owns the database file
other code embeds BlazeDB or talks to that owner
```

## Research harness (allowed)

Bounded experiment only: [Experiments/DaemonBatching/](../../Experiments/DaemonBatching/).

The harness is **not** asking “Can this architecture work?” That is already answered.

It asks:

> How much performance do batching, group commit, and queue coordination add compared with direct embedding and unbatched daemon access?

Prefer realistic traffic when possible (for example, extract or replay request patterns from an owning service such as BlazeAgent) over synthetic “N clients store the word banana” loads.

Scope:

- one daemon process owning one database
- Unix domain socket locally
- fixed request format
- put / get / batch only
- configurable batch window and client count
- **no** public SDK, support promise, auth product, tools-table entry, or new Blaze* brand

Measure under the **same durability mode**:

- direct in-process writes
- daemon unbatched writes
- daemon batched writes
- p50 / p95 / p99 latency, throughput, queue depth, fsync count, batch size
- crash and restart behavior

Not:

> Should BlazeDB become a server database?

A negative result is still useful: it avoids months of protocol, packaging, and support work for a generalized product nobody needs.

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

See also: [WHY_SINGLE_WRITER.md](WHY_SINGLE_WRITER.md) · [Benchmarks README](../Benchmarks/README.md) · [Experiments/DaemonBatching](../../Experiments/DaemonBatching/)
