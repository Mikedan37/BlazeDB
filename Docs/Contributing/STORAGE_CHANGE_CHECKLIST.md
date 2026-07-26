# Storage-change contributor checklist

Use this checklist for any change that touches on-disk format, WAL, page encryption, metadata/layout, recovery, vacuum/GC that rewrites pages, or import/export of native database files.

If unsure whether your change qualifies, assume it does.

## Before coding

- [ ] Read [DURABILITY_MODE_SUPPORT](../Status/DURABILITY_MODE_SUPPORT.md) and the Storage sections of [SYSTEM_MAP](../SYSTEM_MAP.md) / [Architecture](../Architecture/README.md).
- [ ] State whether the change is **compatible** (old files still open) or **requires a format/version bump**.
- [ ] Identify which WAL mode(s) you touch (`legacy` default vs `unified`). Do not mix modes on one file.
- [ ] List the exact failure modes you are trying to prevent or might introduce (torn page, orphan overflow, failed fsync, auth vs corrupt confusion, etc.).

## Required validation (paste commands into the PR)

Run from a clean-enough tree and paste the exact commands:

```bash
./Scripts/preflight.sh
./dev tier0
# Add focused filters for the files you touched, for example:
./dev test BPlusTreeNodeTests.createsSimpleTree   # only if indexing-related
swift test --filter CrashRecoveryTests
swift test --filter BlazeCorruptionRecoveryTests
```

Also run any path-specific suites you know apply (WAL, vacuum, encryption round-trip, migration). Prefer the smallest filter that still covers the failure mode.

## PR description must include

- [ ] What on-disk or recovery behavior changed (or “behavior unchanged; refactor only”).
- [ ] Compatibility impact for existing databases.
- [ ] Exact validation commands and results.
- [ ] Whether benchmarks were run (required if the change is performance-sensitive): prefer `swift build -c release --product BlazeDBBenchmarks` and the methodology in [Docs/Benchmarks](../Benchmarks/README.md).

## Do not

- Weaken assertions to make a suite green.
- Change default durability semantics without an explicit docs update in the same PR.
- Treat Status/Archive docs as the behavior contract when they disagree with `Package.swift`, tests, or DURABILITY_MODE_SUPPORT.

Related: [CONTRIBUTING.md](../../CONTRIBUTING.md), [PRODUCT_AUDIT.md](../Product/PRODUCT_AUDIT.md), [ROADMAP.md](../../ROADMAP.md).
