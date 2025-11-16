//
//  TestRunnerView.swift
//  BlazeDBVisualizer
//
//  Run BlazeDB test suite and show results
//  ✅ Test execution
//  ✅ Live progress
//  ✅ Results breakdown (read, write, telemetry)
//  ✅ Performance metrics
//
//  Created by Michael Danylchuk on 11/14/25.
//

import SwiftUI
import AppKit

struct TestRunnerView: View {
    @StateObject private var runner = TestRunner()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundStyle(.mint.gradient)
                
                Text("Test Suite Information")
                    .font(.title2.bold())
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Always show test categories
            testCategoriesView
        }
    }
    
    // MARK: - Test Categories View
    
    private var testCategoriesView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)
                
                Image(systemName: "flask")
                    .font(.system(size: 60))
                    .foregroundStyle(.mint.gradient)
                
                VStack(spacing: 8) {
                    Text("BlazeDB Test Suite")
                        .font(.title.bold())
                    
                    Text("907 comprehensive tests across 8 categories")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    Text("Validates database health, performance, and reliability")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                // Test Categories (REAL BlazeDB test breakdown!)
                VStack(spacing: 10) {
                    TestCategoryCard(
                        title: "Unit Tests",
                        icon: "doc.text",
                        testCount: 437,
                        description: "Core functionality, data operations, queries"
                    )
                    
                    TestCategoryCard(
                        title: "Integration Tests",
                        icon: "arrow.triangle.merge",
                        testCount: 19,
                        description: "Multi-database, RLS, feature combinations"
                    )
                    
                    TestCategoryCard(
                        title: "MVCC Tests",
                        icon: "arrow.triangle.branch",
                        testCount: 67,
                        description: "Concurrency, transactions, garbage collection"
                    )
                    
                    TestCategoryCard(
                        title: "Binary Format Tests",
                        icon: "01.square",
                        testCount: 48,
                        description: "BlazeBinary encoding, CRC32, performance"
                    )
                    
                    TestCategoryCard(
                        title: "Chaos Engineering",
                        icon: "tornado",
                        testCount: 7,
                        description: "Crash simulation, corruption, recovery"
                    )
                    
                    TestCategoryCard(
                        title: "Property-Based Tests",
                        icon: "function",
                        testCount: 15,
                        description: "Fuzzing, random inputs, edge cases"
                    )
                    
                    TestCategoryCard(
                        title: "Performance Tests",
                        icon: "speedometer",
                        testCount: 45,
                        description: "Benchmarks, profiling, optimization"
                    )
                    
                    TestCategoryCard(
                        title: "Baseline Tests",
                        icon: "chart.bar",
                        testCount: 269,
                        description: "Regression detection, performance tracking"
                    )
                }
                .padding(.horizontal, 32)
                
                // Run button
                VStack(spacing: 12) {
                    Button(action: {
                        openInXcode()
                    }) {
                        HStack {
                            Image(systemName: "hammer.fill")
                            Text("Run Tests in Xcode")
                                .fontWeight(.semibold)
                        }
                        .frame(width: 300)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .controlSize(.large)
                    
                    VStack(spacing: 6) {
                        Text("Opens BlazeDB.xcodeproj in Xcode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Press ⌘U to run all 907 tests (takes 2-3 minutes)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
    
    private func openInXcode() {
        let projectURL = URL(fileURLWithPath: "/Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB/BlazeDB.xcodeproj")
        
        NSWorkspace.shared.open(projectURL)
        
        // Show helper alert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = "Xcode Opening"
            alert.informativeText = "Press ⌘U in Xcode to run all 907 BlazeDB tests.\n\nTests typically complete in 2-3 minutes."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Got It")
            alert.runModal()
        }
    }
    
    // MARK: - Running View
    
    private var runningView: some View {
        VStack(spacing: 24) {
            ProgressView(value: runner.progress)
                .progressViewStyle(.linear)
                .frame(width: 400)
            
            VStack(spacing: 8) {
                Text(runner.currentTest)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(runner.completedTests) / \(runner.totalTests) tests")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Live results
            HStack(spacing: 40) {
                StatBadge(
                    value: "\(runner.passedTests)",
                    label: "Passed",
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
                
                StatBadge(
                    value: "\(runner.failedTests)",
                    label: "Failed",
                    color: .red,
                    icon: "xmark.circle.fill"
                )
                
                StatBadge(
                    value: String(format: "%.1fs", runner.elapsedTime),
                    label: "Time",
                    color: .blue,
                    icon: "clock.fill"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Results View
    
    private func resultsView(_ results: TestResults) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Error message if no tests ran
                if results.total == 0 {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("No Tests Executed")
                            .font(.title.bold())
                        
                        Text("xcodebuild failed to run the test suite")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Possible solutions:")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                Text("Run tests directly in Xcode with ⌘U")
                            }
                            .font(.callout)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                Text("Check Console.app for xcodebuild errors")
                            }
                            .font(.callout)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("3.")
                                Text("Make sure BlazeDB scheme is shared in Xcode")
                            }
                            .font(.callout)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("4.")
                                VStack(alignment: .leading) {
                                    Text("Run manually:")
                                    Text("cd /Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB")
                                        .font(.caption.monospaced())
                                    Text("xcodebuild test -scheme BlazeDB -destination platform=macOS")
                                        .font(.caption.monospaced())
                                }
                            }
                            .font(.callout)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                }
                
                // Summary Card
                VStack(spacing: 16) {
                    HStack(spacing: 40) {
                        VStack(spacing: 8) {
                            Text("\(results.passed)")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.green)
                            Text("Passed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 8) {
                            Text("\(results.failed)")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(results.failed > 0 ? .red : .secondary)
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 8) {
                            Text(String(format: "%.1f%%", results.passRate))
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(results.passRate >= 95 ? .green : .orange)
                            Text("Pass Rate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Completed in \(String(format: "%.2f", results.duration))s")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                
                // Category Breakdown
                VStack(alignment: .leading, spacing: 12) {
                    Text("Results by Category")
                        .font(.headline)
                    
                    ForEach(results.categories, id: \.name) { category in
                        TestCategoryResultView(category: category)
                    }
                }
                
                // Run again button
                Button(action: {
                    Task {
                        await runner.runTests()
                    }
                }) {
                    Label("Run Tests Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
    }
}

// MARK: - Test Category Card

struct TestCategoryCard: View {
    let title: String
    let icon: String
    let testCount: Int
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.mint)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(testCount)")
                .font(.title3.bold().monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            Text(value)
                .font(.title.bold().monospacedDigit())
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Test Category Result

struct TestCategoryResultView: View {
    let category: TestCategory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.name)
                    .font(.headline)
                
                Spacer()
                
                Text("\(category.passed)/\(category.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(category.failed > 0 ? .red : .green)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                    
                    Capsule()
                        .fill(category.failed > 0 ? Color.red.gradient : Color.green.gradient)
                        .frame(width: geometry.size.width * (Double(category.passed) / Double(category.total)))
                }
            }
            .frame(height: 8)
            
            if !category.failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(category.failures, id: \.self) { failure in
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text(failure)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Test Runner (ViewModel)

@MainActor
final class TestRunner: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var currentTest = ""
    @Published var completedTests = 0
    @Published var totalTests = 907  // REAL BlazeDB test count!
    @Published var passedTests = 0
    @Published var failedTests = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var results: TestResults?
    
    private var testProcess: Process?
    
    func runTests() async {
        isRunning = true
        progress = 0
        completedTests = 0
        passedTests = 0
        failedTests = 0
        results = nil
        
        let startTime = Date()
        
        // Run REAL BlazeDB tests using xcodebuild
        await runRealTests(startTime: startTime)
        
        isRunning = false
    }
    
    private func runRealTests(startTime: Date) async {
        let process = Process()
        testProcess = process
        
        // Set working directory to BlazeDB project root
        process.currentDirectoryURL = URL(fileURLWithPath: "/Users/mdanylchuk/Developer/ProjectBlaze/BlazeDB")
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            "test",
            "-scheme", "BlazeDB",
            "-destination", "platform=macOS",
            "-quiet"  // Reduce output noise
        ]
        
        // Disable buffering for real-time output
        process.environment = [
            "NSUnbufferedIO": "YES"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Read output asynchronously
        let outputHandle = pipe.fileHandleForReading
        
        do {
            // Debug: Log the command
            let command = "xcodebuild " + (process.arguments ?? []).joined(separator: " ")
            print("🔍 Executing: \(command)")
            print("🔍 Working directory: \(process.currentDirectoryURL?.path ?? "none")")
            
            currentTest = "Starting xcodebuild..."
            try process.run()
            
            // Check if process started
            if !process.isRunning {
                currentTest = "❌ xcodebuild exited immediately"
                elapsedTime = Date().timeIntervalSince(startTime)
                
                // Try to read any output
                let errorData = try? outputHandle.readToEnd()
                let errorOutput = errorData.flatMap { String(data: $0, encoding: .utf8) } ?? "No output"
                
                print("❌ xcodebuild error output:\n\(errorOutput)")
                
                // Create error results with helpful info
                results = TestResults(
                    total: 0,
                    passed: 0,
                    failed: 0,
                    duration: elapsedTime,
                    categories: [
                        TestCategory(
                            name: "Setup Error",
                            total: 0,
                            passed: 0,
                            failed: 0,
                            failures: [
                                "xcodebuild failed to start or exited immediately",
                                "Command: \(command)",
                                "Check Console.app for xcodebuild errors",
                                errorOutput.components(separatedBy: "\n").prefix(5).joined(separator: " | ")
                            ]
                        )
                    ]
                )
                return
            }
            
            currentTest = "Running tests..."
            print("✅ xcodebuild started successfully")
            
            // Set up notification for output
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self.currentTest = "Tests running... (check Xcode Console for progress)"
                        print("📝 xcodebuild: \(output.prefix(200))...")
                    }
                }
            }
            
            // Parse output in background task
            Task.detached { @MainActor [weak self] in
                guard let self = self else { return }
                
                var categoryResults: [String: TestCategory] = [
                    "Unit Tests": TestCategory(name: "Unit Tests", total: 437, passed: 0, failed: 0, failures: []),
                    "Integration Tests": TestCategory(name: "Integration Tests", total: 19, passed: 0, failed: 0, failures: []),
                    "MVCC Tests": TestCategory(name: "MVCC Tests", total: 67, passed: 0, failed: 0, failures: []),
                    "Binary Format Tests": TestCategory(name: "Binary Format Tests", total: 48, passed: 0, failed: 0, failures: []),
                    "Chaos Engineering": TestCategory(name: "Chaos Engineering", total: 7, passed: 0, failed: 0, failures: []),
                    "Property-Based Tests": TestCategory(name: "Property-Based Tests", total: 15, passed: 0, failed: 0, failures: []),
                    "Performance Tests": TestCategory(name: "Performance Tests", total: 45, passed: 0, failed: 0, failures: []),
                    "Baseline Tests": TestCategory(name: "Baseline Tests", total: 269, passed: 0, failed: 0, failures: [])
                ]
                
                var currentCategory = "Unit Tests"
                
                // Monitor process output with better buffering
                var outputBuffer = ""
                
                while process.isRunning {
                    // Read available data (non-blocking)
                    let data = try? outputHandle.availableData
                    
                    if let data = data, !data.isEmpty,
                       let output = String(data: data, encoding: .utf8) {
                        
                        outputBuffer += output
                        print("📝 xcodebuild output: \(output.prefix(200))...")  // Debug
                        
                        // Parse xcodebuild output
                        let lines = outputBuffer.components(separatedBy: "\n")
                        
                        for line in lines {
                            guard !line.isEmpty else { continue }
                            
                            // Log interesting lines
                            if line.contains("Test") {
                                print("🧪 Test line: \(line)")
                            }
                            
                            // Detect test suite changes
                            if line.contains("Test Suite") && line.contains("started") {
                                if let suiteName = extractSuiteName(from: line) {
                                    currentTest = suiteName
                                    currentCategory = mapToCategory(suiteName)
                                    print("📂 Suite started: \(suiteName) → \(currentCategory)")
                                }
                            }
                            
                            // Detect test pass
                            if line.contains("Test Case") && line.contains("passed") {
                                passedTests += 1
                                completedTests += 1
                                if var category = categoryResults[currentCategory] {
                                    category.passed += 1
                                    categoryResults[currentCategory] = category
                                }
                                print("✅ Test passed (total: \(passedTests))")
                            }
                            
                            // Detect test fail
                            if line.contains("Test Case") && line.contains("failed") {
                                failedTests += 1
                                completedTests += 1
                                if let testName = extractTestName(from: line) {
                                    if var category = categoryResults[currentCategory] {
                                        category.failed += 1
                                        category.failures.append(testName)
                                        categoryResults[currentCategory] = category
                                    }
                                    print("❌ Test failed: \(testName) (total: \(failedTests))")
                                }
                            }
                            
                            // Update progress
                            progress = totalTests > 0 ? Double(completedTests) / Double(totalTests) : 0
                            elapsedTime = Date().timeIntervalSince(startTime)
                        }
                        
                        // Keep last incomplete line in buffer
                        if let lastNewline = outputBuffer.lastIndex(of: "\n") {
                            outputBuffer = String(outputBuffer[lastNewline...])
                        }
                    }
                    
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
                }
                
                print("🏁 xcodebuild process finished. Exit code: \(process.terminationStatus)")
                
                // Wait for process to complete
                print("⏳ Waiting for xcodebuild to finish...")
                process.waitUntilExit()
                
                print("🏁 xcodebuild finished with exit code: \(process.terminationStatus)")
                
                // Read any remaining output
                if let finalData = try? outputHandle.readToEnd(),
                   let finalOutput = String(data: finalData, encoding: .utf8) {
                    print("📝 Final output: \(finalOutput.prefix(500))...")
                }
                
                elapsedTime = Date().timeIntervalSince(startTime)
                
                // If we got zero results, it means parsing failed
                if passedTests == 0 && failedTests == 0 {
                    print("⚠️ Zero tests detected - parsing may have failed")
                    
                    // Create helpful results
                    results = TestResults(
                        total: 0,
                        passed: 0,
                        failed: 0,
                        duration: elapsedTime,
                        categories: [
                            TestCategory(
                                name: "Test Execution",
                                total: 0,
                                passed: 0,
                                failed: 0,
                                failures: [
                                    "xcodebuild executed (exit code: \(process.terminationStatus))",
                                    "But no test output was captured",
                                    "Tests may have run - check Xcode Test Navigator",
                                    "Or run manually: xcodebuild test -scheme BlazeDB"
                                ]
                            )
                        ]
                    )
                    return
                }
                
                // Final results
                let finalCategories = Array(categoryResults.values)
                    .filter { $0.passed > 0 || $0.failed > 0 }  // Only categories that ran
                    .sorted { $0.name < $1.name }
                
                results = TestResults(
                    total: completedTests,
                    passed: passedTests,
                    failed: failedTests,
                    duration: elapsedTime,
                    categories: finalCategories
                )
            }
            
        } catch {
            currentTest = "❌ Error starting tests: \(error.localizedDescription)"
            elapsedTime = Date().timeIntervalSince(startTime)
            
            // Create error results with details
            results = TestResults(
                total: 0,
                passed: 0,
                failed: 0,
                duration: elapsedTime,
                categories: [
                    TestCategory(
                        name: "Error",
                        total: 0,
                        passed: 0,
                        failed: 0,
                        failures: [
                            "Failed to execute xcodebuild",
                            error.localizedDescription,
                            "Check if BlazeDB.xcodeproj exists",
                            "Make sure xcodebuild is installed"
                        ]
                    )
                ]
            )
            isRunning = false
        }
    }
    
    func cancelTests() {
        testProcess?.terminate()
        testProcess = nil
        isRunning = false
        currentTest = "Tests cancelled"
    }
    
    private func extractSuiteName(from line: String) -> String? {
        if let range = line.range(of: "Test Suite '"), 
           let endRange = line.range(of: "'", range: range.upperBound..<line.endIndex) {
            return String(line[range.upperBound..<endRange.lowerBound])
        }
        return nil
    }
    
    private func extractTestName(from line: String) -> String? {
        if let range = line.range(of: "Test Case '-["), 
           let endRange = line.range(of: "]'", range: range.upperBound..<line.endIndex) {
            let fullName = String(line[range.upperBound..<endRange.lowerBound])
            // Extract just the test method name
            if let lastDot = fullName.lastIndex(of: " ") {
                return String(fullName[fullName.index(after: lastDot)...])
            }
            return fullName
        }
        return nil
    }
    
    private func mapToCategory(_ suiteName: String) -> String {
        if suiteName.contains("MVCC") { return "MVCC Tests" }
        if suiteName.contains("Integration") { return "Integration Tests" }
        if suiteName.contains("Binary") || suiteName.contains("Blaze") { return "Binary Format Tests" }
        if suiteName.contains("Chaos") { return "Chaos Engineering" }
        if suiteName.contains("Property") { return "Property-Based Tests" }
        if suiteName.contains("Performance") || suiteName.contains("Baseline") { return "Performance Tests" }
        if suiteName.contains("Baseline") { return "Baseline Tests" }
        return "Unit Tests"
    }
}

// MARK: - Test Results Models

struct TestResults {
    let total: Int
    let passed: Int
    let failed: Int
    let duration: TimeInterval
    let categories: [TestCategory]
    
    var passRate: Double {
        total > 0 ? (Double(passed) / Double(total)) * 100 : 0
    }
}

struct TestCategory {
    let name: String
    let total: Int
    var passed: Int
    var failed: Int
    var failures: [String]
}

