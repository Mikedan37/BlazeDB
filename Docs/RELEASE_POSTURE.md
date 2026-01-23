# Release Posture

**Version:** 0.1.0 (Pre-User Hardening Release)  
**Status:** Ready for early adopters  
**Date:** Pre-User Hardening Phase Complete

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

### Current: v0.1.0
- **Type:** Pre-1.0 release
- **Breaking Changes:** May occur (documented in CHANGELOG)
- **Stability:** Core APIs stable, experimental APIs marked

### Target: v1.0.0
- **Timeline:** After early adopter feedback
- **Breaking Changes:** None (major version bump only)
- **Stability:** All stable APIs locked

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

### For Early Adopters
1. Test real workloads
2. Report friction points
3. Provide feedback on APIs
4. Help identify polish needs

### For Maintainers
1. Monitor early adopter feedback
2. Fix critical issues quickly
3. Document common patterns
4. Plan v1.0.0 based on usage

---

## Summary

**This Release:**
- Complete trust envelope
- Swift 6 compliant core
- Comprehensive tooling
- Ready for early adopters

**Not Included:**
- Distributed sync
- Performance optimization
- Automatic tuning

**Next Phase:**
- Real-world usage
- Early adopter feedback
- Polish based on friction
- v1.0.0 planning

**Status:** Ready for controlled early adoption.
