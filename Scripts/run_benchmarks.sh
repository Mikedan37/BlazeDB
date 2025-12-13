#!/bin/bash
# Run BlazeDB Performance Benchmarks and Extract Results
# This script runs benchmarks and extracts actual measured performance numbers

set -e

echo "🚀 Running BlazeDB Performance Benchmarks..."
echo ""

# Create output directory
mkdir -p benchmark_results
OUTPUT_FILE="benchmark_results/performance_results_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "=========================================="
    echo "BlazeDB Performance Benchmark Results"
    echo "Generated: $(date)"
    echo "=========================================="
    echo ""
    
    echo "📊 Running Comprehensive Benchmarks..."
    echo "----------------------------------------"
    swift test --filter ComprehensiveBenchmarks 2>&1 | tee -a "$OUTPUT_FILE"
    
    echo ""
    echo "📊 Running Performance Benchmarks..."
    echo "----------------------------------------"
    swift test --filter PerformanceBenchmarks 2>&1 | tee -a "$OUTPUT_FILE"
    
    echo ""
    echo "📊 Running Baseline Tests..."
    echo "----------------------------------------"
    BLAZEDB_RUN_BASELINE_TESTS=1 swift test --filter BaselinePerformanceTests 2>&1 | tee -a "$OUTPUT_FILE"
    
    echo ""
    echo "=========================================="
    echo "Benchmark Results Summary"
    echo "=========================================="
    echo ""
    
    # Extract key metrics from output
    echo "Extracting key metrics..."
    grep -E "(ops/sec|ms|Time:|Throughput:|BENCHMARK|BASELINE)" "$OUTPUT_FILE" || echo "No metrics found in output"
    
    echo ""
    echo "Full results saved to: $OUTPUT_FILE"
    echo ""
    
    # Check for JSON results
    if [ -d ".build/test-metrics" ]; then
        echo "📄 JSON metrics found in .build/test-metrics/"
        ls -lh .build/test-metrics/*.json 2>/dev/null || echo "No JSON files found"
    fi
    
    if [ -f "/tmp/blazedb_baselines.json" ]; then
        echo "📄 Baseline results found in /tmp/blazedb_baselines.json"
        cat /tmp/blazedb_baselines.json
    fi
    
} | tee "$OUTPUT_FILE"

echo ""
echo "✅ Benchmarks complete! Results saved to: $OUTPUT_FILE"


