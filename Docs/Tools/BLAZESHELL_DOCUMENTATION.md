# blazedb CLI (formerly BlazeShell)

**Command-line interface for BlazeDB.** The SwiftPM product is **`blazedb`** (target `BlazedbCLI`); shared implementation lives in the **`BlazeCLICore`** module under [`BlazeShell/`](../../BlazeShell/).

---

## **Overview**

`blazedb` provides a terminal-first workflow: on macOS and Linux, run it with no arguments to open an **interactive picker** (recents, default-folder discovery, optional home scan, metadata and chips), then enter your password and use the **REPL** for CRUD. Other platforms can still open a database by path and password.

---

## **Installation**

`blazedb` is included in the BlazeDB package. Build or run:

```bash
swift build -c release --product blazedb
swift run blazedb --help
```

The CLI is built via SwiftPM. The Xcode project no longer ships a separate shell scheme; use **`swift run blazedb`** from a package checkout.

---

## **Usage**

### **Interactive picker (no arguments)**

```bash
swift run blazedb
```

- **Recent** databases (MRU after successful opens) appear first, then **Found** (non-recursive `*.blazedb` under the default Application Support / Linux data directory).
- **Arrow keys** move selection, **Enter** opens, **q** quits, **s** starts an **opt-in home-directory scan** (incremental; status shows `Scanning home… (N found)`).
- **`--scan-home`** starts the home scan immediately when the picker opens.
- Rows show **size and last-modified** plus chips **`[recent]`**, **`[bookmarked]`**, **`[locked]`** (password still required).

### **Direct open (path + password)**

```bash
swift run blazedb /path/to/database.blazedb mypassword
```

Prefer the environment variable so the password does not appear in `ps`:

```bash
export BLAZEDB_PASSWORD='yourpassword'
swift run blazedb /path/to/database.blazedb
```

### **Manager mode**

```bash
swift run blazedb --manager
```

### **Bookmarks (picker chips)**

```bash
swift run blazedb bookmark add /path/to/db.blazedb
swift run blazedb bookmark remove /path/to/db.blazedb
```

Registry (recents + bookmarks) is stored next to other app data: `cli-registry.json` under the directory returned by `PathResolver.defaultDatabaseDirectory()`.

### **Test database creation**

```bash
swift run blazedb --create-test
```

Creates a test database with 50 sample records for BlazeDBVisualizer.

### **Backup helpers**

```bash
swift run blazedb restore-backup <destination-path>
swift run blazedb show-backup
```

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
$ swift run blazedb /tmp/test.blazedb password123

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
$ swift run blazedb --manager

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
$ swift run blazedb --create-test

 Creating test database for BlazeDBVisualizer...
 Adding 50 test records...
 SUCCESS! Created test.blazedb on Desktop!
 Location: /var/folders/.../blazedb-test-visualizer.blazedb
 Password: test1234
 Records: 50
```

---

## **Error Handling**

`blazedb` provides clear error messages:

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

`blazedb` works great with:
- **BlazeDBVisualizer** - Use `--create-test` to create test data
- **Scripts** - Pipe commands for automation
- **CI/CD** - Use in build scripts for database setup

---

## **Manual verification (picker TUI)**

After changing terminal UI code, smoke-test on macOS:

- **Terminal.app** and **iTerm2**: `swift run blazedb` — arrows move highlight, Enter prompts for password (or uses `BLAZEDB_PASSWORD`), `q` exits, `s` starts home scan and list grows with a live count.
- **Resize**: v1 does not handle `SIGWINCH`; quick resize may misdraw until next key or scan tick.

---

**For advanced operations, use the BlazeDB Swift API directly!**

