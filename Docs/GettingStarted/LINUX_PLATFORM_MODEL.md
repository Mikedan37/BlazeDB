# BlazeDB Linux Platform Model

## Purpose

BlazeDB is designed as a **cross-platform database engine** with two distinct deployment targets:

1. **Apple Platforms** (iOS, macOS, watchOS, tvOS): Full-featured database with deep platform integration
2. **Linux** (aarch64, x86_64): Core engine deployment target for headless, embeddable use cases

This document explains the feature matrix, design rationale, and explicit limitations for Linux deployments.

---

## Feature Matrix

| Feature | Apple Platforms | Linux | Notes |
|---------|----------------|-------|-------|
| **Core CRUD** | | | Insert, fetch, update, delete |
| **Transactions** | | | ACID transactions (serial on Linux) |
| **BlazeBinary Encoding** | | | Custom binary format, CRC32 checksums |
| **Page-Based Storage** | | | 4KB pages, encryption, MVCC |
| **Secondary Indexes** | | | Single-field and compound indexes |
| **Query Builder** | | | Type-safe query construction |
| **MVCC (Multi-Version Concurrency)** | | | Snapshot isolation, version management |
| **Encryption (AES-256-GCM)** | | | Per-page encryption, PBKDF2/Argon2 KDF |
| **Backup & Restore** | | | Full database backup with metadata |
| **Async Queries** | | | `async/await` APIs gated on Apple |
| **SwiftUI Bindings** | | | `@BlazeQuery`, `@BlazeQueryTyped` property wrappers |
| **Combine Integration** | | | Reactive query updates |
| **Vector Search** | | | Vector similarity indexing |
| **Spatial Indexing** | | | R-tree geospatial queries |
| **Full-Text Search** | | | Inverted index search |
| **Parallel Encoding** | | | SIMD-accelerated batch operations |
| **Batch Operations** | | | `insertBatch`, `updateBatch`, `deleteBatch` |
| **Performance Caching** | | | Query result caching, fetchAll optimization |
| **Distributed Sync** | | | Multi-database synchronization, peer discovery |
| **Network Transport** | | | SecureConnection, TCPRelay, WebSocketRelay |
| **Certificate Pinning** | | | Network.framework TLS pinning |
| **Secure Enclave** | | | Hardware-backed key storage |
| **LocalAuthentication** | | | Biometric key unlock |

---

## Security Model

### What Linux Provides

- **Data-at-Rest Encryption**: AES-256-GCM per-page encryption with PBKDF2 (10,000 iterations) or Argon2id key derivation
- **CRC32 Checksums**: Optional corruption detection (IEEE 802.3 polynomial, pure Swift implementation)
- **File Locking**: POSIX `flock()` exclusive process-level locking
- **Access Control**: File system permissions (managed by host OS)

### What Linux Does NOT Provide

- **Secure Enclave**: No hardware-backed key storage (keys stored in memory only)
- **Certificate Pinning**: No Network.framework TLS validation (transport security is external)
- **Biometric Authentication**: No LocalAuthentication integration (password-only key derivation)
- **App Attest**: No Apple-specific attestation mechanisms

### Transport Security on Linux

BlazeDB on Linux does not implement transport-layer security. Applications must:

- Use external TLS termination (nginx, HAProxy, etc.)
- Implement certificate validation at the application layer
- Use secure channels (SSH tunnels, VPNs) for remote access

---

## Design Rationale

### Why Feature Gating?

BlazeDB's advanced features rely on Apple-specific frameworks and patterns:

- **SwiftUI/Combine**: Apple-only UI frameworks
- **Network.framework**: Apple-only TLS and certificate management
- **Security.framework**: Apple-only keychain and Secure Enclave
- **Compression.framework**: Apple-only compression APIs
- **Heavy Concurrency**: Task.detached, DispatchQueue.concurrentPerform, actor-based caching

Linux deployments are intended for:

- **Headless servers**: No UI, no SwiftUI needed
- **Embedded systems**: Minimal dependencies, core functionality only
- **Backend services**: Simple CRUD, no advanced indexing required
- **Cross-platform libraries**: Core engine that works everywhere

### Why Not "Fix" Linux to Match Apple?

