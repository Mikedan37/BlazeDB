#!/bin/bash
# Diagnostic script to check what's using System Data space
# Run this to see where your disk space is going

echo "🔍 Checking System Data Usage..."
echo "=================================="
echo ""

echo "📦 Xcode DerivedData:"
if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "📱 iOS Simulator:"
if [ -d ~/Library/Developer/CoreSimulator ]; then
    du -sh ~/Library/Developer/CoreSimulator 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "📦 Xcode Archives:"
if [ -d ~/Library/Developer/Xcode/Archives ]; then
    du -sh ~/Library/Developer/Xcode/Archives 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "📱 iOS Device Support:"
if [ -d ~/Library/Developer/Xcode/iOS\ DeviceSupport ]; then
    du -sh ~/Library/Developer/Xcode/iOS\ DeviceSupport 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "💾 iOS Backups:"
if [ -d ~/Library/Application\ Support/MobileSync ]; then
    du -sh ~/Library/Application\ Support/MobileSync 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "🗂️  Caches:"
if [ -d ~/Library/Caches ]; then
    du -sh ~/Library/Caches 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "📋 Logs:"
if [ -d ~/Library/Logs ]; then
    du -sh ~/Library/Logs 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "📦 Containers:"
if [ -d ~/Library/Containers ]; then
    du -sh ~/Library/Containers 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "☁️  iCloud Drive Cache:"
if [ -d ~/Library/Application\ Support/CloudDocs ]; then
    du -sh ~/Library/Application\ Support/CloudDocs 2>/dev/null
else
    echo "  Not found"
fi
echo ""

echo "🗄️  Time Machine Local Snapshots:"
tmutil listlocalsnapshots / 2>/dev/null | head -5
if [ $? -ne 0 ]; then
    echo "  No snapshots or Time Machine not configured"
fi
echo ""

echo "🧪 Test Database Files in /tmp:"
find /tmp -name "*blazedb*" -o -name "*BlazeDB*" 2>/dev/null | wc -l | xargs echo "  Found files:"
echo ""

echo "🧪 Test Database Files in Project:"
if [ -d ~/Developer/ProjectBlaze/BlazeDB ]; then
    find ~/Developer/ProjectBlaze/BlazeDB -name "*.blazedb" -type f 2>/dev/null | wc -l | xargs echo "  Found files:"
else
    echo "  Project directory not found"
fi
echo ""

echo "🐳 Docker (if installed):"
docker system df 2>/dev/null || echo "  Docker not installed or not running"
echo ""

echo "=================================="
echo "✅ Diagnostic complete!"
echo ""
echo "💡 Tips:"
echo "  - Xcode DerivedData can usually be safely deleted"
echo "  - iOS Simulator data can be cleaned via Xcode > Devices"
echo "  - Time Machine snapshots are auto-managed but can be deleted"
echo "  - Test database files in /tmp are usually auto-cleaned"

