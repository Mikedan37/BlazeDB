# Why is BlazeDB single-writer?

BlazeDB uses a single-owner file model as its current safety boundary.

One process owns the `.blazedb` file. Inside that process, BlazeDB supports concurrent readers, serialized writes, transactions, and WAL-backed crash recovery. Multiple applications must not open the same file for writing.

Supporting writers across processes would require a substantially different coordination model for locking, commit ordering, WAL recovery, encryption state, caches, and index maintenance. That would expand both the corruption risk and the recovery surface for a deployment model BlazeDB does not currently target.

The supported model is therefore:

- one process owns the database
- reads may run concurrently in that process
- writes are serialized
- another process must go through the owner, use its own database, or use a server database

A mediating daemon can queue and batch requests for multiple clients, but BlazeDB still has one engine writer.

Single-writer is not a forgotten feature. It is the current product contract. Multi-writer could be explored later as a separate design.

Details and product gates: [ENGINE_VS_DAEMON_BENCHMARKS.md](ENGINE_VS_DAEMON_BENCHMARKS.md). More on safety: [SAFETY_MODEL.md](SAFETY_MODEL.md).
