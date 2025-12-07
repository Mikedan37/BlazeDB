// CreateTestDB.swift
// Temporary file to create a test database for BlazeDBVisualizer
//
// To run: 
// 1. Add this file to BlazeShell target in Xcode
// 2. Replace BlazeShell/main.swift contents with this
// 3. Run the BlazeShell scheme (⌘R)
// 4. Refresh BlazeDBVisualizer

import BlazeDB
import Foundation

print("📦 Creating test database for BlazeDBVisualizer...")

let db = try BlazeDBClient(
    name: "test_visualizer",
    fileURL: URL(fileURLWithPath: "/Users/mdanylchuk/Desktop/test.blazedb"),
    password: "test123"
)

print("✏️  Adding 50 test records...")

for i in 0..<50 {
    _ = try db.insert(BlazeDataRecord([
        "id": .int(i),
        "name": .string("Test Item \(i)"),
        "email": .string("test\(i)@example.com"),
        "age": .int(20 + (i % 50)),
        "active": .bool(i % 2 == 0),
        "created": .date(Date())
    ]))
}

try db.persist()

print("✅ Created test.blazedb on Desktop with 50 records!")
print("📍 Location: /Users/mdanylchuk/Desktop/test.blazedb")
print("🔑 Password: test123")
print("")
print("Now:")
print("1. Restart BlazeDBVisualizer")
print("2. You should see 'test_visualizer' in the list!")
print("3. Click it, enter password 'test123', and unlock with Touch ID!")

