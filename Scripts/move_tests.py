#!/usr/bin/env python3
import os
import shutil
from pathlib import Path

base = Path("/Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB")
tests_dest = base / "Tests" / "BlazeDBTests"

# Create directories
for d in ["Codec", "Engine", "Stress", "Performance", "Fixtures", "CI", "Docs", "Helpers"]:
    (tests_dest / d).mkdir(parents=True, exist_ok=True)

moved_files = []
cleaned_dirs = []

# Move Codec tests
codec_sources = [
    "BlazeDBTests/Encoding/BlazeBinary",
    "BlazeDBTests/Encoding",
    "BlazeDBTests/Fuzz",
    "BlazeDBTests/Codec"
]
for src_dir in codec_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*Tests.swift"):
            dest = tests_dest / "Codec" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")
        for f in src.rglob("CodecValidation.swift"):
            dest = tests_dest / "Helpers" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move Engine tests
engine_sources = [
    "BlazeDBTests/Engine",
    "BlazeDBTests/Core",
    "BlazeDBTests/Integration",
    "BlazeDBTests/Aggregation",
    "BlazeDBTests/Concurrency",
    "BlazeDBTests/DataTypes",
    "BlazeDBTests/EdgeCases",
    "BlazeDBTests/Features",
    "BlazeDBTests/GarbageCollection",
    "BlazeDBTests/Indexes",
    "BlazeDBTests/MVCC",
    "BlazeDBTests/Migration",
    "BlazeDBTests/Overflow",
    "BlazeDBTests/Persistence",
    "BlazeDBTests/Query",
    "BlazeDBTests/Recovery",
    "BlazeDBTests/Security",
    "BlazeDBTests/SQL",
    "BlazeDBTests/Sync",
    "BlazeDBTests/Transactions",
    "BlazeDBTests/Backup",
    "BlazeDBTests/ModelBased"
]
for src_dir in engine_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*Tests.swift"):
            dest = tests_dest / "Engine" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move Stress tests
stress_sources = [
    "BlazeDBTests/Stress",
    "BlazeDBTests/Chaos",
    "BlazeDBTests/PropertyBased"
]
for src_dir in stress_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*Tests.swift"):
            dest = tests_dest / "Stress" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move Performance tests
perf_sources = [
    "BlazeDBTests/Performance",
    "BlazeDBTests/Benchmarks"
]
for src_dir in perf_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*Tests.swift"):
            dest = tests_dest / "Performance" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")
        for f in src.rglob("*Benchmarks.swift"):
            dest = tests_dest / "Performance" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move Fixtures
fixture_sources = [
    "BlazeDBTests/Fixtures"
]
for src_dir in fixture_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*.swift"):
            dest = tests_dest / "Fixtures" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move CI tests
ci_sources = [
    "BlazeDBTests/CI"
]
for src_dir in ci_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*.swift"):
            dest = tests_dest / "CI" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Move root-level test files
root_tests = [
    "BlazeDBTests/BlazeDBStressTests.swift",
    "BlazeDBTests/BlazePaginationTests.swift",
    "BlazeDBTests/DataSeedingTests.swift",
    "BlazeDBTests/EnhancedErrorMessagesTests.swift",
    "BlazeDBTests/FailureInjectionTests.swift",
    "BlazeDBTests/IOFaultInjectionTests.swift",
    "BlazeDBTests/QueryCacheTests.swift",
    "BlazeDBTests/SchemaValidationTests.swift",
    "BlazeDBTests/CodecDualPathTestSuite.swift",
    "BlazeDBTests/CIMatrix.swift"
]
for f_path in root_tests:
    f = base / f_path
    if f.exists():
        if "Stress" in f_path or "Chaos" in f_path or "Fault" in f_path:
            dest = tests_dest / "Stress" / f.name
        elif "Performance" in f_path or "Benchmark" in f_path:
            dest = tests_dest / "Performance" / f.name
        elif "CI" in f_path or "CodecDualPath" in f_path:
            dest = tests_dest / "CI" / f.name
        else:
            dest = tests_dest / "Engine" / f.name
        if not dest.exists():
            shutil.move(str(f), str(dest))
            moved_files.append(f"{f} -> {dest}")

# Move Helpers
helper_sources = [
    "BlazeDBTests/Helpers",
    "BlazeDBTests/Utilities",
    "BlazeDBTests/Testing"
]
for src_dir in helper_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*.swift"):
            if "Tests.swift" not in f.name:
                dest = tests_dest / "Helpers" / f.name
                if not dest.exists():
                    shutil.move(str(f), str(dest))
                    moved_files.append(f"{f} -> {dest}")

# Move Docs
doc_sources = [
    "BlazeDBTests"
]
for src_dir in doc_sources:
    src = base / src_dir
    if src.exists():
        for f in src.rglob("*.md"):
            dest = tests_dest / "Docs" / f.name
            if not dest.exists():
                shutil.move(str(f), str(dest))
                moved_files.append(f"{f} -> {dest}")

# Clean up empty directories
for d in base.rglob("*"):
    if d.is_dir() and d.name in ["Encoding", "Integration", "Core", "Chaos", "Benchmarks", "Stress", "PropertyBased", "Performance", "Fixtures", "CI", "Helpers", "Utilities", "Testing", "Fuzz", "Codec", "Engine", "Aggregation", "Concurrency", "DataTypes", "EdgeCases", "Features", "GarbageCollection", "Indexes", "MVCC", "Migration", "Overflow", "Persistence", "Query", "Recovery", "Security", "SQL", "Sync", "Transactions", "Backup", "ModelBased"]:
        try:
            if not any(d.iterdir()):
                d.rmdir()
                cleaned_dirs.append(str(d))
        except:
            pass

print(f"Moved {len(moved_files)} files")
print(f"Cleaned {len(cleaned_dirs)} directories")

