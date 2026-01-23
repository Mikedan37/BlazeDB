# BlazeShell - CLI Documentation

**Command-line interface for BlazeDB operations.**

---

## **Overview**

BlazeShell is a powerful command-line tool for interacting with BlazeDB databases. It provides a REPL (Read-Eval-Print Loop) interface for database operations.

---

## **Installation**

BlazeShell is included in the BlazeDB package. Build it with:

```bash
swift build -c release
```

Or use it directly from Xcode by running the `BlazeShell` target.

---

## **Usage**

### **Basic Mode:**

```bash
BlazeShell <db-path> <password>
```

**Example:**
```bash
BlazeShell /path/to/database.blazedb mypassword
```

### **Manager Mode:**

```bash
BlazeShell --manager
```

Manages multiple databases with mount/unmount capabilities.

### **Test Database Creation:**

```bash
BlazeShell --create-test
```

Creates a test database with 50 sample records for BlazeDBVisualizer.

---

## **Commands**

### **Basic Operations:**

#### **`fetchAll`**
Fetch all records in the database.

```bash
> fetchAll
BlazeDataRecord(storage: ["id":.uuid(...), "title":.string("Hello")])
BlazeDataRecord(storage: ["id":.uuid(...), "title":.string("World")])
```

#### **`fetch <uuid>`**
Fetch a specific record by UUID.

```bash
> fetch 123e4567-e89b-12d3-a456-426614174000
BlazeDataRecord(storage: ["id":.uuid(123e4567...), "title":.string("Hello")])
```

#### **`insert <json>`**
Insert a new record from JSON.

```bash
> insert {"title": "Hello", "value": 42}
 Inserted with ID: 123e4567-e89b-12d3-a456-426614174000
```

**JSON Format:**
```json
{
 "field1": "string value",
 "field2": 42,
 "field3": 3.14,
 "field4": true,
 "field5": "2024-01-01T00:00:00Z",
 "field6": "uuid-string-here"
}
```

#### **`update <uuid> <json>`**
Update an existing record.

```bash
> update 123e4567-e89b-12d3-a456-426614174000 {"title": "Updated", "value": 100}
 Updated record 123e4567-e89b-12d3-a456-426614174000
```

#### **`delete <uuid>`**
Delete a record permanently.

```bash
> delete 123e4567-e89b-12d3-a456-426614174000
 Deleted record 123e4567-e89b-12d3-a456-426614174000
```

#### **`softDelete <uuid>`**
Soft delete a record (marks as deleted, can be recovered).

```bash
> softDelete 123e4567-e89b-12d3-a456-426614174000
 Soft deleted
```

#### **`exit`**
Exit the shell.

```bash
> exit
```

---

## **Manager Mode Commands**

When running with `--manager` flag:

### **`list`**
List all mounted databases.

```bash
> list
 Database1
 Database2
 Database3
```

### **`mount <name> <path> <password>`**
Mount a database.

```bash
> mount MyDB /path/to/db.blazedb mypassword
 Mounted MyDB
```

### **`use <name>`**
Switch to a different database.

```bash
> use MyDB
 Using MyDB
```

### **`current`**
Show the currently active database.

```bash
> current
 Currently using: MyDB
```

### **`help`**
Show help message.

```bash
> help
 Commands:
- list: Show all mounted DBs
- mount <name> <path> <password>: Mount a DB
- use <name>: Switch current DB
- current: Show currently active DB
- exit: Exit manager
```

---

## **Examples**

### **Example 1: Basic Workflow**

```bash
$ BlazeShell /tmp/test.blazedb password123

 BlazeDB Shell — type 'exit' to quit
> insert {"title": "Hello", "value": 42}
 Inserted with ID: 123e4567-e89b-12d3-a456-426614174000

> fetch 123e4567-e89b-12d3-a456-426614174000
BlazeDataRecord(storage: ["id":.uuid(123e4567...), "title":.string("Hello"), "value":.int(42)])

> update 123e4567-e89b-12d3-a456-426614174000 {"title": "Updated"}
 Updated record 123e4567-e89b-12d3-a456-426614174000

> fetchAll
BlazeDataRecord(storage: ["id":.uuid(123e4567...), "title":.string("Updated"), "value":.int(42)])

> exit
```

### **Example 2: Manager Mode**

```bash
$ BlazeShell --manager

 BlazeDBManager CLI — type 'help' for commands
> mount DB1 /path/to/db1.blazedb pass1
 Mounted DB1

> mount DB2 /path/to/db2.blazedb pass2
 Mounted DB2

> list
 DB1
 DB2

> use DB1
 Using DB1

> current
 Currently using: DB1

> exit
```

### **Example 3: Create Test Database**

```bash
$ BlazeShell --create-test

 Creating test database for BlazeDBVisualizer...
 Adding 50 test records...
 SUCCESS! Created test.blazedb on Desktop!
 Location: /Users/mdanylchuk/Desktop/test.blazedb
 Password: test1234
 Records: 50
```

---

## **Error Handling**

BlazeShell provides clear error messages:

```bash
> fetch invalid-uuid
 Invalid UUID or record not found

> insert invalid json
 Invalid JSON

> update nonexistent-uuid {}
 Invalid UUID
```

---

## **Tips & Tricks**

1. **Use Manager Mode** for working with multiple databases
2. **JSON Format** - Use proper JSON syntax for insert/update
3. **UUID Format** - Use standard UUID format (8-4-4-4-12)
4. **Tab Completion** - Some shells support tab completion
5. **History** - Use up/down arrows to navigate command history

---

## **Limitations**

- **No Query Builder** - Basic operations only (use BlazeDB API for complex queries)
- **No Transactions** - Each command is independent
- **No Async Operations** - All operations are synchronous
- **JSON Only** - Input/output uses JSON format

---

## **Integration with Other Tools**

BlazeShell works great with:
- **BlazeDBVisualizer** - Use `--create-test` to create test data
- **Scripts** - Pipe commands for automation
- **CI/CD** - Use in build scripts for database setup

---

**For advanced operations, use the BlazeDB Swift API directly!**

