# Why BlazeDB Exists

Local-first applications require an embedded database that supports multi-device synchronization, end-to-end encryption, and fine-grained access control. SQLite provides ACID transactions but lacks distributed sync. Realm offers sync but requires a proprietary cloud service. CoreData has no built-in sync mechanism. None of these provide operation-log-based synchronization with cryptographic handshakes or row-level security policies.

The gap is a Swift-native, local-first database with a complete sync engine. Existing solutions either require external services, use inefficient protocols, or don't integrate encryption with the storage layer. There is no database that combines MVCC concurrency control, write-ahead logging, operation-log synchronization, and a custom binary protocol optimized for Apple platforms.

The insight is architectural: when the storage engine, sync layer, and binary protocol are designed together, the system becomes faster, more predictable, and more secure. Separate components create impedance mismatches—JSON serialization overhead, encryption applied as an afterthought, sync protocols that don't understand the storage model. Integration eliminates these costs.

BlazeDB is a fully integrated system: MVCC transactions with snapshot isolation, write-ahead logging for crash recovery, operation-log synchronization with Lamport timestamps, the BlazeBinary protocol (53% smaller than JSON), AES-256-GCM encryption, and ECDH P-256 key exchange. It's built entirely in Swift, runs on iOS, macOS, and Linux, and requires zero external dependencies.

The result is a local-first database engine that provides ACID guarantees, concurrent access without blocking, offline-first synchronization, end-to-end encryption, and row-level security—all in a single, Swift-native package. Developers get correctness, safety, and real distributed behavior without compromising on performance or platform integration.

