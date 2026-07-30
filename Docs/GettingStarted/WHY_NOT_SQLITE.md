# Why Not SQLite?

Honest fit comparison for choosing between BlazeDB and SQLite as an embedded store.

This page is about **product fit**, not stopwatch marketing. Measured latency and throughput live in the [benchmark docs](../Benchmarks/README.md). Authority for platform tiers: [COMPATIBILITY.md](../COMPATIBILITY.md) and [android-status.md](../android-status.md).

---

## Short answer

**Choose BlazeDB** when you want an encrypted, Swift-native embedded engine with typed records, live queries, local inspection tooling, and native embedding through the C ABI.

**Choose SQLite** when SQL compatibility, ecosystem maturity, third-party tooling, broad language support, or lower insert and cold-open latency matter more.

**Do not choose BlazeDB** because of deferred sync, a standalone server story, or unsupported speed claims.

---

## Where SQLite wins

Stated early and plainly, because it is the question most readers arrive with.

In current measured comparison runs, **SQLite typically wins raw insert throughput and cold-open latency** on its unencrypted reference path. BlazeDB's default path includes encryption and carries different durability costs, and that difference is real rather than a tuning gap waiting to be closed.

Some concurrent-read harness numbers favor BlazeDB. Treat those as workload-specific and not as a general "faster than SQLite" claim.

Measured comparisons, with methodology:

- [Benchmarks README](../Benchmarks/README.md) for how to run and how to read results
- [COMPARISON.md](../Benchmarks/COMPARISON.md) for the headline BlazeDB vs SQLite table
- [RESULTS.md](../Benchmarks/RESULTS.md) and [LATENCY.md](../Benchmarks/LATENCY.md)

If a number appears anywhere without a link to methodology, it is not a supported claim.

---

## Fit comparison

| Axis | BlazeDB | SQLite |
|------|---------|--------|
| Query model | Fluent Swift APIs, typed documents | SQL, complex joins, decades of SQL expertise |
| Encryption at rest | Required on public open APIs, AES-256-GCM | Optional, usually via an extension such as SQLCipher |
| Schema | Flexible by default, optional validation and real migration APIs | Explicit SQL schemas and migrations |
| Process model | Single-process file ownership; multi-process writers not supported; network filesystems not recommended | Long history of multi-connection patterns with its own locking and WAL rules |
| Live queries | In-process observation, SwiftUI integration on Apple platforms | Not built in |
| Language reach | Swift natively, plus any language that can call the C ABI | C API essentially everywhere |
| Insert throughput and cold open | Slower on the encrypted default path | Faster on the unencrypted reference path |
| Ecosystem and tooling | Local CLI and REPL against the same engine | Very large third-party tooling surface |
| Production history | Young | Decades of battle history |

Neither product is migration-free for every schema evolution story.

---

## Shipped core vs deferred

These rows describe the **default open-source package**, not roadmap aspirations.

| Capability | BlazeDB today | Notes |
|------------|---------------|-------|
| Encrypted embedded storage | **Shipped** | Public open APIs require a password; pages at rest use **AES-256-GCM** (password-derived 256-bit key via PBKDF2-SHA256 plus per-database salt). See [KEY_MANAGEMENT_AND_COMPATIBILITY.md](../Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md). |
| Typed Swift records (`BlazeStorable`) and raw / byte key-value APIs | **Shipped** | |
| Fluent Swift queries (no SQL string engine) | **Shipped** | |
| Transactional write APIs and WAL-backed recovery | **Shipped** | See [durability docs](../Status/DURABILITY_MODE_SUPPORT.md) for modes and caveats |
| Live queries and SwiftUI integration | **Shipped (Apple platforms)** | Observation helpers are Apple-oriented; portable observe APIs exist in core |
| Local inspection (`blazedb` CLI and REPL, maintenance tools) | **Shipped** | |
| Documented C ABI (`BlazeDBC`) | **Shipped** | Go via cgo is a recipe, not an official Go module |
| Optional schema validation and migrations | **Shipped (opt-in)** | Flexible by default; migrations exist when you opt in. This is not "schema-less, no migrations" |
| Concurrency model | **Shipped (qualified)** | Single-process embedded engine; transactions provide consistency. **Multi-process writers are not supported and network filesystems are not recommended.** MVCC and snapshot isolation exist in the codebase but are **not the default path**, so snapshot isolation is not the everyday guarantee. BlazeDB is not a drop-in multi-writer file server |
| Optional Secure Enclave-assisted key storage | **Platform optional** | Not required for default password-derived encryption |
| Android / KMM consumption | **CI-validated (experimental packaging)** | PR-gate cross-compile plus emulator smoke; not a published SDK; not Linux host Tier0 |
| Multi-device sync, discovery, network server | **Deferred** | Not part of the default OSS package. See [DISTRIBUTED_TRANSPORT_DEFERRED.md](../Status/DISTRIBUTED_TRANSPORT_DEFERRED.md) |
| SQL string dialect | **Not shipped** | Use SQLite if you need SQL |

