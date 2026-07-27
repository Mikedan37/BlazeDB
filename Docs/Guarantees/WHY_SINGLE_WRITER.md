# Why is BlazeDB single-writer?

BlazeDB runs inside a single application process.

Only one writer may modify the database file at a time. That is the **current** product boundary. It keeps locking, crash recovery, encryption, and index maintenance simple enough to test and trust.

Multi-writer support is not part of today’s contract. Exploring it later would be a separate design (and a harder concurrency and recovery problem), not a silent assumption you can make now.

Within one process, BlazeDB still supports:

- concurrent readers
- serialized writes
- transactions
- WAL-backed crash recovery

Do not share one `.blazedb` file across applications or place it on a network filesystem. If multiple processes need to write the same data today, use a server database or a daemon/process that mediates access to the DB.

A daemon can raise system throughput through batching and queueing. It does not make BlazeDB multi-writer. Details and product gates: [ENGINE_VS_DAEMON_BENCHMARKS.md](ENGINE_VS_DAEMON_BENCHMARKS.md).

More detail on safety: [SAFETY_MODEL.md](SAFETY_MODEL.md)
