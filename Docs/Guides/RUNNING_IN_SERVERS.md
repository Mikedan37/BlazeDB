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

**Single-Writer Enforcement:**
BlazeDB uses OS-level file locking (`flock`) to prevent multiple processes from opening the same database.
If you attempt to open a database that is already open in another process, you will receive a `BlazeDBError.databaseLocked` error with clear guidance on how to resolve it.

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
// Explicit close is recommended for deterministic shutdown
defer {
    try? db.close()  // Idempotent - safe to call multiple times
}

// Database automatically flushes on deinit if close() not called
// But explicit close() is recommended for server applications
```

**Signal Handling (SIGTERM/SIGINT):**
```swift
// Handle graceful shutdown
signal(SIGTERM) { _ in
    // Close database explicitly
    try? db.close()
    exit(0)
}

signal(SIGINT) { _ in
    try? db.close()
    exit(0)
}
```

**Note:** Signal handlers should be minimal. For complex cleanup, use `atexit()` or Vapor's lifecycle hooks instead.

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

## Systemd Configuration

**Example systemd service file for BlazeDB-based daemon:**

```ini
[Unit]
Description=My BlazeDB Server
After=network.target

[Service]
Type=simple
User=blazedb
WorkingDirectory=/opt/blazedb-server
ExecStart=/usr/local/bin/my-server
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Environment variables
Environment=DB_PASSWORD=secure-password-from-secrets

[Install]
WantedBy=multi-user.target
```

**Important:** Ensure only one instance runs per database file. Systemd will prevent multiple instances if configured correctly.

---

## Docker Deployment

**Single-container deployment:**

```dockerfile
FROM swift:6.0

WORKDIR /app
COPY . .
RUN swift build -c release

# Database volume (one per container)
VOLUME ["/data"]

ENV DB_PATH=/data/app.blazedb
ENV DB_PASSWORD=secure-password

CMD [".build/release/MyServer"]
```

**Warning:** Do NOT share the database volume between multiple containers. Each container must have its own database file.

**Multi-container deployment:** Use external database (PostgreSQL, MySQL) for shared state. Use BlazeDB only for per-container local storage.

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

**Safety guarantees:**
- OS-level file locking prevents double-open
- Explicit `close()` for deterministic shutdown
- Format version validation prevents incompatible opens
- Resource limit warnings prevent silent failures

---

**Remember:** BlazeDB is an embedded database, not a server database. Use it where you'd use SQLite, not where you'd use PostgreSQL.
