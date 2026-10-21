# BlazeDB

BlazeDB keeps your app’s data in an encrypted file on the device and lets you read and write it with Swift types—no separate database server to install or host.

The library runs **inside your app process**. You open a database with a password, save `Codable` models, and load or filter them with Swift code. Data is stored in a `.blazedb` file (and related sidecar files) at a path you choose or at the platform default location.

[![CI](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Mikedan37/BlazeDB/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v2.8.2-green.svg)](RELEASE.md)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)

**Release:** [v2.8.2](RELEASE.md) · [Changelog](CHANGELOG.md) · [License](LICENSE) (MIT)

---

## What you can use it for

These are **example shapes** of apps BlazeDB can back—not a list of shipped products:

- **Notes or journals** — save many text entries, list them, filter by title or tag fields you store on the model.
- **Task or checklist apps** — persist items with done/open state and query the open ones.
- **Offline catalogs** — hold product or inventory records locally when the network is unreliable.

BlazeDB helps when you want **searchable, structured storage** in Swift without hand-rolling JSON files, plist bookkeeping, or your own encryption layer. It is **not** SQL, and it does not replace a server-side database if you need multi-user cloud storage out of the box.

---

<a id="start-here-new-users"></a>
<a id="try-blazedb-from-this-repo"></a>

## Try it

Pick **one** path: run the sample from a clone, or add the package to an app you already have.

### A. From a clone (fastest smoke test)

Requires [Swift 6.0+](https://www.swift.org/install/) (matches `swift-tools-version:6.0` in `Package.swift`).

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

You should see **`Success (persisted across reopen)`** when inserts survive closing and reopening the database file.

### B. Add BlazeDB to your Swift package or Xcode app

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.2")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

In Xcode: **File → Add Package Dependencies** and paste the same URL. Import **`BlazeDB`** in source files.

### Minimal Swift example (default API)

This uses the recommended entry point: `BlazeDB.open`, then `put`, `get`, and `query`. Each model type gets a short **namespace** derived from its struct name (`Note` → `"note"`). Use that string in `query("note")` and in keys like `"note:<uuid>"`.

```swift
import BlazeDB

struct Note: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var body: String
}

let db = try BlazeDB.open(name: "demo", password: "Choose-a-strong-password")
let note = Note(title: "Groceries", body: "Milk and eggs")
try db.put(note)

let loaded: Note? = try db.get("note:\(note.id.uuidString)")
let matches: [Note] = try db.query("note")
    .where("title", equals: "Groceries")
    .all()
```

Opening with `name:` creates or opens `demo.blazedb` under the [platform default folder](Docs/GettingStarted/DEFAULT_STORAGE_PATHS.md). A password is **required**; it is used to derive encryption keys for the file ([key handling](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)).

CI checks this pattern with `swift run ReadmeSamples --only start-here` after you build once from a clone.

For update, delete, reopen, and file locations, continue in **[Getting Started](Docs/GettingStarted/README.md)**.

---

<a id="is-it-a-fit"></a>
<a id="do-not-use-blazedb-when-you-need"></a>
<a id="hard-nos"></a>

## Is it a fit?

| Good fit | Often better elsewhere |
|----------|-------------------------|
| Swift app, local encrypted storage, document-style records | SQL, spreadsheets, or heavy ad hoc reporting → SQLite or GRDB |
| One app (or one **owning** process) writes the database file | Many uncoordinated writers on the same file path |
| In-app filtering via BlazeDB’s query builders | A built-in network database or multi-device sync in the default OSS package |

**Process ownership:** One running process should **own** writes to a given `.blazedb` path (exclusive file lock). Other clients can talk to **your** macOS/Linux service or worker that holds the file open and serializes writes; on iOS, keep the database in the app. Details: [Why single writer](Docs/Guarantees/WHY_SINGLE_WRITER.md).

**Not in the default package:** Device sync / distributed transport ([deferred](Docs/Status/DISTRIBUTED_TRANSPORT_DEFERRED.md)), SQL, a hosted BlazeDB cloud product, or official Go/Rust/Python SDKs (a [C ABI](Docs/Architecture/C_ABI_BYTE_KV.md) exists for embedders who accept that contract).

**Platforms:** macOS and Linux are **runtime-tested** in CI; iOS, watchOS, tvOS, and visionOS are declared and compile-tested; Android/KMM is **experimental** ([Android status](Docs/android-status.md)). See [Compatibility](Docs/COMPATIBILITY.md).

**Maturity:** Open source with active development; see [support matrix](Docs/Support/SUPPORT_AND_LIMITATIONS.md) for scope and security wording (encryption protects **data at rest** in the file—it does not by itself secure your whole app).

Factual comparison with SQLite-style stores: [Why not SQLite?](Docs/GettingStarted/WHY_NOT_SQLITE.md) · [Compare embedded options](Docs/GettingStarted/COMPARE_EMBEDDED_SWIFT_STORAGE.md).

---

## What it provides

- **Embedded** — No separate database daemon; your app links the library.
- **Typed records** — Save and load Swift structs that conform to `BlazeStorable` (`Codable` + `id`).
- **Encrypted files** — Page encryption by default; password required at open ([details and limits](Docs/Status/KEY_MANAGEMENT_AND_COMPATIBILITY.md)).
- **Grouped writes** — Transaction APIs to commit or roll back related changes ([developer guide](Docs/DEVELOPER_GUIDE.md#transactions)).
- **Live lists in SwiftUI** — Query wrappers can refresh when stored data changes; you wire the client into the environment ([SwiftUI patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md)).
- **Crash recovery** — Committed work is designed to survive app crashes via a on-disk recovery log ([durability behavior](Docs/Status/DURABILITY_MODE_SUPPORT.md)).
- **CLI** — The `blazedb` tool inspects and edits `.blazedb` files locally ([CLI docs](Docs/Tools/BLAZESHELL_DOCUMENTATION.md)); not a network server.

Alternative APIs (direct `insert`/`fetch`, raw records, manual mapping) remain available for advanced use; they are documented outside the beginner path.

---

## Next steps

| If you want to… | Start here |
|-----------------|------------|
| Complete the first-run tutorial | [Getting Started](Docs/GettingStarted/README.md) |
| Use BlazeDB in SwiftUI | [SwiftUI database patterns](Docs/GettingStarted/SWIFTUI_DATABASE_PATTERNS.md) |
| Look up types and methods | [API reference](Docs/API/API_REFERENCE.md) |
| Check platforms and CI depth | [Compatibility](Docs/COMPATIBILITY.md) · [Support & limitations](Docs/Support/SUPPORT_AND_LIMITATIONS.md) |
| Understand storage, encryption, guarantees | [Architecture](Docs/Architecture/README.md) · [Guarantees](Docs/Guarantees/WHY_SINGLE_WRITER.md) |
| Contribute (start small) | [Starter tasks](Docs/Contributing/STARTER_TASKS.md) · [Contributing](CONTRIBUTING.md) |

Documentation index: [Docs/README.md](Docs/README.md). CLI, Android/KMM, C ABI, benchmarks, and contributor CI details live there—not on this page.

---

## Project status

| | |
|--|--|
| Release | [v2.8.2](RELEASE.md) · [Changelog](CHANGELOG.md) |
| Roadmap | [ROADMAP.md](ROADMAP.md) (directional) |
| Security reports | [SECURITY.md](SECURITY.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |
