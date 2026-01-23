# Production Deployment Guide

**Everything you need to deploy BlazeDB in production**

---

## Production Checklist

### 1. Initialize Database

```swift
let db = try BlazeDBClient(
 name: "MyApp",
 fileURL: productionURL,
 password: strongPassword // Use secure password!
)
```

**Security:**
- Use strong password (16+ characters)
- Store password in Keychain (not hardcoded)
- All data encrypted automatically (AES-256)

---

### 2. Enable Monitoring

```swift
// Enable telemetry (automatic performance tracking)
db.telemetry.enable(samplingRate: 0.01) // 1% sampling

// Why: Find production issues, track performance, monitor errors
// Cost: < 1% overhead
```

---

### 3. Configure Garbage Collection

```swift
// Enable auto-VACUUM (prevent database bloat)
db.enableAutoVacuum(
 wasteThreshold: 0.30, // VACUUM at 30% waste
 checkInterval: 3600 // Check every hour
)

// Why: Keeps database small, prevents mysterious growth
// Cost: Negligible
```

---

### 4. Define Schema (If Needed)

```swift
let schema = DatabaseSchema(fields: [
 FieldSchema(name: "title", type:.string, required: true),
 FieldSchema(name: "status", type:.string, required: true, validator: { field in
 guard case.string(let value) = field else { return false }
 return ["open", "in-progress", "closed"].contains(value)
 })
])

db.defineSchema(schema)

// Why: Prevents invalid data, enforces business rules
// When: Production apps, multiple developers
```

---

### 5. Create Indexes

```swift
// Index frequently queried fields
try db.collection.createIndex(on: "status")
try db.collection.createCompoundIndex(on: ["status", "priority"])

// Enable search if needed
try db.collection.enableSearch(on: ["title", "description"])

// Why: 10-100x faster queries
// Critical: Always index before production!
```

---

### 6. Set Up Monitoring

```swift
// Periodic health checks
Task.detached {
 while appIsRunning {
 try await Task.sleep(for:.hours(1))

 // Check GC health
 let gcHealth = try await db.checkGCHealth()
 if gcHealth.status ==.critical {
 BlazeLogger.error("Database needs VACUUM: \(gcHealth.issues)")
 try await db.vacuum()
 }

 // Check performance
 let telemetry = try await db.telemetry.getSummary()
 if telemetry.avgDuration > 50 {
 BlazeLogger.warn("Performance degraded: \(telemetry.avgDuration)ms avg")
 }

 if telemetry.successRate < 95 {
 BlazeLogger.warn("High error rate: \(100 - telemetry.successRate)%")
 }
 }
}
```

---

### 7. Implement Backups

```swift
// Daily backups
Task.detached {
 while appIsRunning {
 try await Task.sleep(for:.hours(24))

 let backupURL = getBackupURL(for: Date())
 let stats = try await db.backup(to: backupURL)

 BlazeLogger.info("Backup created: \(stats.recordCount) records, \(stats.fileSize / 1024 / 1024) MB")

 // Optional: Upload to cloud storage
 // uploadToCloud(backupURL)
 }
}
```

---

### 8. Error Handling

```swift
// Global error handler
func handleDatabaseError(_ error: Error) {
 switch error {
 case BlazeDBError.recordNotFound:
 // User-facing: "Item not found"
 // Log: Track frequency

 case BlazeDBError.diskFull:
 // Critical: Alert user, clear cache
 // Log: Send alert to dev team

 case BlazeDBError.databaseLocked:
 // Retry with backoff

 default:
 // Log unexpected errors
 BlazeLogger.error("Unexpected DB error: \(error)")
 }
}
```

---

## Performance Optimization

### 1. Use Batch Operations

```swift
// Slow (100 individual operations)
for record in records {
 try db.insert(record)
}

// Fast (1 batch operation, 3-5x faster)
try db.insertMany(records)
```

---

### 2. Create Indexes

```swift
// Find slow queries
let slowOps = try await db.telemetry.getSlowOperations(threshold: 50)

// Add indexes for slow query fields
for op in slowOps {
 // If querying on "status" is slow:
 try db.collection.createIndex(on: "status")
}
```

---

### 3. Use Query Cache

```swift
// Enable caching
db.enableQueryCache(ttl: 300) // 5 minutes

// Repeated queries are cached automatically
let results1 = try db.query()...execute() // Queries DB
let results2 = try db.query()...execute() // From cache
```

---

### 4. Pagination

```swift
// Don't do this
let allRecords = try db.fetchAll() // Loads everything!

// Do this
let page = try db.fetchPage(offset: pageNumber * 20, limit: 20)
```

