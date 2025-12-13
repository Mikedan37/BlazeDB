# Changelog

All notable changes to BlazeDB will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive Cryptographic Architecture documentation
- CONTRIBUTING.md guidelines
- CHANGELOG.md for version tracking

### Changed
- README refactored for open-source release
- Improved documentation structure

## [2.5.0-alpha] - 2025-01-XX

### Added
- Multi-version concurrency control (MVCC) with snapshot isolation
- Write-ahead logging (WAL) for crash recovery
- Per-page AES-256-GCM encryption
- BlazeBinary encoding format (53% smaller than JSON)
- Fluent query API with automatic index selection
- Full-text search with inverted index
- Spatial and vector indexes
- JOIN operations (inner, left, right, full outer)
- Aggregations (COUNT, SUM, AVG, MIN, MAX, GROUP BY, HAVING)
- SwiftUI integration with `@BlazeQuery` property wrapper
- Distributed sync with ECDH key exchange
- Row-level security (RLS) policies
- Migration tools (SQLite, Core Data, CSV, JSON)
- Comprehensive test suite (907+ tests, 97% coverage)

### Security
- AES-256-GCM encryption by default
- Argon2id key derivation
- Secure Enclave integration (iOS/macOS)
- Perfect forward secrecy for network sync
- Replay attack protection

### Performance
- Sub-millisecond query latency
- Linear scaling with available cores
- Batch insert optimizations
- Query result caching
- Memory-mapped I/O

### Documentation
- Complete API reference
- Architecture documentation
- Security model documentation
- Threat model analysis
- Cryptographic architecture guide
- Performance benchmarks

## [2.0.0] - 2024-XX-XX

### Added
- Initial public release
- Core database functionality
- Basic query system
- Encryption support

---

## Version History

- **2.5.0-alpha**: Current development version with full feature set
- **2.0.0**: Initial stable release

## Types of Changes

- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** for vulnerability fixes

