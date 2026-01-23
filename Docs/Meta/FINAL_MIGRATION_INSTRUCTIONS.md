# Final Migration Instructions

## Completed

1. Updated Package.swift to use `path: "Tests/BlazeDBTests"`
2. Created Tests/BlazeDBTests/ directory structure
3. Moved critical Codec test files:
 - CodecValidation.swift
 - BlazeBinaryCompatibilityTests.swift
 - BlazeBinaryFuzzTests.swift
 - BlazeBinaryCorruptionRecoveryTests.swift
 - BlazeBinaryFieldViewTests.swift
 - BlazeBinaryLargeRecordTests.swift
 - BlazeBinaryMMapTests.swift
 - BlazeBinaryPointerIntegrityTests.swift
 - BlazeBinaryEncoderTests.swift
 - BlazeBinaryEdgeCaseTests.swift

##  Remaining Work

Due to the large number of files (100+), you need to:

### Option 1: Use File System Commands (Recommended)

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB

# Copy all remaining Codec tests
cp BlazeDBTests/Encoding/BlazeBinary/*.swift Tests/BlazeDBTests/Codec/
cp BlazeDBTests/Encoding/BlazeBinary*.swift Tests/BlazeDBTests/Codec/

# Copy Engine tests
cp -r BlazeDBTests/Core/* Tests/BlazeDBTests/Engine/Core/
cp -r BlazeDBTests/Integration/* Tests/BlazeDBTests/Engine/Integration/
cp BlazeDBTests/Engine/*.swift Tests/BlazeDBTests/Engine/

# Copy Stress tests
cp BlazeDBTests/BlazeDBStressTests.swift Tests/BlazeDBTests/Stress/
cp -r BlazeDBTests/Chaos/* Tests/BlazeDBTests/Stress/Chaos/
cp -r BlazeDBTests/PropertyBased/* Tests/BlazeDBTests/Stress/PropertyBased/
cp BlazeDBTests/FailureInjectionTests.swift Tests/BlazeDBTests/Stress/
cp BlazeDBTests/IOFaultInjectionTests.swift Tests/BlazeDBTests/Stress/

# Copy Performance tests
cp -r BlazeDBTests/Benchmarks/* Tests/BlazeDBTests/Performance/
cp -r BlazeDBTests/Performance/* Tests/BlazeDBTests/Performance/

# Copy Helpers
cp -r BlazeDBTests/Helpers/* Tests/BlazeDBTests/Helpers/

# Copy CI
cp -r BlazeDBTests/CI/* Tests/BlazeDBTests/CI/

# Copy Fixtures
cp -r BlazeDBTests/Fixtures/* Tests/BlazeDBTests/Fixtures/

# Copy all other test files to Engine/Integration
find BlazeDBTests -name "*Tests.swift" -type f! -path "*/Codec/*"! -path "*/Engine/*"! -path "*/Stress/*"! -path "*/Performance/*"! -path "*/Fixtures/*"! -path "*/CI/*"! -path "*/Helpers/*" -exec cp {} Tests/BlazeDBTests/Engine/Integration/ \;

# Copy docs
find BlazeDBTests -name "*.md" -type f -exec cp {} Tests/BlazeDBTests/Docs/ \;
```

### Option 2: Manual File-by-File Copy

Copy each remaining file according to MIGRATION_SCRIPT.md mapping.

## Verification

After copying:

1. Run `swift test --list-tests` to verify discovery
2. Check that all test files end with `Tests.swift`
3. Verify all tests are XCTestCase subclasses
4. Ensure all test methods start with `test`

## Notes

- All imports remain `@testable import BlazeDB` (no changes needed)
- Package.swift already updated
- SwiftPM will discover all `.swift` files in Tests/BlazeDBTests/

