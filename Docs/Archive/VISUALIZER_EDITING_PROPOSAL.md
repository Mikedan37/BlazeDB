# BlazeDB Visualizer - Data Editing Feature Proposal

## **Overview**

Transform BlazeDBVisualizer from read-only viewer to **FULL database management tool** with editing capabilities.

---

## **Proposed Features**

### **1. Inline Field Editing**

**UI/UX:**
```
Current:

 name  age  email 
 Alice  25  alice@...  [Read-only]


Proposed:

 name  age  email 
 [Alice]  [25]  alice@...  [Editable on double-click]

```

**Implementation:**
```swift
struct EditableRecordRow: View {
 @State private var editingField: String? = nil
 @State private var editValue: String = ""
 @State private var showConfirmation = false

 var body: some View {
 HStack {
 ForEach(record.fields) { field in
 if editingField == field.name {
 // Edit mode
 TextField(field.name, text: $editValue)
.textFieldStyle(.roundedBorder)
.onSubmit {
 saveEdit(field: field.name, value: editValue)
 }
.onExitCommand {
 cancelEdit()
 }
 } else {
 // Display mode
 Text(field.value)
.onTapGesture(count: 2) {
 startEditing(field: field.name)
 }
 }
 }
 }
 }

 func saveEdit(field: String, value: String) {
 // 1. Validate data type
 // 2. Update database
 // 3. Refresh view
 // 4. Show success toast
 }
}
```

**Safety Rails:**
- Type validation before save
- "Undo" button (5 sec window)
- Automatic backup before first edit
- Confirmation for bulk edits
- Read-only mode toggle (default OFF)

---

### **2. New Record Creation**

**UI/UX:**
```
[+ Add Record] button in toolbar

Opens modal:

 Create New Record 
 
 Field Name: [________] 
 Field Type: [String ] 
 Value: [________] 
 
 [+ Add Field] 
 
 Fields: 
 • name (string): "Alice" 
 • age (int): 25 
 • email (string): "alice@..." 
 
 [Cancel] [Create Record] 

```

**Implementation:**
```swift
struct NewRecordSheet: View {
 @State private var fields: [(String, BlazeValue)] = []
 @State private var fieldName = ""
 @State private var fieldType: DataType =.string
 @State private var fieldValue = ""

 var body: some View {
 Form {
 Section("Add Field") {
 TextField("Field Name", text: $fieldName)
 Picker("Type", selection: $fieldType) {
 Text("String").tag(DataType.string)
 Text("Int").tag(DataType.int)
 Text("Bool").tag(DataType.bool)
 Text("Date").tag(DataType.date)
 }
 TextField("Value", text: $fieldValue)

 Button("Add Field") {
 addField()
 }
 }

 Section("Fields") {
 ForEach(fields, id: \.0) { field in
 HStack {
 Text(field.0)
 Spacer()
 Text(field.1.description)
 }
 }
 }
 }
.toolbar {
 Button("Create") {
 createRecord()
 }
 }
 }

 func createRecord() {
 // 1. Validate all fields
 // 2. Create BlazeDataRecord
 // 3. Insert into database
 // 4. Refresh view
 // 5. Show success toast
 }
}
```

---

### **3. Record Deletion**

**UI/UX:**
```
Select row(s) → Press Delete key

Shows confirmation:

  Delete 3 Records? 
 
 This action cannot be undone. 
 
 Create backup first 
 (Recommended) 
 
 [Cancel] [Delete] 

```

**Safety Rails:**
- Confirmation dialog (always)
- Automatic backup option (recommended)
- "Undo" within 5 seconds
- Bulk delete limit (max 1,000 at once)
- Progress bar for large deletions

---

### **4. Bulk Operations**

**UI/UX:**
```
Select multiple rows → Right-click

Context menu:

 Edit Selected (5 records) 
  Delete Selected 
 Export Selected 
 Copy Selected 


If "Edit Selected":

 Bulk Edit 5 Records 
 
 Field: [status ] 
 Action: [Set to ] 
 Value: [active] 
 
 Preview: 
 • Record 1: status = "active" 
 • Record 2: status = "active" 
 • Record 3: status = "active" 
... 
 
 [Cancel] [Apply to 5] 

```

---

## **Security Features**

### **Built-in Safety Rails:**

1. **Audit Logging**
 ```swift
 struct EditAuditLog: Codable {
 let timestamp: Date
 let user: String // macOS username
 let operation: String // "update", "delete", "insert"
 let recordID: UUID
 let oldValue: [String: BlazeValue]?
 let newValue: [String: BlazeValue]?
 let success: Bool
 }
 ```

2. **Automatic Backups**
 - Before first edit of session → auto-backup
 - Before bulk operations → mandatory backup
 - Rolling backups (keep last 10)

3. **Read-Only Mode Toggle**
 ```swift
 @AppStorage("editingEnabled") var editingEnabled = false

 // User must explicitly enable editing
 Toggle("Enable Data Editing", isOn: $editingEnabled)
.help(" Allows modifying database records")
 ```

4. **Undo System**
 ```swift
 struct UndoManager {
 private var undoStack: [(operation: String, restore: () throws -> Void)] = []

 func recordUndo(operation: String, restore: @escaping () throws -> Void) {
 undoStack.append((operation, restore))

 // Auto-expire after 30 seconds
 DispatchQueue.main.asyncAfter(deadline:.now() + 30) {
 undoStack.removeAll { $0.operation == operation }
 }
 }

 func undo() throws {
 guard let last = undoStack.popLast() else { return }
 try last.restore()
 }
 }
 ```

