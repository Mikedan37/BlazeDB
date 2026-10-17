# Why is BlazeDB single-writer?

BlazeDB uses a **single-owner file** model as its current safety boundary.

One process at a time owns writes to a given `.blazedb` file (enforced with an exclusive file lock). Inside that owner process, BlazeDB supports concurrent readers, serialized writes, transactions, and WAL-backed crash recovery.

**This is not the same as “only one client in your system.”** On **macOS and Linux**, a common supported shape is:

```text
many clients  →  queue / RPC  →  one daemon or service  →  one BlazeDB open
```

That daemon serializes writes and holds the single engine connection. Examples in this repo include Vapor/CLI owners, Go workers via `BlazeDBC`, and BlazeAgent-style services ([ENGINE_VS_DAEMON_BENCHMARKS.md](ENGINE_VS_DAEMON_BENCHMARKS.md)).

**iOS and other sandboxed app extensions** usually cannot run a separate long-lived database owner for other processes. There, BlazeDB typically lives **inside the app process** (same pattern as DocC’s `SeekerDatabase`).

What **does not** work: two unrelated processes each opening the same database file for write without coordination — the second open should fail or risk corruption.

Supporting writers across processes would require a substantially different coordination model for locking, commit ordering, WAL recovery, encryption state, caches, and index maintenance. That would expand both the corruption risk and the recovery surface for a deployment model BlazeDB does not currently target.

The supported model is therefore:

- one process owns the database
- reads may run concurrently in that process
- writes are serialized
- another process must go through the owner, use its own database, or use a server database

A mediating daemon queues and batches requests for multiple clients; the **file** still has one BlazeDB engine writer. BlazeDB does not ship a generic multi-tenant database server — you own the daemon, queue, and API.

Single-writer is not a forgotten feature. It is the current product contract. Multi-writer could be explored later as a separate design.

Details and product gates: [ENGINE_VS_DAEMON_BENCHMARKS.md](ENGINE_VS_DAEMON_BENCHMARKS.md). More on safety: [SAFETY_MODEL.md](SAFETY_MODEL.md).
