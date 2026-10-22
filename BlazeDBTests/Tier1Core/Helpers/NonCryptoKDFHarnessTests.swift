import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private final class OrdinaryKDFHarnessContext: NonCryptoKDFHarness {}

final class NonCryptoKDFHarnessTests: XCTestCase {
    private var previousIterationsOverride: Int?

    override func setUpWithError() throws {
        previousIterationsOverride = KeyManager.currentTestPBKDF2IterationsOverride()
        KeyManager.setTestPBKDF2IterationsOverride(nil)
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(previousIterationsOverride)
    }

    func testRestoresDefaultWhenNoOverrideWasSet() {
        let defaultIterations = KeyManager.pbkdf2Iterations

        OrdinaryKDFHarnessContext.setUp()
        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, defaultIterations)
        XCTAssertNil(KeyManager.currentTestPBKDF2IterationsOverride())
    }

    func testRestoresExistingOverride() {
        KeyManager.setTestPBKDF2IterationsOverride(12_345)

        OrdinaryKDFHarnessContext.setUp()
        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 12_345)
        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), 12_345)
    }

    func testAppliesReliefDuringOrdinarySuite() {
        KeyManager.setTestPBKDF2IterationsOverride(12_345)
        OrdinaryKDFHarnessContext.setUp()
        defer { OrdinaryKDFHarnessContext.tearDown() }

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
    }
}

// This security-style suite deliberately inherits XCTestCase directly.
final class NonCryptoKDFIsolationTests: XCTestCase {
    private var previousIterationsOverride: Int?

    override func setUpWithError() throws {
        previousIterationsOverride = KeyManager.currentTestPBKDF2IterationsOverride()
        KeyManager.setTestPBKDF2IterationsOverride(nil)
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(previousIterationsOverride)
    }

    func testDefaultIsUnchangedAfterOrdinarySuite() {
        let defaultIterations = KeyManager.pbkdf2Iterations

        OrdinaryKDFHarnessContext.setUp()
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, defaultIterations)
    }

    func testExplicitOverrideSurvivesOrdinarySuite() {
        KeyManager.setTestPBKDF2IterationsOverride(200_000)

        OrdinaryKDFHarnessContext.setUp()
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 200_000)
    }

    func testSecurityContextSeesActiveProcessOverrideWithoutPriorOverride() {
        OrdinaryKDFHarnessContext.setUp()
        defer { OrdinaryKDFHarnessContext.tearDown() }

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
    }

    func testSecurityContextSeesActiveProcessOverrideWithExplicitOverride() {
        KeyManager.setTestPBKDF2IterationsOverride(200_000)
        OrdinaryKDFHarnessContext.setUp()
        defer { OrdinaryKDFHarnessContext.tearDown() }

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
    }
}
