# Why Not SQLite?

Honest comparison for choosing between BlazeDB and SQLite as an embedded store.

This page is about **product fit**, not stopwatch marketing. Measured latency and throughput belong in the benchmark docs linked below. Authority for platform tiers: [COMPATIBILITY.md](../COMPATIBILITY.md) and [android-status.md](../android-status.md).

---

## Short answer

**Choose BlazeDB** when you want an encrypted, Swift-native embedded engine with typed records, live queries, local inspection tooling, and native embedding through the C ABI.

**Choose SQLite** when SQL compatibility, ecosystem maturity, third-party tooling, broad language support, or lower insert and cold-open latency matter more.

**Do not choose BlazeDB** because of deferred sync, a standalone server story, or unsupported speed claims.

---

## Platform support

| | BlazeDB |
|--|---------|
| **Platform support** | macOS and Linux **runtime-tested**; Apple platforms (iOS / watchOS / tvOS) **compile-tested**; Android / KMM **experimental** |

Do not treat Android or KMM as the same maturity as macOS/Linux. Details: [COMPATIBILITY.md](../COMPATIBILITY.md), [android-status.md](../android-status.md).

SQLite’s C API remains the broader “runs everywhere” option when you need one binary story across many languages and hosts.

---

## Shipped core vs deferred

These rows describe the **default open-source package**, not roadmap aspirations.

| Capability | BlazeDB today | Notes |
|------------|---------------|-------|
| Encrypted embedded storage | **Shipped** | Public open APIs require a password; pages at rest use **AES-256-GCM** (password-derived 256-bit key via PBKDF2-SHA256 + per-database salt). See [KEY_MANAGEMENT_AND_COMPATIBILITY.md](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md). |
| Typed Swift records (`BlazeStorable`) and raw / byte key-value APIs | **Shipped** | |
| Fluent Swift queries (no SQL string engine) | **Shipped** | |
| Transactional write APIs and WAL-backed recovery | **Shipped** | See durability docs for modes and caveats |
| Live queries and SwiftUI integration | **Shipped (Apple platforms)** | Observation helpers are Apple-oriented; portable observe APIs exist in core |
| Local inspection (`blazedb` CLI/REPL, maintenance tools) | **Shipped** | |
| Documented C ABI (`BlazeDBC`) | **Shipped** | Go via cgo is a recipe, not an official Go module |
| Optional schema validation and migrations | **Shipped (opt-in)** | Flexible by default; **migrations exist** when you opt in — not “schema-less / no migrations” |
| Concurrency model | **Shipped (qualified)** | Single-process embedded engine. Transactions provide consistency. **MVCC / snapshot isolation exists in the codebase but is not the default path** — do not market “MVCC snapshot isolation” as the everyday guarantee. |
| Optional Secure Enclave-assisted key storage | **Platform optional** | Not required for default password-derived encryption |
| Android / KMM consumption | **Experimental** | Engineering validation; not a production SDK claim |
| Multi-device sync / discovery / network server | **Deferred** | Not part of the default OSS package — see [DISTRIBUTED_TRANSPORT_DEFERRED.md](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) |
| SQL string dialect | **Not shipped** | Use SQLite if you need SQL |

---

## When BlazeDB is a good fit

- You are building Swift applications or in-process Swift services (including Vapor embedding) on supported platforms.
- You want encryption at rest without bolting on a separate cipher extension.
- You prefer typed documents and fluent Swift queries over SQL strings.
- You want in-process live queries and Apple-platform SwiftUI observation.
- You need a local CLI/REPL and related inspection tools against the same engine.
- You may embed the engine from C (or languages that call C) through `BlazeDBC`.

---

## When SQLite is the better choice

- You need SQL compatibility, complex joins, or existing SQL tooling and expertise.
- You need the broadest language and platform ecosystem (C API everywhere).
- You care most about raw insert throughput or cold-open latency on an unencrypted store.
- You want decades of production battle history and a large third-party tooling surface.
- You do not need encryption by default (or you already standardize on SQLCipher / similar).

---

## Capability corrections (read these before citing old tables)

Older comparison tables in the repo sometimes claimed mythology. Prefer this page + Compatibility over archive / architecture one-liners.

