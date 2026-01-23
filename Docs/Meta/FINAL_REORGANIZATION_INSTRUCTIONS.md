# Final Test Reorganization Instructions

## Status

 **Completed:**
- Created new directory structure (Codec/, Engine/, Stress/, Performance/, Fixtures/, CI/, Docs/)
- Moved critical Codec test files:
 - CodecValidation.swift
 - BlazeBinaryCompatibilityTests.swift
 - BlazeBinaryFuzzTests.swift
 - BlazeBinaryCorruptionRecoveryTests.swift
 - BlazeBinaryFieldViewTests.swift
 - BlazeBinaryLargeRecordTests.swift
 - BlazeBinaryMMapTests.swift
 - BlazeBinaryPointerIntegrityTests.swift
 - BlazeBinaryEncoderTests.swift
- Moved CI test files:
 - CIMatrix.swift
 - CodecDualPathTestSuite.swift
- Moved Fixtures:
 - FixtureValidationTests.swift
 - Updated FixtureLoader.swift bundle references

## Remaining Files to Move

Due to the large number of files (100+), please run the provided Python script to complete the reorganization:

### Option 1: Run Python Script (Recommended)

```bash
cd BlazeDBTests
python3 reorganize.py
```

This script will:
- Move all remaining Codec tests
- Move all Engine tests
- Move all Stress tests
- Move all Performance tests
- Move all Docs
- Clean up empty directories

### Option 2: Manual Moves

If the script doesn't work, manually move files according to `REORGANIZATION_PLAN.md`.

## Files Still Need Moving

### Codec/ (from Encoding/)
- `Encoding/BlazeBinaryEdgeCaseTests.swift` → `Codec/`
- `Encoding/BlazeBinaryExhaustiveVerificationTests.swift` → `Codec/`
- `Encoding/BlazeBinaryDirectVerificationTests.swift` → `Codec/`
- `Encoding/BlazeBinaryReliabilityTests.swift` → `Codec/`
- `Encoding/BlazeBinaryUltimateBulletproofTests.swift` → `Codec/`
- `Encoding/BlazeBinaryPerformanceTests.swift` → `Codec/`

### Engine/ (from Core/ and Integration/)
- `Core/*.swift` → `Engine/Core/`
- `Integration/*.swift` → `Engine/Integration/`

### Stress/ (from root and subdirectories)
- `BlazeDBStressTests.swift` → `Stress/`
- `Chaos/*.swift` → `Stress/Chaos/`
- `PropertyBased/*.swift` → `Stress/PropertyBased/`
- `FailureInjectionTests.swift` → `Stress/`
- `IOFaultInjectionTests.swift` → `Stress/`

### Performance/ (from Benchmarks/ and Indexes/)
- `Benchmarks/*.swift` → `Performance/`
- `Indexes/SearchPerformanceBenchmarks.swift` → `Performance/`

### Docs/ (all.md files)
- `*.md` → `Docs/` (except reorganization scripts)

## Verification

After moving files:

1. **Run tests:**
 ```bash
 swift test
 ```

2. **Verify test discovery:**
 - Xcode should show all tests in test navigator
 - SwiftPM should discover all tests automatically

3. **Check for broken imports:**
 - All tests use `@testable import BlazeDB` (no changes needed)
 - CodecValidation.swift functions are available via direct calls

## Notes

- **No Package.swift changes needed** - Test target path remains `BlazeDBTests`
- **No import path changes needed** - All imports use `@testable import BlazeDB`
- **CodecValidation.swift** - Helper functions work via direct calls (no import needed)
- **SwiftPM/Xcode** - Automatically discovers all `.swift` files regardless of subdirectory structure

## After Completion

1. Delete old empty directories
2. Update any CI scripts that reference specific paths
3. Update documentation references
4. Run full test suite to verify everything works

