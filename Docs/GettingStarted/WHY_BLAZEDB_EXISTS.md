# Why BlazeDB Exists

Local-first applications require an embedded database that supports multi-device synchronization, end-to-end encryption, and fine-grained access control. SQLite provides ACID transactions but lacks distributed sync. Realm offers sync but requires a proprietary cloud service. CoreData has no built-in sync mechanism. None of these provide operation-log-based synchronization with cryptographic handshakes.

The gap is a Swift-native, local-first database designed around encrypted embedded storage with a path toward sync. Existing solutions either require external services, use inefficient protocols, or don't integrate encryption with the storage layer. There is no database that combines MVCC concurrency control, write-ahead logging, and a custom binary protocol optimized for Apple platforms in one Swift-first package.

The insight is architectural: when the storage engine, sync layer, and binary protocol are designed together, the system becomes faster, more predictable, and more secure. Separate components create impedance mismatches—JSON serialization overhead, encryption applied as an afterthought, sync protocols that don't understand the storage model. Integration eliminates these costs.

BlazeDB is a Swift-native embedded database engine with MVCC transactions, write-ahead logging for crash recovery, the BlazeBinary protocol (53% smaller than JSON in internal measurements), and AES-256-GCM encryption at rest. It runs on iOS, macOS, and Linux, ships with no external database/service requirement, and keeps a minimal SwiftPM dependency surface for crypto primitives on Linux builds.

The result is a local-first database engine that provides ACID guarantees, concurrent access without blocking, and encryption in a single Swift-native package. In the current OSS core build, distributed transport integration is intentionally deferred and not part of the default runtime surface. (Row-level security is under development and not yet available.) Developers get correctness and safety without external service coupling.

