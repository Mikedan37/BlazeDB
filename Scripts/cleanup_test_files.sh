#!/bin/bash
# cleanup_test_files.sh
# Cleans up BlazeDB test files from temporary directory

echo "🧹 Cleaning BlazeDB test files from temp directory..."

TEMP_DIR=$(mktemp -d)/..  # Get temp directory path
cd "$TEMP_DIR" || exit 1

# Count files before
BEFORE=$(find . -maxdepth 1 \( \
    -name "*.blazedb" -o \
    -name "*.blaze" -o \
    -name "*.blz" -o \
    -name "*.meta" -o \
    -name "*.meta.indexes" -o \
    -name "BlazeDB-*" -o \
    -name "BlazeStress-*" -o \
    -name "BlazeCorruption-*" -o \
    -name "BlazeFS-*" -o \
    -name "blazedb.recovery.*" -o \
    -name "backup_v0_*" -o \
    -name "cleanup-*" -o \
    -name "PageStoreBoundary-*" -o \
    -name "switch*" \
\) 2>/dev/null | wc -l)

echo "📊 Found $BEFORE BlazeDB test files"

if [ "$BEFORE" -eq 0 ]; then
    echo "✅ No cleanup needed"
    exit 0
fi

# Remove BlazeDB test files
find . -maxdepth 1 \( \
    -name "*.blazedb" -o \
    -name "*.blaze" -o \
    -name "*.blz" -o \
    -name "*.meta" -o \
    -name "*.meta.indexes" -o \
    -name "*.db" -o \
    -name "BlazeDB-*" -o \
    -name "BlazeStress-*" -o \
    -name "BlazeCorruption-*" -o \
    -name "BlazeFS-*" -o \
    -name "blazedb.recovery.*" -o \
    -name "backup_v0_*" -o \
    -name "cleanup-*" -o \
    -name "PageStoreBoundary-*" -o \
    -name "testListDB*" -o \
    -name "testdb*" -o \
    -name "switch*" -o \
    -name "*-????-*" \
\) -exec rm -rf {} + 2>/dev/null

# Count files after
AFTER=$(find . -maxdepth 1 \( \
    -name "*.blazedb" -o \
    -name "*.blaze" -o \
    -name "*.meta" \
\) 2>/dev/null | wc -l)

REMOVED=$((BEFORE - AFTER))

echo "✅ Cleaned up $REMOVED test files"
echo "📁 Remaining: $AFTER"

if [ "$AFTER" -gt 0 ]; then
    echo "⚠️  Some files may still remain (check permissions)"
fi

echo "🎉 Cleanup complete!"

