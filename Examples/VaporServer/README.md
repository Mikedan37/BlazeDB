# Vapor Server Example with BlazeDB

This example demonstrates how to embed BlazeDB in a Vapor server application with proper lifecycle management.

## Support Boundaries

- **Supported:** Embedded BlazeDB usage on Linux/macOS in a single process.
- **Reference Integration:** This Vapor example demonstrates integration wiring and lifecycle patterns.
- **Non-goal:** This repository does not ship an official BlazeDB hosted/server runtime product.

Use this as a starting point for your own app package; do not treat it as a versioned server product surface.

## Features

- Database opened on server startup
- Database closed gracefully on shutdown
- Health endpoint: `GET /db/health`
- Stats endpoint: `GET /db/stats`
- Dump endpoint: `POST /db/dump` (DEBUG only)
- Example CRUD endpoints: `GET /users`, `POST /users`

## Setup (In Your Own Vapor App Package)

1. Add dependencies to your app's `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.7")
]
```

2. Create executable target:
```swift
.executableTarget(
    name: "VaporServer",
    dependencies: [
        "BlazeDB",
        .product(name: "Vapor", package: "vapor")
    ],
    path: "Examples/VaporServer"
)
```

3. Build and run:
```bash
swift build --target VaporServer
.build/debug/VaporServer
```

## Environment Variables

- `DB_PASSWORD`: Database encryption password (defaults to "default-password-change-in-production")

## Endpoints

### Health Check
```bash
curl http://localhost:8080/db/health
```

### Statistics
```bash
curl http://localhost:8080/db/stats
```

### Create User
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com"}'
```

### List Users
```bash
curl http://localhost:8080/users
```

## Important Notes

1. **Single Process Only**: BlazeDB is single-process. Do not run multiple Vapor instances sharing the same database file.

2. **Graceful Shutdown**: The `DatabaseLifecycle` handler ensures the database is closed properly on server shutdown.

3. **Signal Handling**: Vapor handles SIGTERM/SIGINT automatically. The lifecycle handler ensures database cleanup.

4. **Production**: Remove the `/db/dump` endpoint in production. It's only enabled in DEBUG builds.

5. **Reference Integration**: Keep ownership/migration expectations in your app repo. This example can evolve faster than the core BlazeDB API surface.

## Deployment

See `Docs/Guides/RUNNING_IN_SERVERS.md` for:
- Systemd configuration
- Docker deployment
- Signal handling guidance
- Multi-instance considerations
