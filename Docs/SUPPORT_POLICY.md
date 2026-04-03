# Support Policy

## Current Support Scope (v2.7.x)

This policy defines what we support and how to report issues.

---

## What We Support

### Core Functionality
- Data corruption or loss
- Migration failures
- Import/export failures
- Query errors or incorrect results
- Performance regressions in core operations

### Trust Features
- Health report accuracy
- Error message clarity
- Migration planning correctness
- Dump/restore integrity

### Documentation
- Missing or unclear documentation
- Incorrect examples
- API documentation gaps

---

## What We Don't Support (Yet)

### Distributed Modules
- Sync/replication issues (modules not Swift 6 compliant)
- Network transport problems
- Cross-app sync failures

### Performance Optimization
- Broad "make it faster" requests without reproducible workload details
- Parallelism requests that bypass current safety constraints
- Query optimization requests without schema/query examples

### Experimental Features
- Advanced query features (spatial, vector on Linux)
- Telemetry API issues (actor isolation problems)

---

## How to Report Issues

### Bug Reports
Use GitHub Issues with this template:

```
**BlazeDB Version:** [e.g., 2.7.0]
**Swift Version:** [e.g., 6.0]
**Platform:** [macOS/iOS/Linux]

**Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Database State:**
- Record count: [number]
- Schema version: [version]
- Health status: [OK/WARN/ERROR]

**Error Messages:**
[Full error output]

**Additional Context:**
[Any other relevant information]
```

### Feature Requests
Feature requests are welcome but may be deferred:
- Core stability takes priority
- Phase 2 (parallelism) is explicitly deferred
- Distributed modules are separate project

---

## Response Time Expectations

### Critical Issues (Data Loss, Corruption)
- **Response:** Within 24 hours
- **Fix:** As soon as possible

### High Priority (Migration Failures, Import/Export)
- **Response:** Within 48 hours
- **Fix:** Within 1 week

### Medium Priority (Query Errors, Performance)
- **Response:** Within 1 week
- **Fix:** Within 2 weeks

### Low Priority (Documentation, Minor Issues)
- **Response:** Within 2 weeks
- **Fix:** Next release

---

## API Stability Commitment

### Stable APIs (v2.x)
We commit to:
- No breaking changes without major version bump
- Deprecation warnings before removal
- Migration paths for breaking changes

## Maintenance and Deprecation Cadence

### Supported Release Lines

- Current stable minor line (for example: `2.7.x`): actively maintained.
- Previous stable minor line: best-effort security and critical fixes only.
- Older lines: unsupported unless explicitly announced.
- Legacy pre-OSS tags that depended on private SSH transport repositories are treated as archival and are not guaranteed to be reproducible in public clean-clone environments.

### Deprecation Cadence

- New deprecations are announced in `CHANGELOG.md`.
- Deprecated APIs receive at least one minor release of warning-only period before removal.
- Removals are performed only in a major release unless a severe security issue requires faster action.

### Experimental APIs
- May change without notice
- No stability guarantees
- Use at your own risk

---

## Limitations and Known Issues

### Current Limitations
- Distributed modules not Swift 6 compliant
- Parallel encoding disabled (Phase 1 freeze)
- No automatic query optimization

### Known Issues
See GitHub Issues for current known issues.

---

## Getting Help

### Documentation
- `../README.md` - Quick start
- `GettingStarted/QUERY_PERFORMANCE.md` - Query guidance
- `GettingStarted/OPERATIONAL_CONFIDENCE.md` - Health monitoring
- `Compliance/PRE_USER_HARDENING.md` - Trust features

### Tools
- `blazedb doctor` - Health checks
- `blazedb dump` - Backup/restore
- `db.stats()` - Statistics
- `db.health()` - Health reports

### Community
- GitHub Issues for bugs
- GitHub Discussions for questions

---

## Summary

**We Support:**
- Core functionality bugs
- Trust feature issues
- Documentation improvements

**We Don't Support (Yet):**
- Distributed sync
- Performance optimization
- Experimental features

**Response Times:**
- Critical: 24 hours
- High: 48 hours
- Medium: 1 week
- Low: 2 weeks

**Lifecycle:**
- Active support for current release line
- Older release lines are best-effort unless otherwise announced
