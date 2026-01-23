#!/bin/bash
# Check that frozen core files have not been modified
# Fails CI if any frozen files are changed

set -e

# Default to comparing against HEAD^ (previous commit)
# Can be overridden: ./check-freeze.sh HEAD~5
BASE_REF="${1:-HEAD^}"

echo "Checking frozen core files against $BASE_REF..."

# Frozen core files (from PHASE_1_FREEZE.md)
FROZEN_FILES=(
    "BlazeDB/Storage/PageStore.swift"
    "BlazeDB/Storage/WriteAheadLog.swift"
    "BlazeDB/Storage/PageCache.swift"
    "BlazeDB/Core/DynamicCollection.swift"
    "BlazeDB/Utils/BlazeBinaryEncoder.swift"
    "BlazeDB/Utils/BlazeBinaryDecoder.swift"
)

MODIFIED_FILES=()

# Check each frozen file
for file in "${FROZEN_FILES[@]}"; do
    if git diff --name-only "$BASE_REF" HEAD | grep -q "^$file$"; then
        MODIFIED_FILES+=("$file")
    fi
done

# Report results
if [ ${#MODIFIED_FILES[@]} -eq 0 ]; then
    echo "✓ All frozen core files are unchanged"
    exit 0
else
    echo "ERROR: Frozen core files have been modified:"
    for file in "${MODIFIED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "Frozen core files must not be modified except for critical bugfixes."
    echo "See Docs/Compliance/PHASE_1_FREEZE.md for details."
    exit 1
fi
