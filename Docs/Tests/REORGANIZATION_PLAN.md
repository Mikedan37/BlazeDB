# Test Reorganization Plan

## New Structure

```
BlazeDBTests/
 Codec/ # All BlazeBinary codec tests
 Engine/ # Engine integration tests
 Stress/ # Stress and fuzz tests
 Performance/ # Performance benchmarks
 Fixtures/ # Test fixtures
 CI/ # CI-specific tests
 Docs/ # Documentation
 Helpers/ # Shared test helpers (keep existing)
```

## File Moves

### Codec/ (BlazeBinary codec tests)
- Encoding/BlazeBinary/*.swift → Codec/
- Encoding/BlazeBinaryEncoderTests.swift → Codec/
- Encoding/BlazeBinaryEdgeCaseTests.swift → Codec/
- Encoding/BlazeBinaryExhaustiveVerificationTests.swift → Codec/
- Encoding/BlazeBinaryDirectVerificationTests.swift → Codec/
- Encoding/BlazeBinaryReliabilityTests.swift → Codec/
- Encoding/BlazeBinaryUltimateBulletproofTests.swift → Codec/
- Encoding/BlazeBinaryPerformanceTests.swift → Codec/
- Fuzz/BlazeBinaryFuzzTests.swift → Codec/
- Helpers/CodecValidation.swift → Codec/

### Engine/ (Engine integration tests)
- Engine/*.swift → Engine/ (already there)
- Core/*.swift → Engine/Core/
- Integration/*.swift → Engine/Integration/

### Stress/ (Stress and fuzz tests)
- Stress/*.swift → Stress/ (already there)
- BlazeDBStressTests.swift → Stress/
- Chaos/*.swift → Stress/Chaos/
- PropertyBased/*.swift → Stress/PropertyBased/
- FailureInjectionTests.swift → Stress/
- IOFaultInjectionTests.swift → Stress/

### Performance/ (Performance benchmarks)
- Performance/*.swift → Performance/ (already there)
- Benchmarks/*.swift → Performance/
- Indexes/SearchPerformanceBenchmarks.swift → Performance/

### Fixtures/ (Test fixtures)
- Fixtures/*.swift → Fixtures/ (already there)
- Engine/FixtureValidationTests.swift → Fixtures/

### CI/ (CI-specific tests)
- CIMatrix.swift → CI/
- CodecDualPathTestSuite.swift → CI/

### Docs/ (Documentation)
- *.md → Docs/
- CREATE_TEST_PLANS_IN_XCODE.md → Docs/
- TEST_*.md → Docs/

## Import Path Updates

All test files use `@testable import BlazeDB` which doesn't need updating.

CodecValidation.swift helper functions are used via direct function calls (no import needed).