---

## Platform support

BlazeDB is **runtime-tested** on macOS and Linux (host engine tests). Other Apple platforms (iOS, watchOS, tvOS, visionOS) are **compile-tested**. Android and KMM are **CI-validated** through a PR-gate cross-compile and a KMM emulator smoke, with **experimental packaging**.

Android and KMM are not equivalent in maturity to macOS and Linux host Tier0, and they are also not unsupported. Details: [COMPATIBILITY.md](../COMPATIBILITY.md) and [android-status.md](../android-status.md).

SQLite's C API remains the broader "runs everywhere" option when you need one binary story across many languages and hosts.

---

## Choose BlazeDB when

- You are building Swift applications or in-process Swift services, including Vapor embedding, on supported platforms.
- You want encryption at rest without bolting on a separate cipher extension.
- You prefer typed documents and fluent Swift queries over SQL strings.
- You want in-process live queries and Apple-platform SwiftUI observation.
- You need a local CLI and REPL against the same engine for inspection.
- You may embed the engine from C, or from a language that calls C, through `BlazeDBC`.

## Choose SQLite when

- You need SQL compatibility, complex joins, or existing SQL tooling and expertise.
- You need the broadest language and platform ecosystem.
- You care most about raw insert throughput or cold-open latency on an unencrypted store.
- You want decades of production history and a large third-party tooling surface.
- You do not need encryption by default, or you already standardize on SQLCipher or similar.

Multi-device sync, discovery, and a networked BlazeDB server are **not** reasons to choose BlazeDB today. They are deferred from the default open-source package.

---

## Core Data and Realm

- **Core Data**: Apple-framework ORM and persistence layer with deep Cocoa integration and its own migration story. Prefer it when you want framework integration over a standalone encrypted document engine.
- **Realm**: mobile-oriented object database with a long commercial and sync history. Licensing and sync product status have changed over time, so verify current upstream terms rather than trusting a one-word summary. Prefer Realm when you specifically want that ecosystem; prefer BlazeDB when you want MIT-licensed, encryption-default, Swift-native embedded storage without a sync product claim.

This page does not maintain a full BlazeDB vs Core Data vs Realm feature matrix. Those one-liners go stale quickly.

---

## Note for maintainers and doc authors

This page is the authority for BlazeDB vs SQLite positioning. Prefer it and [COMPATIBILITY.md](../COMPATIBILITY.md) over older architecture or archive one-liners, several of which overstate the product.

When citing capabilities elsewhere in the repo:

- Do not describe the schema story as "dynamic, no migrations". Optional validation and real migration APIs exist.
- Do not present MVCC or snapshot isolation as the default product behavior. It exists in the codebase but is not the default path.
- Do not use free-floating "percent faster than SQLite" figures, or "predictable, optimized for Apple Silicon" language, as evidence. Cite [Benchmarks](../Benchmarks/README.md) with methodology or say nothing.
- Do not describe Android or KMM as shipped, and do not describe them as unsupported. The accurate word is experimental.
- Do not cite deferred sync as a current selection reason.

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
