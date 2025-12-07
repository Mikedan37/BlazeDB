#!/bin/bash
#
# Generate Code Coverage Report for BlazeDB
#
# Usage: ./scripts/generate_coverage_report.sh
#

set -e

echo "🔍 Generating Code Coverage Report for BlazeDB..."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Run tests with coverage
echo "📊 Running tests with code coverage enabled..."
swift test --enable-code-coverage

# Find the test binary
TEST_BINARY=$(find .build/debug -name "BlazeDBPackageTests.xctest" -type d | head -1)
if [ -z "$TEST_BINARY" ]; then
    echo "${RED}❌ Could not find test binary${NC}"
    exit 1
fi

TEST_EXECUTABLE="$TEST_BINARY/Contents/MacOS/BlazeDBPackageTests"
PROFDATA=".build/debug/codecov/default.profdata"

if [ ! -f "$PROFDATA" ]; then
    echo "${RED}❌ Could not find profdata file${NC}"
    exit 1
fi

echo "${GREEN}✅ Found test binary and profdata${NC}"
echo ""

# Generate coverage report
echo "📈 Generating coverage report..."
xcrun llvm-cov report "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    -use-color

echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Generate detailed coverage by file
echo "📊 Coverage by file:"
xcrun llvm-cov report "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    | grep "BlazeDB/" \
    | sort -k10 -n

echo ""
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Extract overall coverage percentage
COVERAGE=$(xcrun llvm-cov report "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    | grep "TOTAL" \
    | awk '{print $NF}' \
    | tr -d '%')

echo "📊 Overall Coverage: ${GREEN}${COVERAGE}%${NC}"

# Determine status
if (( $(echo "$COVERAGE >= 80" | bc -l) )); then
    echo "${GREEN}✅ Excellent coverage (>= 80%)${NC}"
elif (( $(echo "$COVERAGE >= 70" | bc -l) )); then
    echo "${YELLOW}⚠️  Good coverage (>= 70%)${NC}"
elif (( $(echo "$COVERAGE >= 60" | bc -l) )); then
    echo "${YELLOW}⚠️  Fair coverage (>= 60%)${NC}"
else
    echo "${RED}❌ Low coverage (< 60%) - Consider adding more tests${NC}"
fi

echo ""

# Generate HTML report
echo "📄 Generating HTML report..."
OUTPUT_DIR="coverage_report"
mkdir -p "$OUTPUT_DIR"

xcrun llvm-cov show "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    -format=html \
    -output-dir="$OUTPUT_DIR" \
    -Xdemangler c++filt \
    -Xdemangler -n

echo "${GREEN}✅ HTML report generated in: $OUTPUT_DIR/index.html${NC}"
echo ""

# Generate LCOV format for CI
echo "📄 Generating LCOV report for CI..."
xcrun llvm-cov export "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    -format=lcov > coverage.lcov

echo "${GREEN}✅ LCOV report generated: coverage.lcov${NC}"
echo ""

# Find uncovered lines
echo "🔍 Finding uncovered code..."
UNCOVERED=$(xcrun llvm-cov report "$TEST_EXECUTABLE" \
    -instr-profile="$PROFDATA" \
    -ignore-filename-regex=".*Tests.swift" \
    | grep "BlazeDB/" \
    | awk '{if ($NF+0 < 100) print $0}' \
    | wc -l | tr -d ' ')

echo "${YELLOW}⚠️  Files with < 100% coverage: $UNCOVERED${NC}"
echo ""

# Coverage badge
if (( $(echo "$COVERAGE >= 90" | bc -l) )); then
    BADGE_COLOR="brightgreen"
elif (( $(echo "$COVERAGE >= 80" | bc -l) )); then
    BADGE_COLOR="green"
elif (( $(echo "$COVERAGE >= 70" | bc -l) )); then
    BADGE_COLOR="yellowgreen"
elif (( $(echo "$COVERAGE >= 60" | bc -l) )); then
    BADGE_COLOR="yellow"
else
    BADGE_COLOR="red"
fi

echo "📛 Coverage Badge:"
echo "[![Coverage](https://img.shields.io/badge/coverage-${COVERAGE}%25-${BADGE_COLOR})](./coverage_report/index.html)"
echo ""

echo "${GREEN}✅ Coverage report generation complete!${NC}"
echo ""
echo "Open: ${BLUE}$OUTPUT_DIR/index.html${NC} to view detailed report"