1. **Framework Availability**: Many features require Apple-only frameworks that don't exist on Linux
2. **Concurrency Model**: Swift 6 strict concurrency is more restrictive on Linux (no unchecked Sendable workarounds)
3. **Performance Tradeoffs**: Parallel execution and caching add complexity without clear benefit for simple use cases
4. **Maintenance Burden**: Maintaining feature parity would require Linux-specific implementations of Apple frameworks

### Compile-Time Gating Strategy

BlazeDB uses a compile-time flag `BLAZEDB_LINUX_CORE` defined in `Package.swift`:

```swift
swiftSettings: [
.define("BLAZEDB_LINUX_CORE",.when(platforms: [.linux]))
]
```

Advanced extension files are wrapped with:

```swift
#if!BLAZEDB_LINUX_CORE
// Advanced features (async, parallel, caching, indexing)
#endif
```

This ensures:

- **Zero runtime overhead**: Gated code is not compiled on Linux
- **Clean separation**: Core logic is never mixed with platform-specific code
- **Type safety**: Compiler enforces that gated APIs are not called on Linux

---

## Explicit Non-Goals

### What We Will NOT Do

1. **SwiftUI on Linux**: No plans to port SwiftUI or create Linux alternatives
2. **Network.framework Replacement**: No plans to implement TLS/certificate pinning on Linux
3. **Secure Enclave Emulation**: No plans to simulate hardware-backed key storage
4. **Feature Parity**: Linux will remain a core-only target
5. **Concurrency Rewrites**: No plans to rewrite async code for Linux compatibility

### What We WILL Do

1. **Core Stability**: Ensure core CRUD, transactions, and storage work reliably on Linux
2. **Bug Fixes**: Fix Linux-specific bugs in core functionality
3. **Documentation**: Keep this document accurate as features evolve
4. **Testing**: Maintain Linux build verification in CI/CD

---

## Build Configuration

### Linux Build

```bash
swift build -c release
```

The `BLAZEDB_LINUX_CORE` flag is automatically defined, excluding:
- All `DynamicCollection+*.swift` extension files (except core: Metrics, Migration)
- Entire `Distributed/` directory (sync, networking, discovery)
- SwiftUI property wrappers
- Combine integration
- Advanced indexing (vector, spatial, full-text)
- Parallel execution paths
- Deprecated `BlazeCollection.swift`

### Apple Build

```bash
swift build -c release
```

The `BLAZEDB_LINUX_CORE` flag is **not** defined, including:
- All extension files
- Full feature set
- Platform-specific optimizations

---

## Migration Notes

### Moving from Apple to Linux

If you're migrating code from Apple platforms to Linux:

1. **Remove SwiftUI Bindings**: Replace `@BlazeQuery` with manual `fetch()` calls
2. **Remove Async APIs**: Replace `insertAsync()` with synchronous `insert()`
3. **Remove Batch Operations**: Replace `insertBatch()` with loops of `insert()`
4. **Remove Advanced Indexing**: Vector/spatial/search indexes are not available
5. **Remove Distributed Sync**: Multi-database sync, peer discovery, and networking are not available
6. **Simplify Concurrency**: Use serial operations instead of parallel execution

### Example Migration

**Apple (Full Features):**
```swift
// SwiftUI binding
@BlazeQuery(db: db, where: "status", equals:.string("open"))
var bugs: [BlazeDataRecord]

// Async batch insert
let ids = try await collection.insertBatchAsync(records)

// Vector search
let results = try db.query()
.vectorNearest(embedding, field: "embedding", limit: 10)
.execute()
```

**Linux (Core Only):**
```swift
// Manual fetch
var bugs: [BlazeDataRecord] = []
bugs = try db.query()
.where("status", equals:.string("open"))
.execute()
.records

// Synchronous loop
var ids: [UUID] = []
for record in records {
 ids.append(try collection.insert(record))
}

// Vector search not available - use full scan or external index
```

---

## Technical Details

### Compile-Time Flag

The `BLAZEDB_LINUX_CORE` flag is defined in `Package.swift`:

```swift
.target(
 name: "BlazeDB",
 dependencies: [...],
 path: "BlazeDB",
 swiftSettings: [
.define("BLAZEDB_LINUX_CORE",.when(platforms: [.linux]))
 ]
)
```

### Gated Files

The following files and directories are entirely gated on Linux:

