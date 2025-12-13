# BlazeDB Production Deployment Guide

Complete guide for deploying BlazeDB in production environments.

## Table of Contents

1. [Overview](#overview)
2. [Server Deployment](#server-deployment)
3. [Client Configuration](#client-configuration)
4. [Performance Tuning](#performance-tuning)
5. [Monitoring & Observability](#monitoring--observability)
6. [Backup & Recovery](#backup--recovery)
7. [Security Hardening](#security-hardening)
8. [Scaling](#scaling)
9. [Troubleshooting](#troubleshooting)

## Overview

BlazeDB is production-ready for:

- ✅ Single-device applications
- ✅ Multi-device sync via BlazeServer
- ✅ High-performance local databases
- ✅ Distributed applications

This guide covers deployment best practices for production use.

## Server Deployment

### Docker Deployment

BlazeDB server can be deployed using Docker:

```bash
# Build Docker image
docker build -t blazedb-server .

# Run server
docker run -d \
  -p 8080:8080 \
  -v /data/blazedb:/data \
  -e BLAZEDB_PORT=8080 \
  -e BLAZEDB_DATA_DIR=/data \
  blazedb-server
```

### Docker Compose

Use `docker-compose.yml` for easier management:

```yaml
version: '3.8'
services:
  blazedb:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
    environment:
      - BLAZEDB_PORT=8080
      - BLAZEDB_DATA_DIR=/data
    restart: unless-stopped
```

Start with:
```bash
docker-compose up -d
```

### Systemd Service (Linux)

Create `/etc/systemd/system/blazedb.service`:

```ini
[Unit]
Description=BlazeDB Server
After=network.target

[Service]
Type=simple
User=blazedb
WorkingDirectory=/opt/blazedb
ExecStart=/opt/blazedb/blazedb-server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable blazedb
sudo systemctl start blazedb
```

### Environment Variables

Configure via environment variables:

- `BLAZEDB_PORT` - Server port (default: 8080)
- `BLAZEDB_DATA_DIR` - Database storage directory
- `BLAZEDB_LOG_LEVEL` - Logging level (debug, info, warn, error)
- `BLAZEDB_MAX_CONNECTIONS` - Maximum client connections

## Client Configuration

### Enable Telemetry

For production monitoring:

```swift
let db = try BlazeDBClient(name: "ProductionDB", password: "secure-password")

// Enable telemetry with 1% sampling (low overhead)
db.telemetry.enable(samplingRate: 0.01)
```

### Connection Pooling

For high-traffic applications:

```swift
class DatabasePool {
    private var connections: [BlazeDBClient] = []
    private let lock = NSLock()
    
    func getConnection() -> BlazeDBClient {
        lock.lock()
        defer { lock.unlock() }
        
        if let available = connections.first(where: { !$0.isInUse }) {
            return available
        }
        
        let newConnection = try! BlazeDBClient(
            name: "PooledDB",
            password: "password"
        )
        connections.append(newConnection)
        return newConnection
    }
}
```

### Error Handling

Implement robust error handling:

```swift
func performDatabaseOperation() {
    do {
        try db.insert(record)
    } catch BlazeDBError.transactionFailed(let reason, _) {
        // Handle transaction failure
        logger.error("Transaction failed: \(reason)")
        // Retry logic here
    } catch BlazeDBError.recordNotFound(let id) {
        // Handle missing record
        logger.warn("Record not found: \(id)")
    } catch {
        // Handle other errors
        logger.error("Unexpected error: \(error)")
    }
}
```

## Performance Tuning

### Index Optimization

Create indexes for frequently queried fields:

```swift
// Create indexes after initial data load
try db.collection.createIndex(on: "email")
try db.collection.createIndex(on: "createdAt")
try db.collection.createIndex(on: "status")
```

### Batch Operations

Use batch operations for better performance:

```swift
// Instead of individual inserts
let records = generateRecords()
let ids = try db.insertMany(records)  // Much faster!
```

### MVCC Configuration

For high-concurrency scenarios:

```swift
// Enable MVCC for better concurrency
try db.enableMVCC(
    snapshotIsolation: true,
    versionRetention: .days(7)
)
```

### Garbage Collection

Schedule periodic GC:

```swift
// Run GC daily
Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
    Task {
        try await db.collection.gcManager.runFullGC()
    }
}
```

## Monitoring & Observability

### Health Checks

Implement health check endpoints:

```swift
func healthCheck() -> HealthStatus {
    do {
        let status = try db.getHealthStatus()
        return status
    } catch {
        return HealthStatus(
            isHealthy: false,
            issues: [error.localizedDescription],
            uptime: 0,
            lastBackup: nil,
            databaseSize: 0,
            recordCount: 0
        )
    }
}
```

### Telemetry Monitoring

Query telemetry for insights:

```swift
// Get performance summary
let summary = try await db.telemetry.getSummary()
print("Average query time: \(summary.avgDuration)ms")
print("Success rate: \(summary.successRate)%")

// Find slow operations
let slowOps = try await db.telemetry.getSlowOperations(threshold: 100)
for op in slowOps {
    print("SLOW: \(op.operation) took \(op.duration)ms")
}

// Check for errors
let errors = try await db.telemetry.getErrors(last: 10)
for error in errors {
    print("ERROR: \(error.operation) - \(error.errorMessage)")
}
```

### Monitoring Dashboard

Export monitoring data for dashboards:

```swift
// Export as JSON for Grafana/Prometheus
let monitoringJSON = try db.exportMonitoringJSON()
// Send to monitoring service
```

### Logging

Configure appropriate log levels:

```swift
// Production: info and above
BlazeLogger.configure(level: .info)

// Development: debug
BlazeLogger.configure(level: .debug)
```

## Backup & Recovery

### Automated Backups

Schedule regular backups:

```swift
// Daily backup
Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
    Task {
        let backupURL = backupDirectory
            .appendingPathComponent("backup-\(Date().timeIntervalSince1970).blazedb")
        let stats = try await db.backup(to: backupURL)
        print("Backup complete: \(stats.recordCount) records")
    }
}
```

### Incremental Backups

For large databases:

```swift
// Backup only changes since yesterday
let yesterday = Date().addingTimeInterval(-86400)
let stats = try await db.incrementalBackup(to: incrementalURL, since: yesterday)
```

### Backup Verification

Verify backups are valid:

```swift
let isValid = try await db.verifyBackup(at: backupURL)
if isValid {
    print("✅ Backup is valid")
} else {
    print("❌ Backup verification failed")
}
```

### Recovery Procedure

Restore from backup:

```swift
// Restore from backup
try await db.restore(from: backupURL)
print("✅ Database restored")
```

## Security Hardening

### Password Management

Use strong, unique passwords:

```swift
// Generate secure password
let password = KeyManager.generateSecurePassword(length: 32)

// Store securely (use Keychain on iOS/macOS)
KeychainHelper.store(password: password, for: "blazedb")
```

### Encryption

BlazeDB encrypts all data at rest. Ensure:

- ✅ Strong passwords (32+ characters)
- ✅ Secure password storage (Keychain)
- ✅ Regular password rotation

### Network Security

For server deployments:

- ✅ Use TLS/SSL for connections
- ✅ Implement authentication
- ✅ Use firewall rules
- ✅ Limit network exposure

### Access Control

Implement row-level security:

```swift
// Use RLS policies
try db.addRLSPolicy(
    name: "user_data",
    predicate: { record, user in
        record.storage["userId"]?.uuidValue == user.id
    }
)
```

## Scaling

### Horizontal Scaling

For distributed scenarios:

```swift
// Connect multiple BlazeDB instances
let topology = BlazeTopology()

// Connect to server
try await topology.connectTCP(
    host: "server.example.com",
    port: 8080,
    sharedSecret: "secret"
)

// Connect peer-to-peer
try await topology.connectCrossApp(
    appID: "com.example.app",
    sharedSecret: "secret"
)
```

### Load Balancing

For high-traffic servers:

- Use multiple BlazeDB server instances
- Load balance client connections
- Distribute databases across instances

### Database Sharding

Split large databases:

```swift
// Shard by user ID
let shardID = userID.hashValue % numberOfShards
let db = try BlazeDBClient(
    name: "shard-\(shardID)",
    password: "password"
)
```

## Troubleshooting

### Common Issues

#### High Memory Usage

- Run garbage collection: `try await db.collection.gcManager.runFullGC()`
- Check for memory leaks in your code
- Reduce telemetry sampling rate
- Close unused connections

#### Slow Queries

- Check telemetry for slow operations
- Create indexes on frequently queried fields
- Review query patterns
- Consider query optimization

#### Connection Issues

- Check network connectivity
- Verify firewall rules
- Check server logs
- Test with `telnet` or `nc`

#### Disk Space

- Monitor database size
- Run VACUUM: `try await db.vacuum()`
- Clean up old backups
- Archive old data

### Performance Debugging

Enable detailed logging:

```swift
BlazeLogger.configure(level: .debug)
```

Query telemetry for insights:

```swift
let breakdown = try await db.telemetry.getOperationBreakdown()
// See which operations are slow
```

### Getting Help

1. Check logs for error messages
2. Review telemetry data
3. Test with minimal reproduction case
4. File issue on GitHub with:
   - Error messages
   - Telemetry summary
   - System information
   - Steps to reproduce

## Best Practices

1. **Monitor continuously** - Use telemetry and health checks
2. **Backup regularly** - Automated daily backups
3. **Test recovery** - Verify backups work
4. **Scale proactively** - Monitor growth and plan scaling
5. **Document procedures** - Keep runbooks updated
6. **Security first** - Use strong passwords and encryption
7. **Performance test** - Load test before production
8. **Plan for failures** - Have recovery procedures ready

## Production Checklist

Before going live:

- [ ] Server deployed and tested
- [ ] Backups configured and tested
- [ ] Monitoring enabled
- [ ] Health checks implemented
- [ ] Security hardened (passwords, TLS)
- [ ] Performance tested
- [ ] Error handling implemented
- [ ] Logging configured
- [ ] Recovery procedures documented
- [ ] Team trained on operations

## Next Steps

- Read [Migration Guide](./MIGRATION_GUIDE.md) for migrating existing databases
- Check [API Reference](../API/API_REFERENCE.md) for API details
- Review [Performance Guide](../Performance/PERFORMANCE_GUIDE.md) for optimization
- Explore [Sync Guide](../Sync/SYNC_GUIDE.md) for distributed sync

