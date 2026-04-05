// swift-corelibs-xctest on Linux does not ship XCTClockMetric / measure(metrics:...).
// Provide minimal stubs and a generic measure overload so Tier1 performance-style tests compile.

#if os(Linux) || os(Android)
import XCTest

public struct XCTClockMetric { public init() {} }
public struct XCTMemoryMetric { public init() {} }
public struct XCTStorageMetric { public init() {} }
public struct XCTCPUMetric { public init() {} }

extension XCTestCase {
    public func measure<M>(metrics: [M], block: () -> Void) {
        block()
    }
}
#endif
