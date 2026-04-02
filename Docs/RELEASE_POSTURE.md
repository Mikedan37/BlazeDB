# Release Posture

**Version Line:** 2.7.x  
**Status:** Active stable line  
**Tag Policy:** `vX.Y.Z` tags drive release workflow

---

## What This Release Includes

### Trust Envelope (Complete)
-  Query ergonomics (validation, error messages, performance docs)
-  Schema evolution (versioning, migrations, planning)
-  Import/export (deterministic dumps, integrity verification)
-  Operational confidence (health reports, stats interpretation)

### Core Stability
-  Swift 6 strict concurrency compliant
-  Deadlock prevention guards
-  Durability verified across close/reopen cycles
-  Comprehensive test coverage

### Tooling
-  `blazedb doctor` - Health checks
-  `blazedb dump` - Backup/restore
-  `db.stats()` - Statistics API
-  `db.health()` - Health reports

---

## What This Release Does NOT Include

### Distributed Modules
-  Sync/replication (not Swift 6 compliant)
-  Cross-app sync (excluded from core)
-  Network transport (separate project)

### Performance Features
-  Parallel encoding (Phase 1 freeze)
-  Query optimization (manual indexing)
-  Automatic tuning (explicit only)

---

## Version Strategy

### Current: v2.7.x
- **Type:** Stable release line
- **Breaking Changes:** Not allowed for stable APIs inside 2.x
- **Stability:** Core APIs stable, experimental APIs explicitly marked

### Future Major: v3.0.0+
- **Breaking Changes:** Allowed only with major version bump
- **Migration:** Required notes and migration guidance in `CHANGELOG.md`

---

## Compatibility Statement

**Core:**  Swift 6 compliant, stable, production-ready  
**Distributed:**  Not yet compliant, excluded from core  
**Storage:**  Stable format, migration support  
**APIs:**  Core APIs stable, experimental APIs clearly marked

See `COMPATIBILITY.md` for details.

---

## Support Expectations

### What We Support
- Core functionality bugs
- Migration failures
- Import/export issues
- Health report accuracy

### What We Don't Support (Yet)
- Distributed sync issues
- Performance optimization requests
- Experimental API problems

### Response Times
- Critical: 24 hours
- High: 48 hours
- Medium: 1 week
- Low: 2 weeks

See `SUPPORT_POLICY.md` for details.

---

## API Stability

### Stable APIs
- Core CRUD operations
- Query builder
- Statistics API
- Health API
- Migration system
- Import/export APIs

### Experimental APIs
- Distributed sync
- Advanced queries
- Telemetry

See `API_STABILITY.md` for details.

---

## Use Cases

### Ready For
-  Local-first apps
-  Devtools caches/indexes
-  Secure local storage
-  Audit logging / forensic stores
-  Data that outlives the binary

### Not Ready For (Yet)
-  Distributed systems (sync not available)
-  High-throughput scenarios (parallelism disabled)
-  Automatic optimization needs (manual indexing)

---

## Next Steps

### For Users
1. Read `QUERY_PERFORMANCE.md` for query guidance
2. Read `OPERATIONAL_CONFIDENCE.md` for health monitoring
3. Use `blazedb doctor` for health checks
4. Use `blazedb dump` for backups

### For Maintainers
1. Keep PR gate green (`ci.yml` — macOS 15 primary job)
2. Publish releases from `v*` tags only
3. Document all behavior-impacting changes in `CHANGELOG.md`

---

## Summary

**This Line (2.x):**
- Swift 6 core engine with tiered CI gates
- Stable API commitment for core APIs
- Release automation from signed/tagged workflow

**Excluded from core line:**
- Distributed sync modules (staging/experimental)

**Status:** Stable and actively maintained.
