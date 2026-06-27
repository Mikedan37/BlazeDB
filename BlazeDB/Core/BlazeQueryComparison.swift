//
//  BlazeQueryComparison.swift
//  BlazeDB
//
//  Filter comparison operators shared by BlazeLiveQuery and SwiftUI query wrappers.
//

import Foundation

/// Comparison operators for typed live queries and SwiftUI query filters.
public enum BlazeQueryComparison: Sendable {
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case greaterThanOrEqual
    case lessThanOrEqual
    case contains // For strings
}
