#!/bin/bash

set -euo pipefail

PROJECT="${1:-BlazeDB.xcodeproj}"
SCHEME="${2:-BlazeDB}"
DESTINATION="${3:-platform=macOS}"

xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk macosx \
  -destination "$DESTINATION" \
  build-for-testing >/tmp/testgov_build_for_testing.log 2>&1 || {
    cat /tmp/testgov_build_for_testing.log >&2
    echo "BUILD_FOR_TESTING_FAILED" >&2
    exit 2
  }

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings \
  | sed -n 's/.*BUILD_DIR = //p' | head -1)

if [ -z "$BUILD_DIR" ]; then
  echo "BUILD_DIR_NOT_FOUND" >&2
  exit 3
fi

COUNT=$(find "$BUILD_DIR" -name "*.xctest" | wc -l | tr -d ' ')
if [ "$COUNT" = "0" ]; then
  echo "NO_TEST_BUNDLES" >&2
  exit 4
fi

echo "build-for-testing smoke: PASS ($COUNT bundles)"
