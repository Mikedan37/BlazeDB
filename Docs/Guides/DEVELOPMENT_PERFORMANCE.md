# Development Performance Guide

**Purpose:** Understand why your MacBook fan spins up during development and how to reduce it.

---

## Why Fans Spin Up

### During `swift build`

**Normal causes:**
- Swift compiler is CPU-intensive
- Large codebase (BlazeDB has many files)
- Type checking and optimization

**What's normal:**
- Initial build: 30-60 seconds (expected)
- Incremental builds: 1-5 seconds (normal)
- Full rebuild: 30-60 seconds (normal)

**What's NOT normal:**
- Builds taking > 2 minutes consistently
- Fans spinning during idle
- CPU usage > 50% when not building

---

### During `swift test`

**Normal causes:**
- Tests create/delete databases repeatedly
- File I/O operations
- Encryption/decryption overhead

**What's normal:**
- Tier 1 tests: 5-15 seconds (expected)
- All tests: 30-60 seconds (normal)
- CPU usage spikes during tests (normal)

**What's NOT normal:**
- Tests taking > 2 minutes
- Memory usage growing unbounded
- Tests hanging indefinitely

---

### During Large Insert Loops

**Normal causes:**
- Encryption overhead (every write is encrypted)
- WAL flushing
- Index updates

**What's normal:**
- 1,000 records: < 1 second
- 10,000 records: 5-10 seconds
- 100,000 records: 30-60 seconds

**What's NOT normal:**
- Insert loops taking > 5 minutes for 10K records
- Memory usage > 1GB for small datasets
- CPU usage stuck at 100%

---

## Recommended Development Limits

### For Quick Iteration

**Record counts:**
- Development: < 1,000 records
- Testing: < 10,000 records
- Production: No limit (but monitor performance)

**Batch sizes:**
- Development: 10-100 records per batch
- Testing: 100-1,000 records per batch
- Production: 1,000-10,000 records per batch

**Why:**
- Smaller batches = faster feedback
- Larger batches = better performance (but slower iteration)

---

## Debug Flags (Development Only)

### Reduce Validation Intensity

**For faster development builds:**

Add to your test/debug build settings:
```swift
#if DEBUG
// Reduce validation during development
BlazeBinaryEncoder.crc32Mode = .disabled  // Faster, less validation
#endif
```

**Warning:** Only use in development. Production should always validate.

---

### Disable Telemetry (If Available)

**For faster test runs:**

```swift
#if DEBUG
// Disable telemetry during development
// (Reduces overhead)
#endif
```

---

## What's Safe to Ignore

### During Development

**Safe to ignore:**
- Warnings about uncommitted transactions (if intentional)
- Health warnings about WAL size (if testing)
- Performance warnings (if not optimizing yet)

**NOT safe to ignore:**
- Compilation errors
- Test failures
- Memory leaks
- Corruption errors

---

## Production vs Development

### Development Settings

**Optimize for:**
- Fast iteration
- Quick feedback
- Low CPU usage

**Use:**
- Smaller datasets
- Fewer validation checks (DEBUG only)
- Simpler queries

### Production Settings

**Optimize for:**
- Correctness
- Durability
- Performance

**Use:**
- Full validation (CRC32 enabled)
- Appropriate batch sizes
- Indexed queries
- Regular `persist()` calls

---

## CPU Usage Patterns

### Normal Patterns

**During build:**
- CPU: 50-100% (normal)
- Duration: 30-60 seconds (normal)
- Fans: May spin up (normal)

**During tests:**
- CPU: 30-70% (normal)
- Duration: 5-60 seconds (normal)
- Fans: May spin up (normal)

**During inserts:**
- CPU: 20-50% (normal)
- Duration: Varies by record count
- Fans: Usually quiet

### Abnormal Patterns

**Investigate if you see:**
- CPU stuck at 100% for > 5 minutes
- Memory usage growing unbounded
- Tests hanging indefinitely
- Builds taking > 5 minutes consistently

---

## Reducing Development Friction

### Use Tier 1 Tests Only

**For quick feedback:**
```bash
./Scripts/test-gate.sh
```

**Runs only production-critical tests (fast).**

### Use Smaller Datasets

**For development:**
- Test with 10-100 records
- Scale up only when needed
- Use realistic but small data

### Batch Operations

**For better performance:**
```swift
// Instead of:
for record in records {
    try db.insert(record)
}

// Use:
try db.insertMany(records)  // 3-5x faster
```

---

## When to Worry

### Performance Issues

**Worry if:**
- Simple operations take > 1 second
- Memory usage > 1GB for small datasets
- CPU usage stuck at 100%

**Don't worry if:**
- Initial build takes 30-60 seconds (normal)
- Tests take 5-15 seconds (normal)
- Fans spin during builds (normal)

---

## Summary

**Development is different from production:**

- **Development:** Fast iteration, quick feedback, smaller datasets
- **Production:** Correctness, durability, performance

**Fans spinning during builds/tests is normal.**

**Focus on:**
- Using Tier 1 tests for quick feedback
- Batching operations when possible
- Keeping development datasets small

**Don't optimize prematurely.** Get it working first, then optimize.
