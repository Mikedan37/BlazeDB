# BlazeDB Safety Model

**Purpose:** Explicit guarantees about what BlazeDB does and does not promise.

This document exists to calm fear and set expectations.

---

## Crash Safety Guarantees

### What BlazeDB Guarantees

**After a crash (SIGKILL, power loss, kernel panic):**

1. **All committed writes survive**
   - If `persist()` was called, data is on disk
   - If `close()` was called, all data is flushed
   - WAL replay restores committed state on next open

2. **No partial records**
   - Either a record is fully written, or it doesn't exist
   - No corrupted records due to crashes
   - Page-level atomicity ensures this

3. **Uncommitted transactions are rolled back**
   - If you called `beginTransaction()` but not `commitTransaction()`, changes are lost
   - This is intentional - transactions are explicit

### What BlazeDB Does NOT Guarantee

- **In-flight writes may be lost** if crash occurs before `persist()` or `close()`
- **Metadata updates** may be lost if crash occurs mid-update (recovered via rebuild)
- **Concurrent writers** will corrupt the database (single-writer only)

---

## Atomicity Guarantees

### Single-Operation Atomicity

**Every operation is atomic:**

- `insert()` - Record is fully written or not written at all
- `update()` - Record is fully replaced or not replaced at all
- `delete()` - Record is fully removed or not removed at all

**No partial states possible.**

### Transaction Atomicity

**Transactions are all-or-nothing:**

- `beginTransaction()` starts a transaction
- Operations inside transaction are buffered
- `commitTransaction()` makes all changes visible atomically
- `rollbackTransaction()` discards all changes

**If crash occurs during transaction:**
- Uncommitted changes are lost (rolled back)
- Committed changes survive

---

## Power Loss Behavior

### What Happens

1. **Process terminates immediately** (no cleanup)
2. **WAL contains committed writes** (if `persist()` was called)
3. **On next open:**
   - WAL is replayed
   - Committed writes are restored
   - Uncommitted writes are discarded

### What You'll See

**On next open after power loss:**

- Database opens successfully (no corruption)
- All committed data is present
- Uncommitted transactions are rolled back
- Health status is OK (unless corruption detected)

**If corruption is detected:**

- Database refuses to open
- Error message explains what happened
- Recovery instructions provided

---

## Flush Behavior

### What `close()` Does

1. **Flushes all pending writes** to disk
2. **Flushes metadata** (index map, schema version)
3. **Closes file handles**
4. **Marks database as closed**

**After `close()`, all data is guaranteed on disk.**

### What `persist()` Does

1. **Flushes metadata** to disk
2. **Does NOT flush all pages** (only metadata)

**Use `persist()` for:**
- Ensuring metadata is saved (indexes, schema version)
- Periodic checkpoints during long operations

**Use `close()` for:**
- Ensuring ALL data is on disk before shutdown

### What Happens Without `close()`

**If process terminates without calling `close()`:**

- Pending writes may be lost
- Metadata may be stale
- WAL replay will restore committed writes
- Database will open successfully (with possible data loss)

**Always call `close()` before process exit.**

---

## Failure Modes

### Disk Full

**What happens:**
- Write operations fail with `BlazeDBError.ioFailure`
- Database remains in consistent state
- No corruption occurs

**What to do:**
- Free disk space
- Retry operation
- Or handle error gracefully

---

### Corruption

**What causes it:**
- Hardware failure (bad disk, RAM errors)
- File system bugs
- Manual file tampering

**What BlazeDB does:**
- Refuses to open corrupted database
- Provides clear error message
- Suggests recovery options

**What you can do:**
- Restore from backup (export/restore)
- Use `blazedb doctor` to diagnose
- Rebuild from data pages (if metadata corrupted)

---

### Wrong Password

**What happens:**
- Database refuses to open
- Error: `BlazeDBError.authenticationFailed`
- Clear message: "Invalid encryption key"

**What to do:**
- Use correct password
- Or restore from unencrypted backup

**Note:** BlazeDB cannot recover data with wrong password. Encryption is real.

---

### Schema Mismatch

**What happens:**
- Database opens successfully
- But schema version doesn't match expected version
- Error on operations that require specific schema

**What to do:**
- Run migrations explicitly
- Or use `allowSchemaMismatch: true` (not recommended)

**BlazeDB will NOT:**
- Automatically migrate your data
- Guess how to transform your schema
- Silently change your data

---

## What Is NOT Guaranteed

### Multi-Process Access

**BlazeDB is single-writer:**
- Only one process can write at a time
- Multiple readers are safe
- Multiple writers will corrupt data

**Do NOT:**
- Share database files across processes
- Use network filesystems (NFS, SMB) for writes
- Open same database from multiple apps

---

### Network Filesystems

**BlazeDB is not designed for:**
- NFS (Network File System)
- SMB (Windows shares)
- Cloud storage mounts

**Why:**
- File locking may not work correctly
- fsync behavior is unpredictable
- Performance will be terrible

**Use local filesystems only.**

---

### Automatic Migrations

**BlazeDB will NOT:**
- Automatically migrate your schema
- Guess how to transform your data
- Silently change your records

**You must:**
- Define migrations explicitly
- Run migrations explicitly
- Test migrations before production

---

## Recovery Procedures

### After Crash

1. **Open database normally**
   - BlazeDB will replay WAL automatically
   - Committed writes are restored
   - Uncommitted writes are lost

2. **Check health:**
   ```swift
   let health = try db.health()
   if health.status != .ok {
       // Investigate warnings
   }
   ```

3. **Verify data:**
   ```swift
   let count = db.count()
   // Check if count matches expected
   ```

### After Corruption

1. **Run diagnostics:**
   ```bash
   blazedb doctor <db-path>
   ```

2. **Restore from backup:**
   ```swift
   try BlazeDBImporter.restore(from: backupURL, to: db)
   ```

3. **If no backup:**
   - Metadata may be rebuildable from data pages
   - Contact support with error details

---

## Summary

**BlazeDB guarantees:**
- ✅ Crash-safe committed writes
- ✅ Atomic operations
- ✅ No partial records
- ✅ Explicit error messages

**BlazeDB does NOT guarantee:**
- ❌ Multi-process writes
- ❌ Network filesystem support
- ❌ Automatic migrations
- ❌ Recovery from wrong password

**Always:**
- Call `close()` before process exit
- Use local filesystems
- Run migrations explicitly
- Keep backups

This is how you build trust: by being explicit about limits.
