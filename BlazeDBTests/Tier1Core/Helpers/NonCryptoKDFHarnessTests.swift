import XCTest
#if canImport(BlazeDBCore)
@testable import BlazeDBCore
#else
@testable import BlazeDB
#endif

private final class OrdinaryKDFHarnessContext: NonCryptoKDFHarness {}
private final class NextOrdinaryKDFHarnessContext: NonCryptoKDFHarness {}

private final class InterClassKDFObserver: XCTestCase {
    class func assertEntryState(rawOverride: Int?, iterations: Int) {
        let entryOverride = KeyManager.currentTestPBKDF2IterationsOverride()
        let entryIterations = KeyManager.pbkdf2Iterations
        XCTAssertEqual(entryOverride, rawOverride)
        XCTAssertEqual(entryIterations, iterations)
    }
}

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

    func testClassLifecycleSequenceRestoresDefault() {
        let defaultIterations = KeyManager.pbkdf2Iterations
        assertClassLifecycleSequence(previousOverride: nil, iterations: defaultIterations)
    }

    func testClassLifecycleSequenceRestoresSavedOverride() {
        KeyManager.setTestPBKDF2IterationsOverride(12_345)
        assertClassLifecycleSequence(previousOverride: 12_345, iterations: 12_345)
    }

    private func assertClassLifecycleSequence(previousOverride: Int?, iterations: Int) {
        OrdinaryKDFHarnessContext.setUp()
        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), 10_000)
        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), previousOverride)
        XCTAssertEqual(KeyManager.pbkdf2Iterations, iterations)

        InterClassKDFObserver.setUp()
        InterClassKDFObserver.assertEntryState(rawOverride: previousOverride, iterations: iterations)
        InterClassKDFObserver.tearDown()

        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), previousOverride)
        XCTAssertEqual(KeyManager.pbkdf2Iterations, iterations)
        NextOrdinaryKDFHarnessContext.setUp()
        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), 10_000)
        XCTAssertEqual(KeyManager.pbkdf2Iterations, 10_000)
        NextOrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), previousOverride)
        XCTAssertEqual(KeyManager.pbkdf2Iterations, iterations)
    }
}

// This security-style suite deliberately inherits XCTestCase directly.
final class NonCryptoKDFIsolationTests: XCTestCase {
    nonisolated(unsafe) private static var entryDefaultIterations = 0
    private var previousIterationsOverride: Int?

    override class func setUp() {
        // Capture before super so accidental harness inheritance stays observable.
        entryDefaultIterations = KeyManager.pbkdf2Iterations
        super.setUp()
    }

    override func setUpWithError() throws {
        previousIterationsOverride = KeyManager.currentTestPBKDF2IterationsOverride()
        let entryIterations = KeyManager.pbkdf2Iterations
        XCTAssertNil(previousIterationsOverride)
        XCTAssertEqual(entryIterations, Self.entryDefaultIterations)
    }

    override func tearDownWithError() throws {
        KeyManager.setTestPBKDF2IterationsOverride(previousIterationsOverride)
    }

    func testDefaultIsUnchangedAfterOrdinarySuite() {
        let defaultIterations = KeyManager.pbkdf2Iterations

        OrdinaryKDFHarnessContext.setUp()
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, defaultIterations)
        XCTAssertNil(KeyManager.currentTestPBKDF2IterationsOverride())
    }

    func testExplicitOverrideSurvivesOrdinarySuite() {
        KeyManager.setTestPBKDF2IterationsOverride(200_000)

        OrdinaryKDFHarnessContext.setUp()
        OrdinaryKDFHarnessContext.tearDown()

        XCTAssertEqual(KeyManager.pbkdf2Iterations, 200_000)
        XCTAssertEqual(KeyManager.currentTestPBKDF2IterationsOverride(), 200_000)
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
