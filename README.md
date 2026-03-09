# BlazeDB

**Version:** 2.7.0  
**Status:** Core modules Swift 6 strict concurrency compliant  
**License:** MIT

BlazeDB is a Swift database with explicit trust features: query ergonomics, schema migrations, verifiable backups, and operational confidence.

**Embedded database for Swift with ACID transactions, encryption, and schema-less storage.**

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Mikedan37/BlazeDB)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 60-Second Quick Start

```swift
import BlazeDB

let db = try BlazeDBClient.open(named: "myapp", password: "your-password")

try db.insert(BlazeDataRecord(["name": .string("Alice"), "role": .string("engineer")]))

let users = try db.query().execute().records
print("Users: \(users.count)")

try db.close()
```

If this runs, BlazeDB is working. [Next: HelloBlazeDB example](Examples/HelloBlazeDB/)

---

## Install

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Mikedan37/BlazeDB.git", from: "2.7.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["BlazeDB"])
]
```

Or in Xcode: File → Add Package Dependencies → paste the URL.

---

## What You Get

- ACID transactions with crash recovery
- AES-256-GCM encryption (on by default)
- Sub-millisecond queries
- Zero dependencies

---

## Learn More

| Resource | Description |
|----------|-------------|
| [Getting Started Guide](Docs/GettingStarted/README.md) | Step-by-step setup in 5 minutes |
| [Complete Reference](Docs/GettingStarted/HOW_TO_USE_BLAZEDB.md) | Migrations, backups, health checks |
| [Examples](Examples/) | Working code for common patterns |
| [Linux Guide](Docs/GettingStarted/LINUX_GETTING_STARTED.md) | Linux-specific setup |

---

## Documentation

- [API Reference](Docs/DEVELOPER_GUIDE.md)
- [Architecture](Docs/Architecture/)
- [Production Readiness](Docs/PRODUCTION_READINESS/INDEX.md)

**Requirements:** Swift 5.9+, macOS 12+ / iOS 15+ / Linux

**License:** MIT
