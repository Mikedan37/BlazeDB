# Getting Started on Linux

**Swift:** 6.0+ (matches `swift-tools-version:6.0` in `Package.swift`)  
**CI:** Linux **Tier0** runs on every PR; **Tier1** runs on nightly confidence ([CI_AND_TEST_TIERS.md](../Testing/CI_AND_TEST_TIERS.md)).

This guide uses the same public API as the README and [HelloBlazeDB](../../Examples/HelloBlazeDB/main.swift).

---

## Install (Swift Package Manager)

In your app's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.2")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Pin matches the current release tag `v2.8.2` ([RELEASE.md](../../RELEASE.md)).

---

## Verify from a clone (recommended first run)

```bash
git clone https://github.com/Mikedan37/BlazeDB.git
cd BlazeDB
swift run HelloBlazeDB
```

**Expected output (abridged):** lines for `Opened database`, `Inserted sample bugs`, `Open bugs: 2`, and `Success (persisted across reopen)`.

**Common failures:**

| Symptom | Action |
|---------|--------|
| `swift: command not found` | Install Swift 6 from [swift.org](https://www.swift.org/install/) |
| Build errors in `swift-crypto` | Ensure Swift 6.0+; on aarch64 use a supported Linux triple |
| `Error: … password` | Example uses `DemoPass123!`; custom opens must meet password policy |

---

## Minimal app snippet (same as Getting Started)

```swift
import BlazeDB

struct Bug: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var status: String
}

let dbURL = URL(fileURLWithPath: "/tmp/demo.blazedb")
let db = try BlazeDB.open(at: dbURL, password: "DemoPass123!")
defer { try? db.close() }

try db.put(Bug(title: "First on Linux", status: "open"))
let open: [Bug] = try db.query("bug").where("status", equals: "open").all()
print(open.count)
```

Typed IDs use `namespace:UUID` keys internally (`bug:<uuid>`).

---

## Default storage paths

Linux default app data directory: `~/.local/share/blazedb/` when using `BlazeDB.open(name:password:)`. See [DEFAULT_STORAGE_PATHS.md](DEFAULT_STORAGE_PATHS.md).

---

## CLI on Linux

Build and run the REPL against a file (no Xcode required):

```bash
swift build --product blazedb
.build/debug/blazedb --help
.build/debug/blazedb /path/to/db.blazedb
```

Doctor, dump, and info ship as separate executables (`BlazeDoctor`, `BlazeDump`, `BlazeInfo`). See [Tools README](../Tools/README.md).

---

## Linux core subset

Some advanced features are gated when building with `BLAZEDB_LINUX_CORE` (spatial, vector, certain RLS-adjacent tooling). Consumer apps using the **`BlazeDB`** product follow the normal package graph; see [COMPATIBILITY.md](../COMPATIBILITY.md) for the feature matrix.

---

## Next steps

- [Getting Started README](README.md)
- [Support and limitations](../Support/SUPPORT_AND_LIMITATIONS.md)
- [HOW_TO_USE_BLAZEDB.md](HOW_TO_USE_BLAZEDB.md)
