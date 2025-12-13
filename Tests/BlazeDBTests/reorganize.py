#!/usr/bin/env python3
"""
Test Reorganization Script
Moves test files into new logical directory structure
"""

import os
import shutil
from pathlib import Path

def ensure_dir(path):
    """Create directory if it doesn't exist"""
    Path(path).mkdir(parents=True, exist_ok=True)

def move_file(src, dst):
    """Move file from src to dst, creating directories as needed"""
    if os.path.exists(src):
        ensure_dir(os.path.dirname(dst))
        shutil.move(src, dst)
        print(f"✅ Moved: {src} → {dst}")
    else:
        print(f"⚠️  Not found: {src}")

def main():
    base = Path(__file__).parent
    
    # Create new directories
    print("📁 Creating directories...")
    for dir_name in ["Codec", "Engine/Core", "Engine/Integration", "Stress/Chaos", 
                     "Stress/PropertyBased", "Performance", "Fixtures", "CI", "Docs"]:
        ensure_dir(base / dir_name)
    
    # Move Codec tests
    print("\n📦 Moving Codec tests...")
    codec_moves = [
        ("Encoding/BlazeBinary/BlazeBinaryCompatibilityTests.swift", "Codec/BlazeBinaryCompatibilityTests.swift"),
        ("Encoding/BlazeBinary/BlazeBinaryCorruptionRecoveryTests.swift", "Codec/BlazeBinaryCorruptionRecoveryTests.swift"),
        ("Encoding/BlazeBinary/BlazeBinaryFieldViewTests.swift", "Codec/BlazeBinaryFieldViewTests.swift"),
        ("Encoding/BlazeBinary/BlazeBinaryLargeRecordTests.swift", "Codec/BlazeBinaryLargeRecordTests.swift"),
        ("Encoding/BlazeBinary/BlazeBinaryMMapTests.swift", "Codec/BlazeBinaryMMapTests.swift"),
        ("Encoding/BlazeBinary/BlazeBinaryPointerIntegrityTests.swift", "Codec/BlazeBinaryPointerIntegrityTests.swift"),
        ("Encoding/BlazeBinaryEncoderTests.swift", "Codec/BlazeBinaryEncoderTests.swift"),
        ("Encoding/BlazeBinaryEdgeCaseTests.swift", "Codec/BlazeBinaryEdgeCaseTests.swift"),
        ("Encoding/BlazeBinaryExhaustiveVerificationTests.swift", "Codec/BlazeBinaryExhaustiveVerificationTests.swift"),
        ("Encoding/BlazeBinaryDirectVerificationTests.swift", "Codec/BlazeBinaryDirectVerificationTests.swift"),
        ("Encoding/BlazeBinaryReliabilityTests.swift", "Codec/BlazeBinaryReliabilityTests.swift"),
        ("Encoding/BlazeBinaryUltimateBulletproofTests.swift", "Codec/BlazeBinaryUltimateBulletproofTests.swift"),
        ("Encoding/BlazeBinaryPerformanceTests.swift", "Codec/BlazeBinaryPerformanceTests.swift"),
        ("Fuzz/BlazeBinaryFuzzTests.swift", "Codec/BlazeBinaryFuzzTests.swift"),
        ("Helpers/CodecValidation.swift", "Codec/CodecValidation.swift"),
    ]
    
    for src, dst in codec_moves:
        move_file(base / src, base / dst)
    
    # Move Engine tests
    print("\n⚙️ Moving Engine tests...")
    engine_moves = []
    # Core files
    if (base / "Core").exists():
        for f in (base / "Core").glob("*.swift"):
            move_file(f, base / "Engine/Core" / f.name)
    # Integration files
    if (base / "Integration").exists():
        for f in (base / "Integration").glob("*.swift"):
            move_file(f, base / "Engine/Integration" / f.name)
    
    # Move Stress tests
    print("\n💥 Moving Stress tests...")
    stress_moves = [
        ("BlazeDBStressTests.swift", "Stress/BlazeDBStressTests.swift"),
        ("FailureInjectionTests.swift", "Stress/FailureInjectionTests.swift"),
        ("IOFaultInjectionTests.swift", "Stress/IOFaultInjectionTests.swift"),
    ]
    for src, dst in stress_moves:
        move_file(base / src, base / dst)
    
    # Move Chaos tests
    if (base / "Chaos").exists():
        for f in (base / "Chaos").glob("*.swift"):
            move_file(f, base / "Stress/Chaos" / f.name)
    
    # Move PropertyBased tests
    if (base / "PropertyBased").exists():
        for f in (base / "PropertyBased").glob("*.swift"):
            move_file(f, base / "Stress/PropertyBased" / f.name)
    
    # Move Performance tests
    print("\n⚡ Moving Performance tests...")
    if (base / "Benchmarks").exists():
        for f in (base / "Benchmarks").glob("*.swift"):
            move_file(f, base / "Performance" / f.name)
    
    if (base / "Indexes/SearchPerformanceBenchmarks.swift").exists():
        move_file(base / "Indexes/SearchPerformanceBenchmarks.swift", 
                 base / "Performance/SearchPerformanceBenchmarks.swift")
    
    # Move Fixtures
    print("\n📁 Moving Fixtures...")
    if (base / "Engine/FixtureValidationTests.swift").exists():
        move_file(base / "Engine/FixtureValidationTests.swift", 
                 base / "Fixtures/FixtureValidationTests.swift")
    
    # Move CI tests
    print("\n🔄 Moving CI tests...")
    ci_moves = [
        ("CIMatrix.swift", "CI/CIMatrix.swift"),
        ("CodecDualPathTestSuite.swift", "CI/CodecDualPathTestSuite.swift"),
    ]
    for src, dst in ci_moves:
        move_file(base / src, base / dst)
    
    # Move Docs
    print("\n📚 Moving Docs...")
    for md_file in base.glob("*.md"):
        if md_file.name not in ["REORGANIZATION_COMPLETE.md", "REORGANIZATION_PLAN.md", "REORGANIZE.sh"]:
            move_file(md_file, base / "Docs" / md_file.name)
    
    # Clean up empty directories
    print("\n🧹 Cleaning up empty directories...")
    for root, dirs, files in os.walk(base, topdown=False):
        try:
            if not os.listdir(root):
                os.rmdir(root)
                print(f"🗑️  Removed empty directory: {root}")
        except OSError:
            pass
    
    print("\n✅ Reorganization complete!")

if __name__ == "__main__":
    main()

