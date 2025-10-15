//  B.swift
//  BlazeDB
//  Created by Michael Danylchuk on 6/15/25.
import Foundation
import ArgumentParser

public typealias BlazeFilter<T> = (T) -> Bool

public final class BlazeQuery<T> {
    private var predicates: [(T) -> Bool] = []
    private var sortComparators: [(T, T) -> Bool] = []
    private var rangeLimits: Range<Int>?

    public init() {}

    public convenience init(field: String, equals value: String) where T == [String: BlazeDocumentField] {
        self.init()
        self.filter { record in
            guard let fieldValue = record[field]?.value as? String else { return false }
            return fieldValue == value
        }
    }

    @discardableResult
    public func `where`(_ predicate: @escaping (T) -> Bool) -> Self {
        return filter(predicate)
    }

    public func `where`<V: Equatable>(_ keyPath: KeyPath<T, V>) -> BlazeWhereBuilder<T, V> {
        return BlazeWhereBuilder(query: self, keyPath: keyPath)
    }

    public static func whereField(_ field: String) -> BlazeDynamicWhereBuilder {
        return BlazeDynamicWhereBuilder(field: field)
    }

    @discardableResult
    public func filter(_ predicate: @escaping (T) -> Bool) -> Self {
        self.predicates.append(predicate)
        return self
    }

    @discardableResult
    public func sort(by comparator: @escaping (T, T) -> Bool) -> Self {
        self.sortComparators.append(comparator)
        return self
    }

    /// Allows chaining additional predicates with logical AND.
    @discardableResult
    public func addPredicate(_ newPredicate: @escaping (T) -> Bool) -> Self {
        self.predicates.append(newPredicate)
        return self
    }

    public var range: Range<Int>? {
        return rangeLimits
    }

    @discardableResult
    public func range(_ range: Range<Int>) -> Self {
        self.rangeLimits = range
        return self
    }

    public func apply(to elements: [T]) -> [T] {
        var result = elements
        for predicate in predicates {
            result = result.filter(predicate)
        }
        if !sortComparators.isEmpty {
            result = result.sorted { lhs, rhs in
                for comparator in sortComparators {
                    if comparator(lhs, rhs) { return true }
                    if comparator(rhs, lhs) { return false }
                }
                return false
            }
        }
        if let range = rangeLimits {
            result = Array(result[range.clamped(to: result.indices)])
        }
        return result
    }
}

public struct BlazeWhereBuilder<T, V: Equatable> {
    private let query: BlazeQuery<T>
    private let keyPath: KeyPath<T, V>

    init(query: BlazeQuery<T>, keyPath: KeyPath<T, V>) {
        self.query = query
        self.keyPath = keyPath
    }

    @discardableResult
    public func equals(_ value: V) -> BlazeQuery<T> {
        return query.filter { $0[keyPath: keyPath] == value }
    }

    @discardableResult
    public func contains(_ substring: String) -> BlazeQuery<T> where V == String {
        return query.filter { $0[keyPath: keyPath].contains(substring) }
    }

    @discardableResult
    public func greaterThan(_ value: V) -> BlazeQuery<T> where V: Comparable {
        return query.filter { $0[keyPath: keyPath] > value }
    }

    @discardableResult
    public func lessThan(_ value: V) -> BlazeQuery<T> where V: Comparable {
        return query.filter { $0[keyPath: keyPath] < value }
    }
}

public struct BlazeDynamicWhereBuilder {
    let field: String

    @discardableResult
    public func equals(_ value: String) -> BlazeQuery<[String: BlazeDocumentField]> {
        return BlazeQuery(field: field, equals: value)
    }
}

public extension BlazeQuery {
    /// Alias for `filter`, reads better in query DSLs.
    func evaluate(_ predicate: @escaping (T) -> Bool) -> Self {
        return self.filter(predicate)
    }

    /// Convenience predicate to hand to `Collection.filter` and friends.
    var matches: (T) -> Bool {
        return { element in
            !self.apply(to: [element]).isEmpty
        }
    }
}
