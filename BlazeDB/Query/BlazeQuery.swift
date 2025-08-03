//  B.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation

public typealias BlazeFilter<T> = (T) -> Bool

public struct BlazeQuery {
    public static func equals<T, V: Equatable>(_ keyPath: KeyPath<T, V>, _ value: V) -> BlazeFilter<T> {
        return { record in record[keyPath: keyPath] == value }
    }

    public static func contains<T>(_ keyPath: KeyPath<T, String>, _ substring: String) -> BlazeFilter<T> {
        return { record in record[keyPath: keyPath].contains(substring) }
    }

    public static func greaterThan<T, V: Comparable>(_ keyPath: KeyPath<T, V>, _ value: V) -> BlazeFilter<T> {
        return { record in record[keyPath: keyPath] > value }
    }

    public static func lessThan<T, V: Comparable>(_ keyPath: KeyPath<T, V>, _ value: V) -> BlazeFilter<T> {
        return { record in record[keyPath: keyPath] < value }
    }

    public static func and<T>(_ lhs: @escaping BlazeFilter<T>, _ rhs: @escaping BlazeFilter<T>) -> BlazeFilter<T> {
        return { lhs($0) && rhs($0) }
    }

    public static func or<T>(_ lhs: @escaping BlazeFilter<T>, _ rhs: @escaping BlazeFilter<T>) -> BlazeFilter<T> {
        return { lhs($0) || rhs($0) }
    }
}
