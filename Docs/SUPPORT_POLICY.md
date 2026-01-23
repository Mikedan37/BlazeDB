# Support Policy

## Early Adopter Support (v0.1.0)

BlazeDB is in early adopter phase. This policy defines what we support and how.

---

## What We Support

### Core Functionality
-  Data corruption or loss
-  Migration failures
-  Import/export failures
-  Query errors or incorrect results
-  Performance regressions in core operations

### Trust Features
-  Health report accuracy
-  Error message clarity
-  Migration planning correctness
-  Dump/restore integrity

### Documentation
-  Missing or unclear documentation
-  Incorrect examples
-  API documentation gaps

---

## What We Don't Support (Yet)

### Distributed Modules
-  Sync/replication issues (modules not Swift 6 compliant)
-  Network transport problems
-  Cross-app sync failures

### Performance Optimization
-  "Make it faster" requests (Phase 2 not started)
-  Parallelism requests (explicitly deferred)
-  Query optimization requests (manual indexing required)

### Experimental Features
-  Advanced query features (spatial, vector on Linux)
-  Telemetry API issues (actor isolation problems)

---

## How to Report Issues

### Bug Reports
Use GitHub Issues with this template:

```
**BlazeDB Version:** [e.g., 0.1.0]
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

## Early Adopter Program

### Who Qualifies
- 1-3 selected early adopters
- Clear use case
- Willing to provide feedback
- Can test real workloads

### What You Get
- Direct support channel
- Priority bug fixes
- Early access to new features
- Input on API design

### What We Ask
- Regular feedback
- Bug reports with details
- Real-world usage testing
- Patience with limitations

---

## API Stability Commitment

### Stable APIs (v0.1.0+)
We commit to:
- No breaking changes without major version bump
- Deprecation warnings before removal
- Migration paths for breaking changes

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
- `README.md` - Quick start
- `QUERY_PERFORMANCE.md` - Query guidance
- `OPERATIONAL_CONFIDENCE.md` - Health monitoring
- `PRE_USER_HARDENING.md` - Trust features

### Tools
- `blazedb doctor` - Health checks
- `blazedb dump` - Backup/restore
- `db.stats()` - Statistics
- `db.health()` - Health reports

### Community
- GitHub Issues for bugs
- GitHub Discussions for questions
- Early adopter channel (by invitation)

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

**Early Adopters:**
- Direct support
- Priority fixes
- Real-world testing
