# Comparing embedded storage for Swift apps

Decision guide for **local, in-process** persistence. BlazeDB is one option among several; this page links primary sources and avoids unsupported competitor claims.

**Methodology for numbers:** only cite benchmarks from [Docs/Benchmarks/README.md](../Benchmarks/README.md) with reproducible commands. If a cell says “varies,” run your own workload.

## At a glance

| | **BlazeDB** | **SQLite (+ GRDB)** | **SwiftData / Core Data** | **Realm (MongoDB)** |
|---|-------------|---------------------|---------------------------|---------------------|
| **Data model** | Typed documents + raw records | SQL tables | Apple object graphs | Object models |
| **Query language** | Swift fluent / namespace APIs | SQL | Framework-specific | Realm APIs |
| **Encryption at rest** | Required on public open APIs (AES-GCM) | Optional (e.g. SQLCipher via GRDB) | Platform/keychain patterns | Supported in product |
| **Process model** | One writer per file; macOS/Linux often use a **daemon + queue**; iOS in-app | Multi-connection patterns (SQLite rules) | App-scoped | App-scoped; sync product separate |
| **Live UI updates** | In-process observation; SwiftUI on Apple | GRDB observation / manual | First-class on Apple | First-class |
| **Linux / server Swift** | Runtime CI on Linux | GRDB + SQLite common | Apple-centric | Mobile-focused |
| **Maturity / history** | Young OSS engine | Decades (SQLite) | Apple stack | Long mobile history |
| **Typical reason to choose** | Swift-native encrypted documents + CLI | SQL + ecosystem | Stay inside Apple frameworks | Existing Realm investment |

BlazeDB detail: [WHY_NOT_SQLITE.md](WHY_NOT_SQLITE.md) · [SUPPORT_AND_LIMITATIONS.md](../Support/SUPPORT_AND_LIMITATIONS.md).

## BlazeDB positioning (verified)

**Choose BlazeDB when:**

- **One owning process** per database file on a **local filesystem** (direct multi-process file access is not supported; daemon-mediated access is fine on macOS/Linux)
- **Encryption by default** on the database file matters
- You want **Swift `Codable` / namespace queries**, not SQL
- **Operator tooling** (`blazedb` REPL/CLI) on real files is valuable

**Choose something else when:**

- You need **SQL**, heavy analytics, or maximum insert throughput on an unencrypted path → SQLite/GRDB
- You want **Apple-only** persistence with minimal custom engine → SwiftData/Core Data
- You need **multi-device sync as a product** → dedicated sync stacks (BlazeDB default OSS package **defers** distributed sync)
- You need **Kotlin-first Android** → not BlazeDB’s published SDK path (experimental bridge only)

## Name disambiguation

**BlazeDB** (this repository) is a **Swift embedded document database**. Use “Swift embedded” in titles when posting externally.

## Competitor doc pointers (primary sources)

| Project | Start here |
|---------|------------|
| GRDB | https://github.com/groue/GRDB.swift |
| SQLite | https://sqlite.org |
| SwiftData | Apple documentation |
| Realm | https://www.mongodb.com/docs/realm |

BlazeDB does not maintain third-party feature matrices; verify competitor capabilities in their docs before shipping comparisons in your own materials.

## Benchmarks

Headline BlazeDB vs SQLite tables: [COMPARISON.md](../Benchmarks/COMPARISON.md). Read [HONEST_PERFORMANCE.md](../Benchmarks/HONEST_PERFORMANCE.md) before quoting any latency figure.
