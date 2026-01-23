# TODO: Direct Codable Encoder (No JSON Intermediate)

## Goal
Create a custom Swift `Encoder` implementation that directly converts `Codable` types (like `BlazeRecord`) to `BlazeDataRecord` without using JSON as an intermediate format.

## Current State
- `BlazeRecord.toBlazeDataRecord()` uses JSONEncoder → JSON → BlazeDataRecord
- `BlazeRecord.fromBlazeDataRecord()` uses BlazeDataRecord → JSON → JSONDecoder
- This works but is inefficient (extra JSON serialization step)

## Implementation Plan

### 1. Create `BlazeRecordEncoder` class
- Implements Swift's `Encoder` protocol
- Directly builds `BlazeDataRecord` during encoding
- Handles all Swift types: String, Int, Double, Bool, UUID, Date, Data, Array, Dictionary, Optional

### 2. Create `BlazeRecordDecoder` class
- Implements Swift's `Decoder` protocol
- Directly converts `BlazeDataRecord` to Codable types
- Handles type conversions (e.g., Date from TimeInterval, Bool from Int)

### 3. Update `BlazeRecord` extension
- Replace `toBlazeDataRecord()` to use `BlazeRecordEncoder`
- Replace `fromBlazeDataRecord()` to use `BlazeRecordDecoder`
- Remove JSON intermediate step

### 4. Benefits
- **10-20% faster** encoding/decoding
- **Lower memory usage** (no intermediate JSON Data)
- **Type-safe** (direct conversion, fewer errors)
- **Cleaner code** (no JSON serialization)

### 5. Files to Create/Modify
- `BlazeDB/Core/BlazeRecordEncoder.swift` (new)
- `BlazeDB/Core/BlazeRecordDecoder.swift` (new)
- `BlazeDB/Core/BlazeRecord.swift` (update extension methods)

## Reference
- Swift Encoder protocol: https://developer.apple.com/documentation/swift/encoder
- Similar to PropertyListEncoder but for BlazeDataRecord

## Priority
Medium - Current JSON approach works fine, but direct encoding would be more efficient and cleaner.

