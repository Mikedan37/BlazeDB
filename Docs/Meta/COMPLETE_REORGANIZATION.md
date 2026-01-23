# Complete Test Reorganization

## Status: IN PROGRESS

Due to terminal command limitations, files are being moved using direct file operations.

## Strategy

1. Copy all remaining test files from `BlazeDBTests/` to `Tests/BlazeDBTests/`
2. Organize by subsystem:
 - Codec tests → `Tests/BlazeDBTests/Codec/`
 - Engine tests → `Tests/BlazeDBTests/Engine/`
 - Stress tests → `Tests/BlazeDBTests/Stress/`
 - Performance tests → `Tests/BlazeDBTests/Performance/`
3. Update Package.swift (already done)

## Files to Move

### Codec Tests (from Encoding/)
- BlazeBinaryEdgeCaseTests.swift
- BlazeBinaryExhaustiveVerificationTests.swift
- BlazeBinaryDirectVerificationTests.swift
- BlazeBinaryReliabilityTests.swift
- BlazeBinaryUltimateBulletproofTests.swift
- BlazeBinaryPerformanceTests.swift
- Encoding/BlazeBinary/*.swift (already moved some)

### Engine Tests
- Core/*.swift → Engine/Core/
- Integration/*.swift → Engine/Integration/
- All other engine-related tests

### Stress Tests
- BlazeDBStressTests.swift
- Chaos/*.swift
- PropertyBased/*.swift
- FailureInjectionTests.swift
- IOFaultInjectionTests.swift

### Performance Tests
- Benchmarks/*.swift
- Performance/*.swift

## Next Steps

1. Read each file from old location
2. Write to new location in Tests/BlazeDBTests/
3. Verify Package.swift path is correct (done)
4. Test discovery with `swift test`

