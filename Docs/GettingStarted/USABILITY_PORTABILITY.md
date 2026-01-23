# Usability & Portability Hardening

**Status:** In Progress  
**Phase:** Post Pre-User Hardening  
**Scope:** API surface, defaults, Linux compatibility - NO engine work

## Goals

Make BlazeDB:
- **Easier to use** - Zero configuration for basic cases
- **Linux-first** - Explicit path handling, no macOS assumptions
- **Error-friendly** - Errors teach, not scold

## Constraints

**STRICT:**
-  No PageStore changes
-  No WAL changes
-  No concurrency changes
-  No storage semantics changes
-  Swift 6 strict concurrency must continue to compile

**ALLOWED:**
-  API surface improvements
-  Default value improvements
-  Path handling utilities
-  Error message improvements
-  Documentation improvements

---

## Work Items

### 1. Easy Entrypoint API 

**Status:** COMPLETE

**Deliverables:**
-  `BlazeDB.openDefault(name:password:)` - Zero configuration
-  `BlazeDB.open(name:path:password:)` - Custom path
-  Automatic directory creation
-  Platform-specific defaults

**Files:**
- `BlazeDB/Exports/BlazeDBClient+EasyOpen.swift`

**Platform Defaults:**
- macOS: `~/Library/Application Support/BlazeDB`
- Linux: `~/.local/share/blazedb`

---

### 2. Platform-Safe Path Handling 

**Status:** COMPLETE

**Deliverables:**
-  `PathResolver` utility
-  Platform-specific default directories
-  Explicit directory creation with permissions
-  Path validation (rejects traversal)
-  Permission error handling

**Files:**
- `BlazeDB/Utils/PathResolver.swift`

**Features:**
- Automatic directory creation
- Permission checking
- Path traversal rejection
- Relative/absolute path resolution

---

### 3. Error UX Polish 

**Status:** COMPLETE

**Deliverables:**
-  Improved error messages for path/directory issues
-  Platform-specific guidance (Linux vs macOS)
-  "What BlazeDB guarantees" vs "What BlazeDB refuses to guess"

**Files:**
- `BlazeDB/Exports/BlazeDBError+Categories.swift` (enhanced)

**Examples:**
- "BlazeDB guarantees: directories are created automatically with openDefault()"
- "BlazeDB refuses to guess: you must provide a valid path or use openDefault()"

---

### 4. Linux Verification 

**Status:** COMPLETE

**Deliverables:**
-  Linux compatibility tests
-  Path resolution tests
-  Directory creation tests
-  Round-trip tests (open → insert → close → reopen)
-  Export/restore tests

**Files:**
- `BlazeDBTests/Platform/LinuxCompatibilityTests.swift`

**Test Coverage:**
- Path resolution (relative, absolute, traversal rejection)
- Directory creation and permissions
- Easy open API
- Round-trip persistence
- Export/restore compatibility

---

### 5. CLI Polish 

**Status:** COMPLETE

**Deliverables:**
-  `blazedb info` - Database information tool
-  All CLI tools work with relative paths
-  All CLI tools print paths being used
-  Consistent exit codes

**Files:**
- `BlazeInfo/main.swift`
- `BlazeDoctor/main.swift` (enhanced)
- `BlazeDump/main.swift` (enhanced)

**CLI Tools:**
- `blazedb doctor` - Health checks
- `blazedb dump` - Backup
- `blazedb restore` - Restore
- `blazedb info` - Database info

---

### 6. Documentation 

**Status:** COMPLETE

**Deliverables:**
-  Linux getting started guide
-  Updated README with simplest usage
-  Platform-specific path documentation
-  Troubleshooting guide

**Files:**
- `Docs/LINUX_GETTING_STARTED.md`
- `README.md` (updated examples)

**Content:**
- Copy-paste Linux examples
- Path location documentation
- Permission troubleshooting
- Platform differences explained

---

## Verification

-  No frozen core files modified
-  No new concurrency constructs
-  Swift 6 strict concurrency compiles
-  Linux tests compile and pass
-  CLI tools work without Xcode
-  All new behavior documented

---

## Summary

**What Changed:**
- Easy entrypoint API (`openDefault()`)
- Platform-safe path handling
- Better error messages
- Linux verification tests
- CLI polish (`blazedb info`)
- Linux documentation

**What Didn't Change:**
- Storage engine
- Concurrency model
- Durability behavior
- Performance characteristics

**Result:**
BlazeDB is now easier to use and Linux-ready, without touching the frozen core.