| Topic | Verified wording |
|-------|------------------|
| **Schema** | Flexible by default; **optional validation and real migration APIs** exist. Not “dynamic, no migrations.” |
| **Concurrency** | Single-process embedded design; multi-process writers unsupported; network filesystems not recommended. Do not claim absolute “MVCC snapshot isolation” as the default product behavior. |
| **Performance** | Cite [Benchmarks](../Benchmarks/README.md) only. Do **not** use “predictable, optimized for Apple Silicon” or free-floating “% faster than SQLite” slogans. |
| **Encryption** | At-rest pages: **AES-256-GCM** with password-derived keys on public open APIs. SQLite encryption remains optional/extension-based (e.g. SQLCipher). |
| **Platforms** | macOS/Linux runtime-tested; other Apple platforms compile-tested; Android/KMM experimental. |
| **Sync** | Deferred from the default OSS package — not a selection reason today. |

### Brief notes on Core Data and Realm

- **Core Data** — Apple-framework ORM/persistence with deep Cocoa integration and its own migration story. Prefer it when you want framework integration over a standalone encrypted document engine.
- **Realm** — Mobile-oriented object database with a long commercial/sync history; **licensing and sync product status have changed over time** — verify current upstream terms rather than citing a one-word “Commercial/MIT” cell. Prefer Realm when you specifically want that ecosystem; prefer BlazeDB when you want MIT-licensed, encryption-default, Swift-native embedded storage without a sync product claim.

This page does **not** maintain a full BlazeDB vs Core Data vs Realm feature matrix. Those one-liners go stale quickly.

---

## Tradeoffs (without invented percentages)

### Encryption

BlazeDB public open APIs require a password; stored pages use **AES-256-GCM**. SQLite encryption is optional and typically comes from an extension (for example SQLCipher). Prefer BlazeDB when encryption-by-default is a primary requirement.

### Query model

BlazeDB uses fluent Swift APIs. SQLite uses SQL. Prefer SQLite for SQL-heavy workloads and existing SQL ecosystems; prefer BlazeDB for Swift-native typed access.

### Schema

BlazeDB models are often flexible day-to-day, with **optional** schema validation and a real migration surface when you need it. SQLite uses explicit SQL schemas and migrations. Neither product is “migration-free” for every evolution story.

### Concurrency and process model

BlazeDB is designed as a **single-process** embedded engine. Multi-process writers are not supported; network filesystems are not recommended. SQLite has a long history of multi-connection patterns (with its own locking and WAL rules). Do not treat BlazeDB as a drop-in multi-writer file server, and do not equate “transactions exist” with “MVCC snapshot isolation is always on.”

### Performance

Do **not** trust free-floating “X% faster than SQLite” slogans on this page or elsewhere in the repo without measured methodology. Do not cite vague “optimized for Apple Silicon” language as evidence.

Authoritative measured comparisons:

- [Docs/Benchmarks/README.md](../Benchmarks/README.md) (how to run and how to read results)
- [Docs/Benchmarks/COMPARISON.md](../Benchmarks/COMPARISON.md) (headline BlazeDB vs SQLite table)
- [Docs/Benchmarks/RESULTS.md](../Benchmarks/RESULTS.md) and [LATENCY.md](../Benchmarks/LATENCY.md)

In current measured comparison runs, SQLite typically wins raw insert throughput and cold-open latency on the unencrypted reference path. BlazeDB’s secure default path includes encryption and different durability costs. Some concurrent-read harness numbers favor BlazeDB; treat those as workload-specific, not a general “faster than SQLite” claim.

### Sync and servers

Distributed sync, discovery, and a networked BlazeDB server are **not** reasons to choose BlazeDB today. They are deferred from the default open-source package. See [DISTRIBUTED_TRANSPORT_DEFERRED.md](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md).

---

## Recommendation

Choose **BlazeDB** for encrypted Swift-native embedded storage, typed records, live queries, local inspection tooling, and native embedding through the C ABI — on platforms whose support tier matches your risk tolerance.

Choose **SQLite** when SQL compatibility, ecosystem maturity, third-party tooling, broad language support, or lower insert and cold-open latency matter more.

Both are strong embedded databases for different jobs. Pick the product whose **shipped** shape matches your constraints.

---

## Related docs

- [Getting Started](README.md)
- [Compatibility](../COMPATIBILITY.md)
- [Android / KMM status](../android-status.md)
- [Architecture](../Architecture/README.md)
- [Key management](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)
- [Durability Mode Support](../Status/DURABILITY_MODE_SUPPORT.md)
- [Benchmarks](../Benchmarks/README.md)
- [Distributed transport deferred](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)
