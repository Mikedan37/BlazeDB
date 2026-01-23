# Running BlazeDB in Servers

**BlazeDB as embedded database in server applications (Vapor, etc.)**

---

## What BlazeDB Is

**Embedded database:** Single-process, single-writer database.

**Use cases:**
- Vapor server with embedded database
- Background daemons
- CLI tools with persistent storage
- Single-process applications

---

## What BlazeDB Is NOT

**NOT a multi-tenant database:**
- Cannot share database files between multiple processes
- Cannot have multiple writers to the same database
- Cannot cluster or replicate at the storage level

**NOT a replacement for PostgreSQL/MySQL:**
- No SQL compatibility
- No multi-process concurrent access
- No built-in replication

---

## Vapor Example

**Single-process Vapor server with embedded BlazeDB:**

```swift
import Vapor
import BlazeDB

// Configure Vapor app
let app = Application(.development)

// Open database (one per server process)
let db = try BlazeDB.openForDaemon(
    name: "myserver",
    password: ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? "default-password"
)

// Routes
app.get("users") { req async throws -> [User] in
    let records = try db.query()
        .where("active", equals: .bool(true))
        .execute()
        .records
    
    return records.map { User(from: $0) }
}

app.post("users") { req async throws -> User in
    let userData = try req.content.decode(UserData.self)
    let record = BlazeDataRecord([
        "name": .string(userData.name),
        "email": .string(userData.email),
        "active": .bool(true)
    ])
    
    let id = try db.insert(record)
    return User(id: id, from: record)
}

// Start server
try app.run()
```

**Important:** One database instance per server process. Do not share database files.

---

## Lifecycle Guidance

### Server Startup

```swift
// 1. Open database
let db = try BlazeDB.openForDaemon(name: "server", password: "secure-password")

// 2. Validate schema (if using schema versioning)
struct ServerSchema: BlazeSchema {
    static var version = SchemaVersion(major: 1, minor: 0)
}
try db.validateSchemaVersion(expectedVersion: ServerSchema.version)

// 3. Run migrations if needed
let plan = try db.planMigration(
    targetVersion: ServerSchema.version,
    migrations: [MyMigration()]
)
if !plan.migrations.isEmpty {
    try db.executeMigration(plan: plan, dryRun: false)
}

// 4. Check health
let health = try db.health()
if health.status == .error {
    // Handle error state
}
```

### Server Shutdown

```swift
// Database automatically flushes on deinit
// No explicit cleanup needed for normal shutdown

// For graceful shutdown:
defer {
    // BlazeDBClient deinit handles cleanup
    // WAL is flushed, pages are written
}
```

---

## Non-Goals

**What BlazeDB does NOT support:**

1. **Multi-process access:** Cannot share database files between processes
2. **Clustering:** No built-in replication or clustering
3. **Shared writers:** Only one writer per database file
4. **Multi-tenant:** Each tenant needs separate database file

**If you need these:** Use PostgreSQL, MySQL, or another multi-process database.

---

## Best Practices

### Database Per Process

```swift
// CORRECT: One database per server process
class Server {
    let db: BlazeDBClient
    
    init() throws {
        self.db = try BlazeDB.openForDaemon(name: "server", password: "pass")
    }
}
```

### Error Handling

```swift
// Handle database errors explicitly
do {
    try db.insert(record)
} catch BlazeDBError.databaseLocked {
    // Database is locked (shouldn't happen in single-process)
    // Log and return error to client
    throw Abort(.serviceUnavailable, reason: "Database temporarily unavailable")
} catch {
    // Other errors
    throw Abort(.internalServerError, reason: "Database error: \(error)")
}
```

### Health Monitoring

```swift
// Periodic health checks
func checkHealth() {
    do {
        let health = try db.health()
        if health.status == .error {
            // Alert monitoring system
        }
    } catch {
        // Database error - alert
    }
}

// Run health check every 60 seconds
Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
    checkHealth()
}
```

---

## Limitations

**Single-process only:**
- Cannot share database between multiple server instances
- Cannot use BlazeDB for multi-instance deployments
- Each server instance needs its own database

**Workaround for multi-instance:**
- Use external database (PostgreSQL, MySQL) for shared state
- Use BlazeDB for per-instance caching or local storage
- Use BlazeDB's distributed sync (when available) for replication

---

## Summary

**BlazeDB in servers:**
- Embedded database for single-process applications
- Suitable for Vapor servers, daemons, CLI tools
- NOT suitable for multi-process or multi-tenant scenarios

**When to use:**
- Single-process server applications
- Background services
- CLI tools with persistent storage

**When NOT to use:**
- Multi-process deployments
- Shared database files
- Multi-tenant applications

---

**Remember:** BlazeDB is an embedded database, not a server database. Use it where you'd use SQLite, not where you'd use PostgreSQL.
