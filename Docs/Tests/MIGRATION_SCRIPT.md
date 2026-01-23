# Complete Test Migration Script

## Status

 Package.swift updated to use `path: "Tests/BlazeDBTests"`

## Remaining Work

Due to the large number of files (100+), a comprehensive migration script is needed.

## File Mapping

### Codec Tests → Tests/BlazeDBTests/Codec/
- BlazeDBTests/Encoding/BlazeBinary/*.swift
- BlazeDBTests/Encoding/BlazeBinary*.swift
- BlazeDBTests/Fuzz/BlazeBinaryFuzzTests.swift
- BlazeDBTests/Codec/*.swift (already moved)

### Engine Tests → Tests/BlazeDBTests/Engine/
- Core/*.swift → Engine/Core/
- Integration/*.swift → Engine/Integration/
- Engine/*.swift → Engine/ (root)
- Aggregation/*.swift → Engine/Integration/
- Concurrency/*.swift → Engine/Integration/
- DataTypes/*.swift → Engine/Core/
- EdgeCases/*.swift → Engine/Core/
- Features/*.swift → Engine/Integration/
- GarbageCollection/*.swift → Engine/Core/
- Indexes/*.swift → Engine/Integration/
- MVCC/*.swift → Engine/Integration/
- Migration/*.swift → Engine/Integration/
- Overflow/*.swift → Engine/Core/
- Persistence/*.swift → Engine/Core/
- Query/*.swift → Engine/Integration/
- Recovery/*.swift → Engine/Core/
- Security/*.swift → Engine/Integration/
- SQL/*.swift → Engine/Integration/
- Sync/*.swift → Engine/Integration/
- Transactions/*.swift → Engine/Integration/
- Backup/*.swift → Engine/Integration/
- ModelBased/*.swift → Engine/Integration/
- Root level *Tests.swift → Engine/Integration/

### Stress Tests → Tests/BlazeDBTests/Stress/
- BlazeDBStressTests.swift
- Chaos/*.swift → Stress/Chaos/
- PropertyBased/*.swift → Stress/PropertyBased/
- FailureInjectionTests.swift
- IOFaultInjectionTests.swift
- Stress/*.swift

### Performance Tests → Tests/BlazeDBTests/Performance/
- Benchmarks/*.swift
- Performance/*.swift
- Indexes/SearchPerformanceBenchmarks.swift

### Helpers → Tests/BlazeDBTests/Helpers/
- Helpers/*.swift
- Utilities/*.swift
- Testing/*.swift

### CI → Tests/BlazeDBTests/CI/
- CI/*.swift
- CIMatrix.swift (root)
- CodecDualPathTestSuite.swift (root)

### Fixtures → Tests/BlazeDBTests/Fixtures/
- Fixtures/*.swift
- Engine/FixtureValidationTests.swift

### Docs → Tests/BlazeDBTests/Docs/
- All *.md files

## Next Steps

Run a script to copy all files according to the mapping above.

