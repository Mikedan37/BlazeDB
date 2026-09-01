# Getting started with BlazeDBClient

Use this path for command-line tools, services, unit tests, and any Swift code that is not using the SwiftUI property wrappers.

## 1. Add the package

In Xcode: **File → Add Package Dependencies** and use:

```swift
.package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.8.1")
```

Depend on the **BlazeDB** product (it re-exports ``BlazeDBCore``).

## 2. Define a model

Conform your type to ``BlazeStorable``. It must be `Codable`, `Identifiable`, and use `UUID` as the id type.

```swift
import BlazeDB

struct Job: BlazeStorable {
    var id: UUID = UUID()
    var title: String
    var company: String
    var status: String
}
```

BlazeDB stores each model under a namespace derived from the type name (for example `job` for `Job`). Query and get APIs use that namespace in keys and filters.

## 3. Open the database

**SwiftUI apps:** use one app-owned holder (see <doc:SwiftUIIntegration>). Example:

```swift
public final class SeekerDatabase {
    public static let shared: SeekerDatabase = {
        do {
            return try SeekerDatabase()
        } catch {
            fatalError("Failed to initialize Seeker database: \(error)")
        }
    }()

    public let db: BlazeDBClient

    public init() throws {
        let password = loadPasswordFromKeychain()
        self.db = try BlazeDBClient.open(named: "seeker", password: password)
    }
}
```

**CLI, tests, and services** can open inline:

```swift
let db = try BlazeDBClient.open(named: "seeker", password: "YourSecurePassword123!")
```

For a specific file URL:

```swift
let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo.blazedb")
let db = try BlazeDBClient.open(at: url, password: "YourSecurePassword123!")
```

The ``BlazeDB`` facade mirrors the same calls:

```swift
let db = try BlazeDB.open(name: "seeker", password: "YourSecurePassword123!")
```

Passwords must meet the library minimum length (8 characters). Store production passwords in Keychain, not source.

## 4. Create, read, update

**Insert or update** with `put(_:)`:

```swift
var job = Job(title: "iOS Engineer", company: "Acme", status: "applied")
try db.put(job)

job.status = "interview"
try db.put(job)
```

**Read one row** with `get(_:)`. Pass a key as `namespace:UUID`:

```swift
let loaded: Job? = try db.get("job:\(job.id.uuidString)")
```

**Query many rows** with `query(_:)`:

```swift
let openJobs: [Job] = try db.query("job")
    .where("status", equals: "applied")
    .all()
```

## 5. Close when you are done

Hold ``BlazeDBClient`` for the lifetime of your process or app session. When you no longer need the database, release the client so files can be closed cleanly (for example set your holder to `nil` or let it deinitialize).

## When to use BlazeDBClient directly

Use ``BlazeDBClient`` when you need APIs beyond `put` / `get` / `query`, such as raw ``BlazeDataRecord`` access, transactions, schema tools, or advanced query builders. The open helpers on ``BlazeDBClient`` mirror ``BlazeDB/open(name:password:)`` and ``BlazeDB/open(at:password:)``.

For SwiftUI screens, see <doc:SwiftUIIntegration> instead of wiring ``BlazeDBClient`` through every initializer.
