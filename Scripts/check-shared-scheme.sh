#!/bin/bash

set -euo pipefail

SCHEME_PATH="BlazeDB.xcodeproj/xcshareddata/xcschemes/BlazeDB.xcscheme"

if [ ! -f "$SCHEME_PATH" ]; then
  echo "SHARED_SCHEME_MISSING: $SCHEME_PATH" >&2
  exit 1
fi

echo "shared scheme check: PASS"
