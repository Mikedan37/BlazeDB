#!/bin/bash
# BlazeDB Test Runner Script
# Provides convenient shortcuts for running different test suites

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Parse command line arguments
MODE=${1:-all}

case $MODE in
    quick)
        print_status "🚀 Running Quick Tests (< 30s)"
        swift test --parallel --filter '!Stress|!Heavy|!Performance|!Integration'
        print_success "Quick tests complete!"
        ;;
    
    unit)
        print_status "🧪 Running All Unit Tests (907 tests)"
        swift test --parallel --filter BlazeDBTests
        print_success "Unit tests complete!"
        ;;
    
    integration)
        print_status "🔗 Running Integration Tests"
        swift test --parallel --filter BlazeDBIntegrationTests
        print_success "Integration tests complete!"
        ;;
    
    perf)
        print_status "⚡ Running Performance Tests"
        swift test --filter Performance
        swift test --filter Benchmark
        print_success "Performance tests complete!"
        
        # Track performance metrics
        if [ -f "scripts/track_performance.py" ]; then
            print_status "📊 Tracking Performance Metrics"
            python3 scripts/track_performance.py
        fi
        ;;
    
    stress)
        print_status "💪 Running Stress Tests (Heavy Load)"
        export RUN_HEAVY_STRESS=1
        export TEST_SLOW_CONCURRENCY=1
        swift test --filter StressTests
        swift test --filter ConcurrencyTests
        print_success "Stress tests complete!"
        ;;
    
    sanitizer)
        print_status "🔬 Running Sanitizer Tests"
        
        echo "Running with Thread Sanitizer..."
        swift test -Xswiftc -sanitize=thread --filter '!Stress|!Heavy' || {
            print_error "Thread Sanitizer detected issues!"
            exit 1
        }
        
        echo "Running with Address Sanitizer..."
        swift test -Xswiftc -sanitize=address --filter '!Stress|!Heavy' || {
            print_error "Address Sanitizer detected issues!"
            exit 1
        }
        
        print_success "Sanitizer tests complete - No issues found!"
        ;;
    
    coverage)
        print_status "📊 Generating Coverage Report"
        swift test --enable-code-coverage --parallel
        
        xcrun llvm-cov show \
            .build/debug/BlazeDBPackageTests.xctest/Contents/MacOS/BlazeDBPackageTests \
            -instr-profile .build/debug/codecov/default.profdata \
            -format=html \
            -output-dir=coverage_report
        
        print_success "Coverage report generated: coverage_report/index.html"
        open coverage_report/index.html
        ;;
    
    all)
        print_status "🎯 Running COMPLETE Test Suite"
        
        echo ""
        echo "📋 Phase 1: Quick Tests..."
        swift test --parallel --filter '!Stress|!Heavy|!Performance|!Integration'
        print_success "Quick tests passed"
        
        echo ""
        echo "📋 Phase 2: Unit Tests..."
        swift test --parallel --filter BlazeDBTests
        print_success "Unit tests passed (907/907)"
        
        echo ""
        echo "📋 Phase 3: Integration Tests..."
        swift test --parallel --filter BlazeDBIntegrationTests
        print_success "Integration tests passed"
        
        echo ""
        echo "📋 Phase 4: Performance Tests..."
        swift test --filter Performance
        print_success "Performance tests passed"
        
        echo ""
        print_status "✅ ALL TESTS PASSED!"
        ;;
    
    ci)
        print_status "🤖 Running CI Validation (Same as GitHub Actions)"
        
        echo "📋 Running tests..."
        swift test --parallel --filter BlazeDBTests
        swift test --parallel --filter BlazeDBIntegrationTests
        
        echo "📊 Generating coverage..."
        swift test --enable-code-coverage --parallel
        
        echo "🔬 Running thread sanitizer..."
        swift test -Xswiftc -sanitize=thread --filter '!Stress|!Heavy'
        
        print_success "CI validation complete!"
        ;;
    
    help|--help|-h)
        echo "BlazeDB Test Runner"
        echo ""
        echo "Usage: ./scripts/test.sh [MODE]"
        echo ""
        echo "Modes:"
        echo "  quick       - Fast tests only (< 30s)"
        echo "  unit        - All unit tests (907 tests, ~2min)"
        echo "  integration - Integration scenarios (~5min)"
        echo "  perf        - Performance tests with metrics"
        echo "  stress      - Heavy load stress tests (~10min)"
        echo "  sanitizer   - Thread & address sanitizers"
        echo "  coverage    - Generate coverage report"
        echo "  all         - Everything (full suite, ~15min)"
        echo "  ci          - CI validation (same as GitHub Actions)"
        echo ""
        echo "Examples:"
        echo "  ./scripts/test.sh quick      # Fast feedback"
        echo "  ./scripts/test.sh all        # Complete validation"
        echo "  ./scripts/test.sh perf       # Track performance"
        ;;
    
    *)
        print_error "Unknown mode: $MODE"
        echo "Run './scripts/test.sh help' for usage"
        exit 1
        ;;
esac

echo ""
print_success "Done!"

