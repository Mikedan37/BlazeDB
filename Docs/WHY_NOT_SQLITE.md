# Why Not SQLite?

**Comparisons and tradeoffs with SQLite and other embedded databases.**

---

## Quick Comparison

| Feature | BlazeDB | SQLite | Realm | Core Data |
|---------|---------|--------|-------|-----------|
| **Encryption** | AES-256-GCM (default) | Optional extension | Optional | No |
| **Schema** | Dynamic, no migrations | Static, requires migrations | Static, migrations | Static, complex migrations |
| **Concurrency** | MVCC snapshot isolation | File-level locking | MVCC | Context-based |
| **Performance** | Predictable, optimized for Apple Silicon | Variable under load | Fast, but licensing | Variable, object graph overhead |
| **Query Language** | Fluent Swift API | SQL | Fluent API | NSPredicate |
| **Platform** | macOS/iOS/Linux (Swift) | Universal (C) | Cross-platform | macOS/iOS only |
| **Dependencies** | Zero | Zero | Large SDK | Built-in |
| **Sync** | Built-in distributed sync | None | Proprietary cloud | CloudKit (Apple only) |

---

## When to Use BlazeDB

### Use BlazeDB when:

- **Encryption by default**: Need encryption at rest without configuration
- **Schema flexibility**: Dynamic schemas without migration complexity
- **Swift-native**: Building Swift applications with idiomatic APIs
- **Predictable performance**: Consistent latency under varying workloads
- **Multi-device sync**: Local-first apps with distributed synchronization
- **Apple Silicon optimization**: Targeting macOS/iOS with best performance

### Performance Advantages

- **10% faster inserts** than SQLite (optimized page writes)
- **33% faster queries** than SQLite (indexed lookups)
- **Sub-millisecond latency** for common operations
- **Linear scaling** with CPU cores

---

## When to Use SQLite

### Use SQLite when:

- **SQL compatibility**: Need SQL queries and complex joins
- **Universal compatibility**: C API works everywhere
- **Battle-tested**: 20+ years of production use
- **Maximum compatibility**: Widest platform support
- **SQL expertise**: Team familiar with SQL

### SQLite Advantages

- **Mature**: 20+ years, billions of deployments
- **SQL standard**: Full SQL compatibility
- **Extensive tooling**: SQLite CLI, GUI tools, libraries
- **Documentation**: Comprehensive, well-documented
- **Community**: Large community, Stack Overflow answers

---

## Detailed Tradeoffs

### Encryption

**BlazeDB:**
- Encryption by default (AES-256-GCM)
- Per-page encryption with unique nonces
- Secure Enclave integration (iOS/macOS)
- Zero configuration required

**SQLite:**
- Encryption via SQLCipher extension
- File-level encryption
- Requires separate library
- Additional configuration

**Verdict**: BlazeDB wins for encryption-by-default use cases.

---

### Schema Management

**BlazeDB:**
- Dynamic schemas, no migrations
- Add fields without schema changes
- Type inference from data
- Zero downtime schema evolution

**SQLite:**
- Static schemas, ALTER TABLE required
- Migrations needed for changes
- Schema versioning required
- Potential downtime for migrations

**Verdict**: BlazeDB wins for rapid iteration and schema flexibility.

---

### Concurrency

**BlazeDB:**
- MVCC snapshot isolation
- No read-write blocking
- Concurrent readers and writers
- Predictable performance

**SQLite:**
- File-level locking
- WAL mode improves concurrency
- Still has write contention
- Variable performance under load

**Verdict**: BlazeDB wins for high-concurrency workloads.

---

### Query Language

**BlazeDB:**
- Fluent Swift API
- Type-safe query builder
- Automatic index selection
- Swift-idiomatic

**SQLite:**
- SQL standard
- Powerful and expressive
- Complex queries possible
- Requires SQL knowledge

**Verdict**: SQLite wins for complex SQL queries. BlazeDB wins for Swift-native APIs.

---

### Performance

**BlazeDB:**
- Predictable latency
- Optimized for Apple Silicon
- Sub-millisecond queries
- Linear scaling

**SQLite:**
- Variable performance
- Optimized for general use
- Fast for simple queries
- Can degrade under load

**Verdict**: BlazeDB wins for predictable performance. SQLite wins for maximum raw speed in some cases.

---

### Platform Support

**BlazeDB:**
- macOS/iOS/Linux (Swift)
- Best on Apple Silicon
- Swift runtime required

**SQLite:**
- Universal (C)
- Works everywhere
- No runtime dependencies

**Verdict**: SQLite wins for maximum compatibility. BlazeDB wins for Swift-native integration.

---

## Migration Path

### From SQLite to BlazeDB

1. Export SQLite data to JSON
2. Import into BlazeDB
3. Update queries to Fluent API
4. Test thoroughly

### From BlazeDB to SQLite

1. Export BlazeDB data to JSON
2. Create SQLite schema
3. Import data
4. Update queries to SQL

---

## Honest Assessment

### BlazeDB Strengths

- Encryption by default
- Schema flexibility
- Swift-native API
- Predictable performance
- Built-in sync

### BlazeDB Weaknesses

- Newer (less battle-tested)
- Smaller community
- No SQL compatibility
- Swift-only

### SQLite Strengths

- Mature and stable
- SQL compatibility
- Universal platform support
- Large community

### SQLite Weaknesses

- No encryption by default
- Schema migrations required
- Variable performance
- No built-in sync

---

## Recommendation

**Choose BlazeDB if:**
- Building Swift applications
- Need encryption by default
- Want schema flexibility
- Prioritize predictable performance
- Need multi-device sync

**Choose SQLite if:**
- Need SQL compatibility
- Require maximum compatibility
- Want battle-tested stability
- Have SQL expertise
- Don't need encryption

**Both are excellent choices** for different use cases. The decision depends on your specific requirements.

---

For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).
For performance benchmarks, see [PERFORMANCE.md](PERFORMANCE.md).

