//
//  XCTestCase+FixtureRequire.swift
//  BlazeDBTests
//
//  Optional test fixtures (setUp assigns `?` properties) are unwrapped via XCTUnwrap
//  so failures are explicit test failures, not force-unwrap crashes.
//

import XCTest

extension XCTestCase {
    /// XCTUnwrap with a default message; use for optional fixtures assigned in `setUp` / `setUpWithError`.
    func requireFixture<T>(
        _ value: T?,
        _ message: @autoclosure () -> String = "Fixture should be set in setUp",
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> T {
        try XCTUnwrap(value, message(), file: file, line: line)
    }
}
