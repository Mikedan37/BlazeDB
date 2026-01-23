# Changelog

All notable changes to BlazeDB will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Query validation with helpful error messages and field name suggestions
- Schema versioning and explicit migration system
- Import/export with integrity verification (deterministic dump format)
- Operational confidence: health reports (OK/WARN/ERROR) with actionable guidance
- `blazedb doctor` CLI tool for database health checks
- `blazedb dump` CLI tool for database backup/restore
- Comprehensive documentation: query performance, operational confidence, migration guides

### Changed
- Error messages are now categorized and include remediation hints
- Database statistics include interpretation (not just raw numbers)
- Query errors provide field name suggestions using Levenshtein distance

### Fixed
- Swift 6 strict concurrency compliance for core modules
- Deadlock prevention guards in PageStore (dispatchPrecondition)
- Durability verification across database close/reopen cycles

### Documentation
- `QUERY_PERFORMANCE.md` - Query performance characteristics and best practices
- `OPERATIONAL_CONFIDENCE.md` - Health monitoring and when to investigate
- `PRE_USER_HARDENING.md` - Complete trust envelope documentation
- `CONCURRENCY_COMPLIANCE.md` - Swift 6 concurrency status and guarantees

## [0.1.0] - Pre-User Hardening Release

### Status
**Core modules:**  Swift 6 strict concurrency compliant  
**Distributed modules:**  Not yet compliant (excluded from core)

### Compatibility
- **Swift:** 6.0+
- **Platforms:** macOS 14+, iOS 15+, Linux (aarch64)
- **Storage format:** Stable (v1.0)
- **Migration format:** Stable (v1.0)
- **Dump format:** Stable (v1.0)

### API Stability
- **Stable:** Core CRUD operations, query builder, statistics API
- **Stable:** Migration system (SchemaVersion, BlazeDBMigration protocol)
- **Stable:** Import/export APIs (DumpFormat v1)
- **Experimental:** Distributed sync modules (not included in core)

### Known Limitations
- Distributed modules fail to compile under Swift 6 strict concurrency
- Parallel encoding/compression temporarily disabled (Phase 1 freeze)
- No automatic query optimization (manual index creation required)

---

## Version History

### 0.1.0 (Pre-User Hardening)
- Complete trust envelope: query ergonomics, migrations, import/export, operational confidence
- Swift 6 strict concurrency compliance for core
- Comprehensive documentation and tooling
