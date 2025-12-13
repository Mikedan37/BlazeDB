#!/bin/bash
# Test runner with timeout for AI query layer tests

set -e

cd "$(dirname "$0")"

echo "🔵 Building tests..."
swift build 2>&1 | tail -5

echo "🔵 Running AI query layer tests with 60s timeout..."
timeout 60 swift test --filter BlazeDBAIQueryTests 2>&1 || {
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "❌ Tests timed out after 60 seconds"
    else
        echo "❌ Tests failed with exit code $EXIT_CODE"
    fi
    exit $EXIT_CODE
}

echo "✅ All tests completed"

