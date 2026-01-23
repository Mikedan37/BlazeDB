# Test Runner Debugging Guide

## **Issue: Tests Don't Run (0 passed, 0 failed, 0.01s)**

This means xcodebuild failed to execute the test suite. Here's how to fix it:

---

## **Quick Fixes (Try These First)**

### **1. Make Sure BlazeDB Scheme is Shared**

```
In Xcode:
1. Open BlazeDB.xcodeproj
2. Product → Scheme → Manage Schemes...
3. Check "Shared" next to "BlazeDB" scheme
4. Close and rebuild BlazeDBVisualizer
```

This ensures the scheme is available to xcodebuild.

---

### **2. Test the Command Manually**

Open Terminal and run:

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
xcodebuild test -scheme BlazeDB -destination 'platform=macOS'
```

**If this works:** The issue is with how BlazeDBVisualizer calls xcodebuild.

**If this fails:** Fix the BlazeDB project first:
- Check that BlazeDB scheme exists
- Make sure scheme is set to "Run" tests
- Verify test targets are included

---

### **3. Check Console.app for Errors**

```
1. Open /Applications/Utilities/Console.app
2. Search for "xcodebuild" or "BlazeDBVisualizer"
3. Look for error messages
4. Common errors:
 - "Scheme BlazeDB is not configured"
 - "Unable to find scheme"
 - "Build failed"
```

---

### **4. Run Tests Directly in Xcode**

```
Fastest method:
1. Open BlazeDB.xcodeproj in Xcode
2. Press ⌘U (Run Tests)
3. See if tests execute
4. Fix any issues there first
```

---

## **Common Issues & Solutions**

### **Issue 1: Scheme Not Found**

**Error:** `Unable to find a scheme named 'BlazeDB'`

**Solution:**
```
1. Open BlazeDB.xcodeproj
2. Product → Scheme → BlazeDB
3. Edit Scheme...
4. Check that "Test" action includes test targets
5. Check "Shared" checkbox
6. File → Save
```

---

### **Issue 2: Xcode Not Installed**

**Error:** `xcodebuild: command not found`

**Solution:**
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Or set path to Xcode
sudo xcode-select --switch /Applications/Xcode.app
```

---

### **Issue 3: Sandbox Restrictions**

**Error:** Process doesn't start or exits immediately

**Solution:**
Already fixed! Entitlements have:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

---

### **Issue 4: Project Path Wrong**

**Error:** `The project named "BlazeDB" was not found`

**Solution:**
Check the path in `TestRunnerView.swift`:
```swift
process.currentDirectoryURL = URL(fileURLWithPath: "/Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB")
```

Make sure this matches YOUR actual project location!

---

## **Debugging Steps**

### **Step 1: Check if xcodebuild works**

```bash
which xcodebuild
# Should output: /usr/bin/xcodebuild

xcodebuild -version
# Should output: Xcode version
```

---

### **Step 2: Check if scheme exists**

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
xcodebuild -list
```

**Expected output:**
```
Schemes:
 BlazeDB
```

---

### **Step 3: Try running tests manually**

```bash
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
xcodebuild test -scheme BlazeDB -destination 'platform=macOS' | head -50
```

**If this works:** Tests will start running!

**If this fails:** Fix the error shown, then try again.

---

### **Step 4: Check Console.app Output**

When you click "Run Tests" in BlazeDBVisualizer:

```
1. Open Console.app
2. Click "Start" to begin streaming
3. Search for "xcodebuild" or "BlazeDBVisualizer"
4. Look for these debug lines:
 Executing: xcodebuild test -scheme BlazeDB -destination platform=macOS
 Working directory: /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
 xcodebuild started successfully

 OR

 xcodebuild error output: [error details]
```

---

## **Alternative: Run Tests in Xcode**

**Easiest solution:**

```
1. Open BlazeDB.xcodeproj in Xcode
2. Press ⌘U (Product → Test)
3. Tests run in Xcode Test Navigator
4. See live results
```

**This always works and gives you:**
- Real-time test execution
- Test failures with stack traces
- Performance metrics
- Test coverage reports

---

## **Future Enhancement**

If xcodebuild doesn't work from BlazeDBVisualizer, we could:

1. **Show Recent Test Results**
 - Parse test results from DerivedData
 - Display last run results

2. **Open in Xcode Button**
 - One-click to open project
 - Run tests there

3. **Alternative Test Runner**
 - Use `swift test` instead
 - Or parse test logs from file

---

## **What the Test Runner Does**

When it works correctly:

```
1. Executes: xcodebuild test -scheme BlazeDB
2. Parses live output:
 "Test Suite 'BlazeDBTests' started..."
 "Test Case 'testInsert' passed (0.002 seconds)"
 "Test Case 'testUpdate' passed (0.001 seconds)"

3. Updates UI in real-time:
 Progress: [] 45%
 Running: "AggregationTests"
 412 / 907 tests
 405 Passed
 7 Failed
 ⏱ 48.5s

4. Shows final results:
 893 PASSED
 14 FAILED
 98.5% Pass Rate
 ⏱ Completed in 127.3s
```

---

## **Recommended Workflow**

**For now, use Xcode directly:**

```
1. Open BlazeDB.xcodeproj
2. Press ⌘U
3. Watch tests run
4. Check Test Navigator for results
```

**Once working, try BlazeDBVisualizer test runner again!**

---

## **Diagnostic Commands**

Run these to diagnose:

```bash
# Check xcodebuild exists
which xcodebuild

# Check Xcode version
xcodebuild -version

# List schemes
cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB
xcodebuild -list

# Test command (copy from Console output)
xcodebuild test -scheme BlazeDB -destination 'platform=macOS'

# Check for derived data issues
rm -rf ~/Library/Developer/Xcode/DerivedData/BlazeDB-*
```

---

## **The Goal**

When working, you'll see:

```
BlazeDB Test Suite Runner

Running tests... [Cancel]
Progress:  82%

Running: "PerformanceTests"
745 / 907 tests

 738 Passed
 7 Failed
⏱ 94.2s
```

Then beautiful results with category breakdown!

---

**Check Console.app now for xcodebuild output to see what went wrong!**

