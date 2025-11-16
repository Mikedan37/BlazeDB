#!/bin/bash
# Quick cleanup script for BlazeDB test files
# Run this anytime to clean up temp directory

echo "🧹 Cleaning BlazeDB test files..."

cd $(dirname $(mktemp -u)) 2>/dev/null || cd /tmp

# Count before
BEFORE=$(ls -1 | grep -E "\.(blazedb|blaze|blz|meta|db)$|^BlazeDB-|^backup_v0_|blazedb\.recovery|^BlazeCorruption-|^BlazeStress-|^PageStoreBoundary-|^testdb|^testListDB|^switch|^cleanup-" | wc -l | tr -d ' ')

echo "📊 Found $BEFORE test files"

if [ "$BEFORE" -eq "0" ]; then
    echo "✅ Already clean!"
    exit 0
fi

# Remove files
rm -f *.blazedb *.blaze *.blz *.meta *.meta.indexes 2>/dev/null
rm -rf BlazeDB-* BlazeCorruption-* BlazeStress-* BlazeFS-* 2>/dev/null
rm -f backup_v0_* blazedb.recovery.* PageStoreBoundary-* 2>/dev/null
rm -f testdb* testListDB* switch* cleanup-* 2>/dev/null

# Count after
AFTER=$(ls -1 | grep -E "\.(blazedb|blaze|blz|meta)$|^BlazeDB-" | wc -l | tr -d ' ')
REMOVED=$((BEFORE - AFTER))

echo "✅ Removed $REMOVED files"
echo "📁 Remaining: $AFTER"
echo "🎉 Done!"