**Core Extensions:**
- `DynamicCollection+Async.swift` - Async/await operations
- `DynamicCollection+Optimized.swift` - Caching, parallel filtering
- `DynamicCollection+Performance.swift` - Parallel reads, aggressive caching
- `DynamicCollection+ParallelEncoding.swift` - SIMD, parallel encoding
- `DynamicCollection+Batch.swift` - Batch operations
- `DynamicCollection+Search.swift` - Full-text search
- `DynamicCollection+Spatial.swift` - Geospatial indexing
- `DynamicCollection+Vector.swift` - Vector similarity indexing
- `DynamicCollection+Lazy.swift` - Lazy decoding
- `DynamicCollection+MetaStore.swift` - Metadata caching
- `DynamicCollection+IndexBatch.swift` - Enhanced batch index updates

**SwiftUI Integration:**
- `BlazeQuery.swift` - SwiftUI property wrapper
- `BlazeQueryTyped.swift` - Type-safe SwiftUI wrapper
- `BlazeQuery+Extensions.swift` - SwiftUI bindings

**Distributed Sync (Entire Directory):**
- `Distributed/` - All files in this directory (28 files)
 - `BlazeSyncEngine.swift` - Multi-database synchronization
 - `BlazeTopology.swift` - Connection topology management
 - `BlazeServer.swift` - Remote database server
 - `BlazeDiscovery.swift` - mDNS/Bonjour peer discovery
 - `SecureConnection.swift` - E2E encrypted connections
 - `TCPRelay.swift`, `WebSocketRelay.swift` - Transport implementations
 - All GC, validation, and relay implementations

**Deprecated:**
- `BlazeCollection.swift` - Legacy collection type (use `DynamicCollection` instead)

### Core Files (Always Enabled)

These files are always compiled on both platforms:

- `DynamicCollection.swift` - Core CRUD operations
- `PageStore.swift` - Storage engine
- `StorageLayout.swift` - Metadata management
- `BlazeBinaryEncoder.swift` - Binary encoding
- `BlazeBinaryDecoder.swift` - Binary decoding
- All core types and protocols

---

## Conclusion

BlazeDB on Linux is a **core engine deployment target**, not a feature-complete replacement for Apple platforms. This is intentional:

- **Simplicity**: Core functionality is easier to maintain and debug
- **Reliability**: Fewer dependencies mean fewer failure modes
- **Portability**: Works on any Linux system with Swift 6
- **Performance**: Core operations are fast without advanced optimizations

For full-featured database needs on Linux, consider:
- Using BlazeDB for core storage
- Implementing advanced features at the application layer
- Using external indexing services (Elasticsearch, PostgreSQL, etc.)

For Apple platforms, BlazeDB provides a complete, integrated database solution with deep platform integration.

---

## Contribution Rules

### Adding New Features

When adding new features to BlazeDB, you must declare the platform support:

1. **Core Feature**: Works on all platforms (Apple + Linux)
 - Must not use Apple-only frameworks
 - Must not use Swift 6 concurrency patterns that violate Sendable
 - Must not use static mutable state
 - Must compile cleanly on Linux

2. **Apple-Only Feature**: Works only on Apple platforms
 - Wrap entire file/extension with `#if!BLAZEDB_LINUX_CORE`
 - Document in this file's feature matrix
 - No Linux stubs or fallbacks

3. **Future Linux Support**: Optional future Linux support
 - Mark as "Future Linux Support" in feature matrix
 - Do not gate with `#if!BLAZEDB_LINUX_CORE` if Linux support is planned
 - Document Linux requirements/limitations

### Gating Rules

- **Never** conditionally compile inside methods
- **Always** gate entire files or extensions
- **Never** create Linux stubs or fake implementations
- **Never** use runtime platform checks (`#if os(Linux)` inside functions)

### Example: Adding a New Feature

**Core Feature (All Platforms):**
```swift
// BlazeDB/Core/NewCoreFeature.swift
// No gating - compiles on all platforms
extension DynamicCollection {
 public func newCoreFeature() throws {
 // Core logic only
 }
}
```

**Apple-Only Feature:**
```swift
// BlazeDB/Core/DynamicCollection+AppleFeature.swift
#if!BLAZEDB_LINUX_CORE

extension DynamicCollection {
 public func newAppleFeature() async throws {
 // Apple-specific implementation
 }
}

#endif //!BLAZEDB_LINUX_CORE
```

---

**Last Updated**: 2025-01-XX
**BlazeDB Version**: 2.5.x
**Swift Version**: 6.0+

