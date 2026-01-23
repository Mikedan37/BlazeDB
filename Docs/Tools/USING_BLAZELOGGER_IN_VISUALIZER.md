# Using BlazeLogger in BlazeDBVisualizer

## **YES! BlazeLogger is Available Everywhere**

Since BlazeDBVisualizer depends on BlazeDB, you have full access to BlazeLogger!

---

## **How to Use BlazeLogger**

### **Option 1: Import and Use Directly**

```swift
import BlazeDB

// In any Visualizer file:
BlazeLogger.info("User unlocked database: \(dbName)")
BlazeLogger.warn("Large database detected: \(size) MB")
BlazeLogger.error("Failed to connect", context: ["path": dbPath])
```

### **Option 2: Enable Stack Traces**

```swift
// At app launch (BlazeDBVisualizerApp.swift)
init() {
 BlazeLogger.captureStackTraces = true // Enable for debugging
}

// Then when logging:
BlazeLogger.error("Critical error", includeStack: true)
```

### **Option 3: Custom Log Filtering**

```swift
// Only show warnings and errors (hide info/debug)
BlazeLogger.logLevel =.warn

// Show everything (including debug)
BlazeLogger.logLevel =.debug
```

---

## **Where to Add Logging**

### **1. EditingService (Already Useful!)**

```swift
func insertRecord(_ data: BlazeDataRecord) async throws -> UUID {
 BlazeLogger.debug("Inserting record", context: [
 "fields": data.storage.keys.joined(separator: ", ")
 ])

 let id = try db.insert(data)

 BlazeLogger.info("Record inserted", context: [
 "id": id.uuidString,
 "fieldCount": String(data.storage.count)
 ])

 return id
}
```

### **2. MonitoringService (Track Performance)**

```swift
func startMonitoring(...) async throws {
 BlazeLogger.info("Starting monitoring", context: [
 "dbPath": dbPath,
 "interval": String(interval)
 ])

 //... monitoring code...

 BlazeLogger.debug("Snapshot collected", context: [
 "records": String(snapshot.storage.totalRecords),
 "health": snapshot.health.status
 ])
}
```

### **3. BackupRestoreService (Track Operations)**

```swift
func createBackup(dbPath: String, name: String?) throws -> URL {
 BlazeLogger.info("Creating backup", context: [
 "dbPath": dbPath,
 "name": name?? "auto"
 ])

 let backupURL = //... create backup...

 BlazeLogger.info("Backup created", context: [
 "size": String(fileSize),
 "location": backupURL.path
 ])

 return backupURL
}
```

### **4. Password Authentication**

```swift
func unlock(password: String) throws {
 BlazeLogger.debug("Attempting database unlock")

 do {
 let db = try BlazeDBClient(...)
 BlazeLogger.info("Database unlocked successfully")
 } catch {
 BlazeLogger.error("Unlock failed", context: [
 "error": error.localizedDescription
 ])
 throw error
 }
}
```

---

## **Viewing Logs**

### **Option 1: Xcode Console**

```
When running in Xcode:
- View → Debug Area → Show Debug Area (⌘⇧Y)
- All BlazeLogger output appears here
```

### **Option 2: Console.app**

```
1. Open /Applications/Utilities/Console.app
2. Search for "BlazeDBVisualizer"
3. See all logs with timestamps
```

### **Option 3: Log to File**

```swift
// Create custom logger that writes to file
class FileLogger {
 static func log(_ message: String) {
 let logFile = URL(fileURLWithPath: "/tmp/blazedb_visualizer.log")
 let timestamp = Date().ISO8601Format()
 let line = "[\(timestamp)] \(message)\n"

 if let data = line.data(using:.utf8) {
 if FileManager.default.fileExists(atPath: logFile.path) {
 let fileHandle = try? FileHandle(forWritingTo: logFile)
 fileHandle?.seekToEndOfFile()
 fileHandle?.write(data)
 try? fileHandle?.close()
 } else {
 try? data.write(to: logFile)
 }
 }
 }
}

// Then in your code:
BlazeLogger.info("Something happened")
FileLogger.log("Something happened") // Also write to file
```

