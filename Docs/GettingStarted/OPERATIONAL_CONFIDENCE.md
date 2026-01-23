# Operational Confidence Guide

**Purpose:** Help users understand database health, interpret statistics, and know when to investigate.

## Health Status

BlazeDB provides three health statuses:

### OK
Database is operating normally. No action required.

**Indicators:**
- WAL size is reasonable (< 20% of database size)
- Cache hit rate is good (> 70%)
- Records per page ratio is healthy (> 10)
- Database size is manageable

### WARN
Database has some concerns but is still functional. Monitor and consider action.

**Common WARN conditions:**
- WAL size is growing (20-50% of database size)
- Cache hit rate is moderate (50-70%)
- Low records per page (< 10) - possible fragmentation
- Database size is large (> 10 GB)

**Actions:**
- Run `blazedb doctor` for detailed diagnostics
- Consider checkpoint if WAL is large
- Consider vacuum if fragmentation is detected

### ERROR
Database has serious issues requiring attention.

**Common ERROR conditions:**
- WAL size is very large (> 50% of database size)
- Cache hit rate is very low (< 50%)
- Severe fragmentation (< 5 records per page)

**Actions:**
- Run `blazedb doctor` immediately
- Check disk space
- Consider maintenance operations

## Statistics Interpretation

### Record Count
- **0**: Empty database
- **< 100**: Small database
- **100 - 10,000**: Moderate size
- **10,000 - 1,000,000**: Large database
- **> 1,000,000**: Very large database

### Page Count
- **Records per page**: Indicates fragmentation
  - **> 10**: Healthy
  - **5-10**: Moderate fragmentation
  - **< 5**: Severe fragmentation (consider vacuum)

### Database Size
- **Average record size**: Total size / record count
  - **< 1 KB**: Small records
  - **1-10 KB**: Normal records
  - **> 10 KB**: Large records

### WAL Size
- **WAL ratio**: WAL size / database size
  - **< 20%**: Normal
  - **20-50%**: Growing (consider checkpoint)
  - **> 50%**: Large (run checkpoint)

### Cache Hit Rate
- **> 90%**: Excellent
- **70-90%**: Good
- **50-70%**: Moderate (expect slower reads)
- **< 50%**: Low (expect slower reads)

### Index Count
- **0**: No indexes (queries may be slow)
- **1-5**: Few indexes
- **> 5**: Well-indexed

## When to Investigate

### Investigate Immediately (ERROR status)
- WAL size > 50% of database size
- Cache hit rate < 50%
- Severe fragmentation (< 5 records per page)

### Investigate Soon (WARN status)
- WAL size 20-50% of database size
- Cache hit rate 50-70%
- Moderate fragmentation (5-10 records per page)
- Database size > 10 GB

### Monitor (OK status)
- All metrics within normal ranges
- No action needed, but continue monitoring

## Using Health Reports

### Programmatic Access
```swift
let health = try db.health()
print("Status: \(health.status)")
for reason in health.reasons {
    print("- \(reason)")
}
for action in health.suggestedActions {
    print("→ \(action)")
}
```

### CLI Access
```bash
blazedb doctor /path/to/db.blazedb password
```

The doctor command now includes:
- Health status (OK/WARN/ERROR)
- Reasons for the status
- Suggested actions
- Interpreted statistics

## Thresholds Reference

| Metric | Normal | Warn | Error |
|--------|--------|------|-------|
| WAL Ratio | < 20% | 20-50% | > 50% |
| Cache Hit Rate | > 70% | 50-70% | < 50% |
| Records/Page | > 10 | 5-10 | < 5 |
| Database Size | < 10 GB | 10 GB+ | N/A |

## Best Practices

1. **Regular Health Checks**
   - Run `blazedb doctor` weekly
   - Monitor health status in production

2. **Proactive Maintenance**
   - Run checkpoint if WAL grows large
   - Run vacuum if fragmentation detected
   - Monitor cache hit rate trends

3. **Capacity Planning**
   - Monitor database size growth
   - Plan for disk space
   - Consider archiving old data

## Limitations

**What health reports do NOT do:**
-  Background monitoring (computed on-demand only)
-  Automatic tuning (observes only)
-  Performance optimization (interpretation only)
-  Predictive alerts (current state only)

**What health reports DO:**
-  Provide current health verdict
-  Interpret statistics meaningfully
-  Suggest actionable steps
-  Help users understand their database

## Summary

Operational confidence makes BlazeDB:
- **Understandable**: Clear health status and interpretation
- **Predictable**: Know when to investigate
- **Trustworthy**: Actionable guidance, not raw numbers

**Remember:** Health reports are computed on-demand. They observe and explain, but do not monitor or tune automatically.
