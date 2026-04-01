#if os(Linux)
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