---

## Monitoring Dashboard

```swift
struct MonitoringDashboard: View {
 let database: BlazeDBClient
 @State private var telemetrySummary: TelemetrySummary?
 @State private var gcHealth: GCHealthReport?

 var body: some View {
 VStack {
 // Performance
 if let telemetry = telemetrySummary {
 VStack {
 Text(" Performance")
 Text("Ops: \(telemetry.totalOperations)")
 Text("Avg: \(String(format: "%.2f", telemetry.avgDuration))ms")
.foregroundColor(telemetry.avgDuration < 10?.green:.orange)
 Text("Success: \(String(format: "%.1f", telemetry.successRate))%")
.foregroundColor(telemetry.successRate > 95?.green:.red)
 }
 }

 // GC Health
 if let health = gcHealth {
 VStack {
 Text(" Database Health")
 Text("\(health.status.emoji) \(health.status.rawValue)")
 Text("Waste: \(String(format: "%.1f", health.wastePercentage))%")
 }
 }

 Button("Refresh") {
 Task {
 telemetrySummary = try? await database.telemetry.getSummary()
 gcHealth = try? await database.checkGCHealth()
 }
 }
 }
.task {
 telemetrySummary = try? await database.telemetry.getSummary()
 gcHealth = try? await database.checkGCHealth()
 }
 }
}
```

---

## Alerts & Notifications

```swift
// Send alerts when issues detected
func checkDatabaseHealth() async {
 // Performance alerts
 let telemetry = try? await db.telemetry.getSummary()
 if let telemetry = telemetry, telemetry.avgDuration > 50 {
 sendAlert("Database slow: \(telemetry.avgDuration)ms avg")
 }

 // Error alerts
 if let telemetry = telemetry, telemetry.successRate < 95 {
 sendAlert("High error rate: \(100 - telemetry.successRate)%")
 }

 // GC alerts
 let health = try? await db.checkGCHealth()
 if health?.status ==.critical {
 sendAlert("Database needs maintenance")
 }
}
```

---

## Production Best Practices

**DO:**
- Enable telemetry (monitor performance)
- Enable auto-VACUUM (prevent bloat)
- Create indexes (critical for performance)
- Use batch operations (3-5x faster)
- Implement backups (daily recommended)
- Monitor health (hourly checks)
- Handle errors gracefully

**DON'T:**
- Use fetchAll() on large datasets
- Skip indexes (queries will be slow)
- Ignore telemetry warnings
- Let database bloat (enable auto-VACUUM)
- Hardcode passwords (use Keychain)

---

## Deployment Configuration

```swift
// Production configuration
var config = GCConfiguration()
config.enablePageReuse = true
config.autoVacuumEnabled = true
config.autoVacuumWasteThreshold = 0.30
config.vacuumBeforeBackup = true

db.configureGC(config)

var telemetryConfig = TelemetryConfiguration()
telemetryConfig.samplingRate = 0.01 // 1%
telemetryConfig.retentionDays = 30
telemetryConfig.autoCleanup = true

db.telemetry.configure(telemetryConfig)
```

---

## Troubleshooting Production Issues

### Issue: "App is slow"

```swift
// 1. Check telemetry
let summary = try await db.telemetry.getSummary()
print("Average: \(summary.avgDuration)ms")

// 2. Find slow operations
let slowOps = try await db.telemetry.getSlowOperations(threshold: 50)
for op in slowOps {
 print("SLOW: \(op.operation) - \(op.duration)ms")
}

// 3. Add indexes or optimize queries
```

---

### Issue: "Database file is huge"

```swift
// 1. Check storage stats
let stats = try await db.getStorageStats()
print("Waste: \(stats.wastePercentage)%")

// 2. If > 30% waste, run VACUUM
if stats.wastePercentage > 30 {
 try await db.vacuum()
}

// 3. Enable auto-VACUUM for future
db.enableAutoVacuum(wasteThreshold: 0.30, checkInterval: 3600)
```

---

### Issue: "Frequent errors"

```swift
// 1. Check errors
let errors = try await db.telemetry.getErrors()

// 2. Group by error type
var errorCounts: [String: Int] = [:]
for error in errors {
 errorCounts[error.errorMessage, default: 0] += 1
}

// 3. Fix most common errors
for (message, count) in errorCounts.sorted(by: { $0.value > $1.value }) {
 print("\(count)x: \(message)")
}
```

---

**BlazeDB is production-ready!**
**Deploy with confidence!**