---

## **Debugging Editing Operations**

### **Add logging to EditingService:**

```swift
// In EditingService.swift

func updateField(id: UUID, field: String, value: BlazeDocumentField) async throws {
 BlazeLogger.debug("Updating field", context: [
 "recordID": id.uuidString.prefix(8),
 "field": field,
 "newValue": String(describing: value)
 ])

 guard let db = db else { throw EditingError.notConnected }

 isProcessing = true
 defer { isProcessing = false }

 if settings.autoBackupBeforeEdit && undoStack.isEmpty {
 BlazeLogger.info("Creating safety backup before first edit")
 try await createSafetyBackup()
 }

 let (oldRecord, newRecord, operation) = try await Task.detached {
 BlazeLogger.debug("Fetching old record for undo")
 guard let oldRecord = try db.fetch(id: id) else {
 BlazeLogger.error("Record not found for update", context: ["id": id.uuidString])
 throw EditingError.recordNotFound(id: id)
 }

 try db.updateFields(id: id, fields: [field: value])
 try db.persist()

 BlazeLogger.debug("Field updated in database")

 guard let newRecord = try db.fetch(id: id) else {
 throw EditingError.recordNotFound(id: id)
 }

 let operation = EditOperation.update(id: id, oldData: oldRecord, newData: newRecord)
 return (oldRecord, newRecord, operation)
 }.value

 addToUndoStack(operation)
 BlazeLogger.info("Update complete, undo available for 30s")

 if settings.enableAuditLogging {
 auditService.log(operation:.update, recordID: id, oldValue: oldRecord.storage, newValue: newRecord.storage)
 }

 lastOperation = "Field '\(field)' updated"
}
```

---

## **Example: Add Logging to Visualizer**

### **1. At App Launch:**

```swift
// BlazeDBVisualizerApp.swift

@main
struct BlazeDBVisualizerApp: App {
 init() {
 // Configure BlazeLogger for visualizer
 BlazeLogger.captureStackTraces = false // Off for performance
 BlazeLogger.logLevel =.info // Show info, warn, error

 BlazeLogger.info("BlazeDBVisualizer starting", context: [
 "version": "2.0",
 "user": NSUserName()
 ])
 }

 var body: some Scene {
 MenuBarExtra("BlazeDB", systemImage: "database") {
 MenuExtraView()
 }
.menuBarExtraStyle(.window)
 }
}
```

### **2. Track User Actions:**

```swift
// In EditableDataViewerView:

func updateRecordField(id: UUID, field: String, value: BlazeDocumentField) {
 BlazeLogger.info("User editing field", context: [
 "field": field,
 "recordID": id.uuidString.prefix(8)
 ])

 Task {
 do {
 try await editingService.updateField(id: id, field: field, value: value)

 BlazeLogger.info("Field updated successfully")

 loadRecords()
 showUndoToast = true

 try? await Task.sleep(nanoseconds: 30_000_000_000)
 showUndoToast = false
 } catch {
 BlazeLogger.error("Failed to update field", context: [
 "error": error.localizedDescription
 ])
 errorMessage = error.localizedDescription
 }
 }
}
```

### **3. Monitor Performance:**

```swift
// Track slow operations
let start = Date()

try await editingService.bulkUpdateField(ids: ids, field: field, value: value)

let duration = Date().timeIntervalSince(start)

if duration > 1.0 {
 BlazeLogger.warn("Slow bulk update", context: [
 "duration": String(format: "%.2fs", duration),
 "recordCount": String(ids.count)
 ])
}
```

---

## **UI ALIGNMENT FIX**

I fixed the row height issue! Changed:

```swift
 Fixed height: 22 points for both Text and TextField
 Removed.roundedBorder (adds extra height)
 Used.plain style with custom background
 Consistent padding on both modes
```

**Result:**
- Row height stays consistent when editing
- All rows perfectly aligned
- Blue highlight shows which field is editing
- Smooth transition between display/edit mode

