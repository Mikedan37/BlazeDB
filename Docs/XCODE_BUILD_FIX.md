# Xcode Build Fix: "Cannot build without a run destination"

## Problem

Xcode is showing: "Cannot build 'BlazeDB-Package' without a run destination"

This happens when Xcode doesn't know which platform to build for.

---

## **Solution 1: Select a Run Destination in Xcode**

1. **Open Xcode** and open the BlazeDB package
2. **Look at the top toolbar** - you'll see a device/simulator selector
3. **Click the device selector** (next to the play/stop buttons)
4. **Select a destination:**
 - **"My Mac"** (for macOS)
 - **Any iOS Simulator** (for iOS testing)
 - **Any available device**

5. **Now try building again** (Cmd+B)

---

## **Solution 2: Build a Specific Target**

Instead of building the package, build a specific target:

1. **In Xcode**, go to **Product → Scheme → Manage Schemes...**
2. **Select a scheme** (e.g., "BlazeDB" library, "BlazeShell", "BlazeServer")
3. **Click "Build"** (Cmd+B)

Or use the scheme selector in the toolbar (next to the device selector).

---

## **Solution 3: Build from Command Line (Recommended)**

If Xcode is giving you trouble, use the command line:

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB

# Clean first
swift package clean

# Build the library
swift build

# Or build a specific executable
swift build --product BlazeShell
swift build --product BlazeServer
swift build --product BlazeMCP
```

**Note:** If you see `SWBBuildService` errors, you may need to use Xcode's toolchain instead:

```bash
# Use Xcode's Swift (if installed)
xcodebuild -scheme BlazeDB -destination 'platform=macOS'
```

---

## **Solution 4: Create an Xcode Project File**

If you want to use Xcode's GUI, you can generate an Xcode project:

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
swift package generate-xcodeproj
```

Then open the generated `.xcodeproj` file in Xcode.

**Note:** `generate-xcodeproj` is deprecated in newer Swift versions. Modern approach is to open the package directly in Xcode (File → Open → select the folder containing `Package.swift`).

---

## **Solution 5: Open Package Directly in Xcode**

1. **Close Xcode** (if open)
2. **Navigate to** `/Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB`
3. **Double-click** `Package.swift` (or right-click → Open With → Xcode)
4. **Xcode will open the package** with proper scheme configuration
5. **Select a destination** from the toolbar
6. **Build** (Cmd+B)

---

## **Why This Happens**

Swift Packages don't have a default run destination like Xcode projects do. Xcode needs to know:
- **What platform** to build for (macOS, iOS, Linux)
- **What architecture** (x86_64, arm64, etc.)

When you select a destination, Xcode knows these details and can build correctly.

---

## **Recommended Approach**

For Swift Packages, the **command line** is often more reliable:

```bash
swift build
```

This builds for your current platform automatically and doesn't require destination selection.

---

**Last Updated:** 2025-01-XX