5. **Confirmation Dialogs**
 - Edit → No confirmation (can undo)
 - Delete single → Confirmation
 - Delete multiple → Confirmation + backup option
 - Bulk edit → Preview + confirmation

6. **Type Validation**
 ```swift
 func validate(value: String, as type: DataType) -> Result<BlazeValue, ValidationError> {
 switch type {
 case.int:
 guard let int = Int(value) else {
 return.failure(.invalidInt("'\(value)' is not a valid integer"))
 }
 return.success(.int(int))

 case.bool:
 let normalized = value.lowercased()
 guard ["true", "false", "1", "0"].contains(normalized) else {
 return.failure(.invalidBool("'\(value)' is not a valid boolean"))
 }
 return.success(.bool(normalized == "true" || normalized == "1"))

 case.date:
 guard let date = ISO8601DateFormatter().date(from: value) else {
 return.failure(.invalidDate("'\(value)' is not a valid ISO8601 date"))
 }
 return.success(.date(date))

 case.string:
 return.success(.string(value))
 }
 }
 ```

---

## **Testing Plan**

### **New Tests Required:**

```swift
// EditingTests.swift (50+ tests)
 testInlineEditString
 testInlineEditInt
 testInlineEditWithInvalidType
 testEditCreatesBackup
 testEditCanUndo
 testEditAuditLogging
 testEditRequiresConfirmation
 testReadOnlyModeBlocksEdits

// DeletionTests.swift (30+ tests)
 testDeleteSingleRecord
 testDeleteMultipleRecords
 testDeleteCreatesBackup
 testDeleteCanUndo
 testDeleteAuditLogging
 testDeleteWithConfirmation

// BulkOperationTests.swift (40+ tests)
 testBulkUpdateValidation
 testBulkUpdateProgress
 testBulkDeleteLimit
 testBulkOperationRollback

// SafetyTests.swift (25+ tests)
 testAutoBackupBeforeEdit
 testUndoExpiration
 testReadOnlyModeEnforcement
 testAuditLogIntegrity

TOTAL: ~145 new tests
```

---

## **Performance Considerations**

### **Optimization Strategies:**

1. **Batch Updates**
 ```swift
 // Instead of:
 for record in selectedRecords {
 try db.update(record)
 try db.persist()
 }

 // Do this:
 try db.beginTransaction()
 for record in selectedRecords {
 try db.update(record)
 }
 try db.commitTransaction()
 ```

2. **Background Processing**
 ```swift
 Task.detached(priority:.userInitiated) {
 let result = try await performBulkOperation()

 await MainActor.run {
 updateUI(result)
 }
 }
 ```

3. **Progress Reporting**
 ```swift
 @Published var bulkProgress: Double = 0.0

 for (index, record) in records.enumerated() {
 try processRecord(record)
 bulkProgress = Double(index + 1) / Double(records.count)
 }
 ```

---

## **UI Enhancements**

### **Visual Indicators:**

1. **Editing Mode Badge**
 ```
 EDITING MODE ACTIVE
 ```

2. **Unsaved Changes Warning**
 ```
  You have unsaved changes. Save or discard?
 ```

3. **Undo Toast**
 ```
 Record updated [Undo] [×]
 ```

4. **Progress Bar (Bulk Ops)**
 ```
 Updating 1,000 records...  82%
 ```

---

## **Implementation Roadmap**

### **Phase 1: Inline Editing (Week 1)**
- Double-click to edit
- Type validation
- Auto-backup on first edit
- Undo support (30 sec window)
- 50 tests

### **Phase 2: Record Creation (Week 2)**
- "Add Record" modal
- Field type picker
- Validation before insert
- 30 tests

### **Phase 3: Deletion (Week 3)**
- Single record delete
- Bulk delete
- Confirmation dialogs
- Automatic backup option
- 30 tests

### **Phase 4: Bulk Operations (Week 4)**
- Bulk update
- Progress reporting
- Preview before apply
- 40 tests

### **Phase 5: Audit & Security (Week 5)**
- Audit logging
- Read-only mode toggle
- Enhanced confirmations
- 25 tests

**TOTAL: 5 weeks, 175+ new tests**

---

## **Result**

After implementation, BlazeDBVisualizer would be:

```
 COMPLETE DATABASE MANAGEMENT TOOL
 Comparable to TablePlus/Sequel Pro/DataGrip
 Safe editing with undo/backup
 Audit logging for compliance
 471 total tests (296 + 175)
 Production-ready for teams
```

---

## **Configuration Options**

```swift
struct EditingSettings: Codable {
 var editingEnabled: Bool = false
 var autoBackupBeforeEdit: Bool = true
 var undoTimeout: TimeInterval = 30
 var bulkOperationLimit: Int = 1000
 var requireConfirmationForDelete: Bool = true
 var auditLogEnabled: Bool = true
 var readOnlyMode: Bool = true // Default to read-only!
}
```

---

## **Conclusion**

**Should we add editing?**

# **YES! **

**With proper safety rails:**
- Automatic backups
- Undo system
- Audit logging
- Type validation
- Confirmation dialogs
- Read-only mode toggle

**This would make BlazeDBVisualizer a LEGENDARY tool! **