---

## **Debugging Tips with BlazeLogger**

### **Find Performance Bottlenecks:**

```swift
BlazeLogger.info("Bulk update starting", context: [
 "recordCount": String(ids.count)
])

let start = Date()
try await editingService.bulkUpdateField(...)
let duration = Date().timeIntervalSince(start)

BlazeLogger.info("Bulk update complete", context: [
 "duration": String(format: "%.3fs", duration),
 "recordsPerSecond": String(format: "%.0f", Double(ids.count) / duration)
])
```

### **Track Undo Stack:**

```swift
// After adding to undo stack:
BlazeLogger.debug("Undo stack updated", context: [
 "stackSize": String(editingService.undoStack.count),
 "operation": operation.description
])
```

### **Monitor Audit Log:**

```swift
auditService.log(operation:.insert, recordID: id)

BlazeLogger.debug("Audit entry created", context: [
 "totalEntries": String(auditService.entries.count),
 "operation": "insert"
])
```

---

## **Example Log Output**

```
[BlazeDB:INFO] BlazeDBVisualizer starting (version: 2.0, user: mdanylchuk)
[BlazeDB:INFO] User unlocked database (name: test, encrypted: true)
[BlazeDB:INFO] Starting monitoring (interval: 5.0s)
[BlazeDB:DEBUG] Snapshot collected (records: 50, health: healthy)
[BlazeDB:INFO] User editing field (field: age, recordID: abc12345)
[BlazeDB:DEBUG] Updating field (recordID: abc12345, field: age, newValue: int(26))
[BlazeDB:DEBUG] Fetching old record for undo
[BlazeDB:DEBUG] Field updated in database
[BlazeDB:INFO] Update complete, undo available for 30s
[BlazeDB:DEBUG] Undo stack updated (stackSize: 3, operation: Update record)
[BlazeDB:DEBUG] Audit entry created (totalEntries: 15, operation: update)
[BlazeDB:INFO] Field updated successfully
```

---

## **READY TO TEST:**

```bash
# Build and run
⌘B → Build
⌘R → Run

# Then:
1. Enable editing mode
2. Double-click a field (e.g., "age")
3. Edit it (e.g., 25 → 26)
4. Press Enter
5. Row stays perfectly aligned!
6. Blue highlight shows editing
7. Undo toast appears
8. Check Xcode Console for BlazeLogger output!
```

---

## **Pro Tips:**

### **Performance Logging:**

```swift
// Measure operation time
func bulkUpdateField(...) async throws {
 let start = Date()

 //... operation...

 let duration = Date().timeIntervalSince(start)

 BlazeLogger.info("Bulk update", context: [
 "records": String(ids.count),
 "duration": String(format: "%.3fs", duration),
 "throughput": String(format: "%.0f records/s", Double(ids.count) / duration)
 ])
}
```

### **Error Context:**

```swift
catch {
 BlazeLogger.error("Operation failed", context: [
 "operation": "bulkUpdate",
 "field": field,
 "recordCount": String(ids.count),
 "error": error.localizedDescription
 ], includeStack: true) // Include stack trace!
}
```

### **User Action Tracking:**

```swift
// Track what users do
BlazeLogger.info("User action", context: [
 "action": "bulkDelete",
 "recordCount": String(selectedRecords.count),
 "hasBackup": String(backupCreated)
])
```

---

## **WHAT YOU CAN LOG:**

```
 User authentication (unlock/lock)
 Database connections
 CRUD operations
 Bulk operations
 Undo operations
 Backup/restore
 Export operations
 Query execution
 Performance metrics
 Error conditions
 User actions
```

---

## **THIS IS POWERFUL!**

**With BlazeLogger in the visualizer:**
- Debug user issues
- Track performance
- Monitor operations
- Audit trail (separate from AuditLogService)
- Stack traces when needed
- Zero overhead when disabled

---

# **ROW ALIGNMENT FIXED! BLAZELOGGER READY! **

**Test it now - double-click a field and watch it edit smoothly!**

