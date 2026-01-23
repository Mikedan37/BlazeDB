# BlazeDB CLI Reference

**Command-line tools for BlazeDB database management.**

---

## Commands

### `blazedb doctor`

Health check tool for databases.

**Usage:**
```bash
blazedb doctor <db-path> <password> [--json]
```

**Options:**
- `--json` - Output results as JSON (for scripting)
- `-h, --help` - Show help message

**Examples:**
```bash
# Human-readable output
blazedb doctor /path/to/db.blazedb mypassword

# JSON output (for scripting)
blazedb doctor /path/to/db.blazedb mypassword --json
```

**Exit Codes:**
- `0` - Database is healthy
- `1` - Database health check failed
- `1` - Usage error (missing arguments)

**Output (Human-readable):**
```
 BlazeDB Doctor - Health Check Report

Database: mydb
Path: /path/to/db.blazedb

 File Exists: Database file found
 Encryption Key: Encryption key valid, database opened successfully
 Layout Integrity: Layout metadata readable and valid
 Read/Write Cycle: Read/write cycle successful

 Health Status: OK

 Statistics:
  Records: 1,000
  Pages: 100
  Size: 2.5 MB
  Encrypted: Yes

 Database is healthy
```

**Output (JSON):**
```json
{
  "healthy": true,
  "database": "mydb",
  "path": "/path/to/db.blazedb",
  "checks": [
    {
      "name": "File Exists",
      "passed": true,
      "message": "Database file found"
    },
    {
      "name": "Encryption Key",
      "passed": true,
      "message": "Encryption key valid, database opened successfully"
    }
  ],
  "stats": {
    "pageCount": 100,
    "recordCount": 1000,
    "databaseSize": 2621440,
    "isEncrypted": true,
    "walSize": 512000,
    "cacheHitRate": 0.95,
    "indexCount": 3
  },
  "errors": []
}
```

---

### `blazedb dump`

Export database to dump file.

**Usage:**
```bash
blazedb dump <db-path> <dump-path> <password>
```

**Options:**
- `-h, --help` - Show help message

**Examples:**
```bash
blazedb dump /path/to/db.blazedb /path/to/backup.blazedump mypassword
```

**Exit Codes:**
- `0` - Export successful
- `1` - Export failed
- `1` - Usage error (missing arguments)

**Output:**
```
Exporting database to /path/to/backup.blazedump...
 Export successful
```

---

### `blazedb restore`

Restore database from dump file.

**Usage:**
```bash
blazedb restore <dump-path> <db-path> <password> [--allow-schema-mismatch]
```

**Options:**
- `--allow-schema-mismatch` - Allow restore even if schema versions don't match
- `-h, --help` - Show help message

**Examples:**
```bash
# Normal restore (schema must match)
blazedb restore /path/to/backup.blazedump /path/to/newdb.blazedb mypassword

# Restore with schema mismatch allowed
blazedb restore /path/to/backup.blazedump /path/to/newdb.blazedb mypassword --allow-schema-mismatch
```

**Exit Codes:**
- `0` - Restore successful
- `1` - Restore failed (schema mismatch, non-empty DB, etc.)
- `1` - Usage error (missing arguments)

**Output:**
```
Restoring database from /path/to/backup.blazedump...
 Restore successful
```

**Errors:**
```
 Restore failed: Cannot restore to non-empty database. Database has 10 records.
    Clear database first or use a new database.
```

---

### `blazedb verify`

Verify dump file integrity.

**Usage:**
```bash
blazedb verify <dump-path>
```

**Options:**
- `-h, --help` - Show help message

**Examples:**
```bash
blazedb verify /path/to/backup.blazedump
```

**Exit Codes:**
- `0` - Dump file is valid
- `1` - Verification failed (corrupted, invalid format)
- `1` - Usage error (missing arguments)

**Output:**
```
Verifying dump file /path/to/backup.blazedump...
 Dump file is valid
   Format version: 1.0
   Schema version: 1.0
   Database: mydb
   Exported at: 2025-01-15T10:30:00Z
```

---

### `blazedb info`

Print database information.

**Usage:**
```bash
blazedb info <db-path> <password>
```

**Options:**
- `-h, --help` - Show help message

**Examples:**
```bash
blazedb info /path/to/db.blazedb mypassword
```

**Exit Codes:**
- `0` - Success
- `1` - Failure (cannot open database, invalid password)
- `1` - Usage error (missing arguments)

**Output:**
```
 Database Information

Path: /path/to/db.blazedb
Name: mydb

Size: 2.5 MB
Records: 1,000
Pages: 100
Indexes: 3
WAL Size: 512 KB

Health: OK
  • Database operating normally

Schema Version: 1.0
```

---

## Exit Code Summary

All CLI tools use consistent exit codes:

- `0` - Success
- `1` - Failure (validation error, operation failed, usage error)

**Note:** Exit code `2` is reserved for future use (e.g., usage errors separate from validation errors).

---

## JSON Output

Tools that support `--json` flag:
- `blazedb doctor` - Health check report

JSON output is designed for scripting and automation. All JSON output goes to stdout, errors go to stderr.

---

## Error Messages

All CLI tools provide:
- Clear error messages
- Actionable suggestions (via `` hints)
- Exit codes for scripting

**Example:**
```
 Error: Permission denied for operation: open
    Check file permissions and app sandbox entitlements. On Linux, ensure directory is writable (chmod 755).
```

---

## Scripting Examples

### Check database health in script
```bash
#!/bin/bash
if blazedb doctor /path/to/db.blazedb mypassword --json > /dev/null 2>&1; then
    echo "Database is healthy"
else
    echo "Database health check failed"
    exit 1
fi
```

### Export and verify backup
```bash
#!/bin/bash
blazedb dump /path/to/db.blazedb /tmp/backup.blazedump mypassword || exit 1
blazedb verify /tmp/backup.blazedump || exit 1
echo "Backup created and verified"
```

---

## Platform Support

All CLI tools work on:
- macOS
- Linux

No platform-specific behavior - same commands work everywhere.
