import XCTest
import Foundation

final class DistributedSecurityTests: XCTestCase {
    private func runXcodeDistributedSuite() throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "xcodebuild",
            "test",
            "-project", "BlazeDB.xcodeproj",
            "-scheme", "BlazeDB",
            "-destination", "platform=macOS",
            "-only-testing:BlazeDBTests/DistributedSecurityTests"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    func testDistributedFailClosedSuiteExecutesAndPasses() throws {
        let result = try runXcodeDistributedSuite()

        XCTAssertEqual(
            result.status,
            0,
            "Distributed security suite failed to run.\n\(result.output)"
        )

        XCTAssertTrue(
            result.output.contains("** TEST SUCCEEDED **"),
            "xcodebuild did not report success.\n\(result.output)"
        )

        XCTAssertTrue(
            result.output.contains("DistributedSecurityTests.testSyncEngine_InvalidRemoteOperation_DoesNotMutateState()"),
            "Missing exploit-path fail-closed execution proof.\n\(result.output)"
        )

        XCTAssertTrue(
            result.output.contains("DistributedSecurityTests.testSyncEngine_MixedBatchWithInvalidOperation_RejectsEntireBatch()"),
            "Missing mixed-batch atomic rejection execution proof.\n\(result.output)"
        )

        XCTAssertFalse(
            result.output.contains("Executed 0 tests"),
            "Distributed security proof invalid: suite executed zero tests.\n\(result.output)"
        )
    }
}
