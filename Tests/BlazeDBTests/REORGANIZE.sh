#!/bin/bash
# Test Reorganization Script
# Moves test files into new logical directory structure

set -e

cd "$(dirname "$0")"

echo "🔧 Reorganizing BlazeDBTests directory..."

# Create new directories
mkdir -p Codec Engine/Core Engine/Integration Stress/Chaos Stress/PropertyBased Performance Fixtures CI Docs

# Move Codec tests
echo "📦 Moving Codec tests..."
mv Encoding/BlazeBinary/*.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryEncoderTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryEdgeCaseTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryExhaustiveVerificationTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryDirectVerificationTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryReliabilityTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryUltimateBulletproofTests.swift Codec/ 2>/dev/null || true
mv Encoding/BlazeBinaryPerformanceTests.swift Codec/ 2>/dev/null || true
mv Fuzz/BlazeBinaryFuzzTests.swift Codec/ 2>/dev/null || true
mv Helpers/CodecValidation.swift Codec/ 2>/dev/null || true

# Move Engine tests
echo "⚙️ Moving Engine tests..."
mv Core/*.swift Engine/Core/ 2>/dev/null || true
mv Integration/*.swift Engine/Integration/ 2>/dev/null || true
# Engine/*.swift already in Engine/

# Move Stress tests
echo "💥 Moving Stress tests..."
mv BlazeDBStressTests.swift Stress/ 2>/dev/null || true
mv Chaos/*.swift Stress/Chaos/ 2>/dev/null || true
mv PropertyBased/*.swift Stress/PropertyBased/ 2>/dev/null || true
mv FailureInjectionTests.swift Stress/ 2>/dev/null || true
mv IOFaultInjectionTests.swift Stress/ 2>/dev/null || true
# Stress/*.swift already in Stress/

# Move Performance tests
echo "⚡ Moving Performance tests..."
mv Benchmarks/*.swift Performance/ 2>/dev/null || true
mv Indexes/SearchPerformanceBenchmarks.swift Performance/ 2>/dev/null || true
# Performance/*.swift already in Performance/

# Move Fixtures
echo "📁 Moving Fixtures..."
mv Engine/FixtureValidationTests.swift Fixtures/ 2>/dev/null || true
# Fixtures/*.swift already in Fixtures/

# Move CI tests
echo "🔄 Moving CI tests..."
mv CIMatrix.swift CI/ 2>/dev/null || true
mv CodecDualPathTestSuite.swift CI/ 2>/dev/null || true

# Move Docs
echo "📚 Moving Docs..."
mv *.md Docs/ 2>/dev/null || true
mv CREATE_TEST_PLANS_IN_XCODE.md Docs/ 2>/dev/null || true
mv TEST_*.md Docs/ 2>/dev/null || true
mv REORGANIZATION_COMPLETE.md Docs/ 2>/dev/null || true

# Clean up empty directories
echo "🧹 Cleaning up empty directories..."
find . -type d -empty -delete 2>/dev/null || true

echo "✅ Reorganization complete!"
echo ""
echo "New structure:"
echo "  Codec/ - BlazeBinary codec tests"
echo "  Engine/ - Engine integration tests"
echo "  Stress/ - Stress and fuzz tests"
echo "  Performance/ - Performance benchmarks"
echo "  Fixtures/ - Test fixtures"
echo "  CI/ - CI-specific tests"
echo "  Docs/ - Documentation"

