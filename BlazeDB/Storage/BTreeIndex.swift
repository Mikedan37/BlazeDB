//
//  BTreeIndex.swift
//  BlazeDB
//
//  B-tree based index for efficient range queries
//  Supports: <, <=, >, >=, between, ordered iteration
//
//  Created by BlazeDB Architecture Sprint.
//

import Foundation

/// A B-tree node for sorted index storage
/// Optimized for in-memory use with disk persistence via Codable
public final class BTreeNode<Key: Comparable & Codable, Value: Codable>: Codable {
    var keys: [Key]
    var values: [[Value]]  // Each key can map to multiple values (non-unique index)
    var children: [BTreeNode<Key, Value>]?
    var isLeaf: Bool
    
    private enum CodingKeys: String, CodingKey {
        case keys, values, children, isLeaf
    }
    
    init(isLeaf: Bool = true) {
        self.keys = []
        self.values = []
        self.children = isLeaf ? nil : []
        self.isLeaf = isLeaf
    }
}

/// B-tree index supporting range queries
/// Thread-safe via internal locking
public final class BTreeIndex<Key: Comparable & Codable & Hashable, Value: Codable & Hashable>: @unchecked Sendable {
    
    /// Minimum degree (minimum number of children for non-root nodes)
    /// A node can have at most 2*t - 1 keys
    private let minDegree: Int
    private var root: BTreeNode<Key, Value>
    private let lock = NSLock()
    
    /// Index name for identification
    public let name: String
    
    /// Number of entries in the index
    public private(set) var count: Int = 0
    
    public init(name: String, minDegree: Int = 32) {
        self.name = name
        self.minDegree = max(2, minDegree)
        self.root = BTreeNode(isLeaf: true)
    }
    
    // MARK: - Insert
    
    /// Insert a key-value pair into the index
    public func insert(key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        // If root is full, split it
        if root.keys.count == 2 * minDegree - 1 {
            let newRoot = BTreeNode<Key, Value>(isLeaf: false)
            newRoot.children = [root]
            splitChild(newRoot, index: 0)
            root = newRoot
        }
        
        insertNonFull(root, key: key, value: value)
        count += 1
    }
    
    private func insertNonFull(_ node: BTreeNode<Key, Value>, key: Key, value: Value) {
        var i = node.keys.count - 1
        
        if node.isLeaf {
            // Find position and insert (searching from right to left)
            while i >= 0 && key < node.keys[i] {
                i -= 1
            }
            
            // Check if key already exists at position i (before incrementing)
            // When key == node.keys[i], the loop exits without decrementing
            if i >= 0 && node.keys[i] == key {
                // Add value to existing key's value list
                node.values[i].append(value)
            } else {
                // Insert new key-value pair at position i + 1
                node.keys.insert(key, at: i + 1)
                node.values.insert([value], at: i + 1)
            }
        } else {
            // Find child to descend into
            while i >= 0 && key < node.keys[i] {
                i -= 1
            }
            i += 1
            
            // Split child if full
            if node.children![i].keys.count == 2 * minDegree - 1 {
                splitChild(node, index: i)
                if key > node.keys[i] {
                    i += 1
                }
            }
            
            insertNonFull(node.children![i], key: key, value: value)
        }
    }
    
    private func splitChild(_ parent: BTreeNode<Key, Value>, index: Int) {
        let fullChild = parent.children![index]
        let newChild = BTreeNode<Key, Value>(isLeaf: fullChild.isLeaf)
        
        let midIndex = minDegree - 1
        
        // Move upper half of keys to new child
        newChild.keys = Array(fullChild.keys[(midIndex + 1)...])
        newChild.values = Array(fullChild.values[(midIndex + 1)...])
        
        if !fullChild.isLeaf {
            newChild.children = Array(fullChild.children![(midIndex + 1)...])
        }
        
        // Move median key up to parent
        let medianKey = fullChild.keys[midIndex]
        let medianValues = fullChild.values[midIndex]
        
        // Truncate full child
        fullChild.keys = Array(fullChild.keys[..<midIndex])
        fullChild.values = Array(fullChild.values[..<midIndex])
        if !fullChild.isLeaf {
            fullChild.children = Array(fullChild.children![...(midIndex)])
        }
        
        // Insert into parent
        parent.keys.insert(medianKey, at: index)
        parent.values.insert(medianValues, at: index)
        parent.children!.insert(newChild, at: index + 1)
    }
    
    // MARK: - Remove
    
    /// Remove a specific key-value pair from the index
    public func remove(key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        if removeFromNode(root, key: key, value: value) {
            count -= 1
        }
        
        // If root has no keys and has a child, make that child the new root
        if root.keys.isEmpty && !root.isLeaf {
            root = root.children![0]
        }
    }
    
    private func removeFromNode(_ node: BTreeNode<Key, Value>, key: Key, value: Value) -> Bool {
        var i = 0
        while i < node.keys.count && key > node.keys[i] {
            i += 1
        }
        
        if i < node.keys.count && node.keys[i] == key {
            // Found the key
            if let idx = node.values[i].firstIndex(where: { $0 == value }) {
                node.values[i].remove(at: idx)
                if node.values[i].isEmpty {
                    // Remove the key entirely
                    node.keys.remove(at: i)
                    node.values.remove(at: i)
                }
                return true
            }
            return false
        } else if node.isLeaf {
            return false
        } else {
            return removeFromNode(node.children![i], key: key, value: value)
        }
    }
    
    // MARK: - Search
    
    /// Find all values for an exact key
    public func find(key: Key) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        return findInNode(root, key: key)
    }
    
    private func findInNode(_ node: BTreeNode<Key, Value>, key: Key) -> [Value] {
        var i = 0
        while i < node.keys.count && key > node.keys[i] {
            i += 1
        }
        
        if i < node.keys.count && node.keys[i] == key {
            return node.values[i]
        } else if node.isLeaf {
            return []
        } else {
            return findInNode(node.children![i], key: key)
        }
    }
    
    // MARK: - Range Queries
    
    /// Find all values where key > lowerBound
    public func findGreaterThan(_ lowerBound: Key) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        rangeSearch(node: root, min: lowerBound, max: nil, includeMin: false, includeMax: true, results: &results)
        return results
    }
    
    /// Find all values where key >= lowerBound
    public func findGreaterThanOrEqual(_ lowerBound: Key) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        rangeSearch(node: root, min: lowerBound, max: nil, includeMin: true, includeMax: true, results: &results)
        return results
    }
    
    /// Find all values where key < upperBound
    public func findLessThan(_ upperBound: Key) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        rangeSearch(node: root, min: nil, max: upperBound, includeMin: true, includeMax: false, results: &results)
        return results
    }
    
    /// Find all values where key <= upperBound
    public func findLessThanOrEqual(_ upperBound: Key) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        rangeSearch(node: root, min: nil, max: upperBound, includeMin: true, includeMax: true, results: &results)
        return results
    }
    
    /// Find all values where lowerBound <= key <= upperBound
    public func findBetween(min: Key, max: Key, includeMin: Bool = true, includeMax: Bool = true) -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        rangeSearch(node: root, min: min, max: max, includeMin: includeMin, includeMax: includeMax, results: &results)
        return results
    }
    
    private func rangeSearch(
        node: BTreeNode<Key, Value>,
        min: Key?,
        max: Key?,
        includeMin: Bool,
        includeMax: Bool,
        results: inout [Value]
    ) {
        var i = 0
        
        // Find starting position
        if let minKey = min {
            while i < node.keys.count && node.keys[i] < minKey {
                i += 1
            }
            // Adjust for includeMin
            if !includeMin && i < node.keys.count && node.keys[i] == minKey {
                i += 1
            }
        }
        
        // Traverse keys in range
        while i < node.keys.count {
            let key = node.keys[i]
            
            // Check upper bound
            if let maxKey = max {
                if key > maxKey || (!includeMax && key == maxKey) {
                    break
                }
            }
            
            // Check lower bound (for non-leaf traversal)
            if let minKey = min {
                if key < minKey || (!includeMin && key == minKey) {
                    if !node.isLeaf {
                        rangeSearch(node: node.children![i], min: min, max: max, includeMin: includeMin, includeMax: includeMax, results: &results)
                    }
                    i += 1
                    continue
                }
            }
            
            // Visit left child first (if internal node)
            if !node.isLeaf && i < node.children!.count {
                rangeSearch(node: node.children![i], min: min, max: max, includeMin: includeMin, includeMax: includeMax, results: &results)
            }
            
            // Add values for this key
            results.append(contentsOf: node.values[i])
            
            i += 1
        }
        
        // Visit rightmost child if needed
        if !node.isLeaf && i < node.children!.count {
            rangeSearch(node: node.children![i], min: min, max: max, includeMin: includeMin, includeMax: includeMax, results: &results)
        }
    }
    
    // MARK: - Ordered Iteration
    
    /// Get all values in sorted key order
    public func allValuesSorted() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [Value] = []
        inorderTraversal(node: root, results: &results)
        return results
    }
    
    /// Get all key-value pairs in sorted key order
    public func allEntriesSorted() -> [(key: Key, values: [Value])] {
        lock.lock()
        defer { lock.unlock() }
        
        var results: [(key: Key, values: [Value])] = []
        inorderTraversalWithKeys(node: root, results: &results)
        return results
    }
    
    private func inorderTraversal(node: BTreeNode<Key, Value>, results: inout [Value]) {
        for i in 0..<node.keys.count {
            if !node.isLeaf {
                inorderTraversal(node: node.children![i], results: &results)
            }
            results.append(contentsOf: node.values[i])
        }
        if !node.isLeaf && !node.children!.isEmpty {
            inorderTraversal(node: node.children![node.keys.count], results: &results)
        }
    }
    
    private func inorderTraversalWithKeys(node: BTreeNode<Key, Value>, results: inout [(key: Key, values: [Value])]) {
        for i in 0..<node.keys.count {
            if !node.isLeaf {
                inorderTraversalWithKeys(node: node.children![i], results: &results)
            }
            results.append((key: node.keys[i], values: node.values[i]))
        }
        if !node.isLeaf && !node.children!.isEmpty {
            inorderTraversalWithKeys(node: node.children![node.keys.count], results: &results)
        }
    }
    
    // MARK: - Persistence
    
    /// Encode the index to Data for persistence
    public func encode() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        
        let encoder = JSONEncoder()
        return try encoder.encode(root)
    }
    
    /// Decode the index from Data
    public func decode(from data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let decoder = JSONDecoder()
        root = try decoder.decode(BTreeNode<Key, Value>.self, from: data)
        
        // Recalculate count
        count = 0
        countEntries(node: root)
    }
    
    private func countEntries(node: BTreeNode<Key, Value>) {
        for values in node.values {
            count += values.count
        }
        if let children = node.children {
            for child in children {
                countEntries(node: child)
            }
        }
    }
    
    /// Clear all entries
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        root = BTreeNode(isLeaf: true)
        count = 0
    }
}

// MARK: - BTreeIndex for BlazeDocumentField

/// Wrapper to make BlazeDocumentField Comparable for B-tree indexing
public struct ComparableField: Comparable, Hashable, Codable {
    public let field: BlazeDocumentField
    
    public init(_ field: BlazeDocumentField) {
        self.field = field
    }
    
    public static func < (lhs: ComparableField, rhs: ComparableField) -> Bool {
        switch (lhs.field, rhs.field) {
        case (.int(let l), .int(let r)):
            return l < r
        case (.double(let l), .double(let r)):
            return l < r
        case (.string(let l), .string(let r)):
            return l < r
        case (.date(let l), .date(let r)):
            return l < r
        case (.bool(let l), .bool(let r)):
            return !l && r  // false < true
        case (.uuid(let l), .uuid(let r)):
            return l.uuidString < r.uuidString
            
        // Cross-type comparison: order by type then value
        case (.null, _):
            return true
        case (_, .null):
            return false
        case (.bool, _):
            return true
        case (_, .bool):
            return false
        case (.int, _):
            return true
        case (_, .int):
            return false
        case (.double, _):
            return true
        case (_, .double):
            return false
        case (.string, _):
            return true
        case (_, .string):
            return false
        case (.date, _):
            return true
        case (_, .date):
            return false
        default:
            return false
        }
    }
    
    public static func == (lhs: ComparableField, rhs: ComparableField) -> Bool {
        return fieldsEqual(lhs.field, rhs.field)
    }
    
    public func hash(into hasher: inout Hasher) {
        switch field {
        case .string(let s): hasher.combine(s)
        case .int(let i): hasher.combine(i)
        case .double(let d): hasher.combine(d)
        case .bool(let b): hasher.combine(b)
        case .date(let d): hasher.combine(d.timeIntervalSince1970)
        case .uuid(let u): hasher.combine(u)
        case .data(let d): hasher.combine(d)
        case .null: hasher.combine(0)
        case .array(let a): hasher.combine(a.count)
        case .dictionary(let d): hasher.combine(d.count)
        case .vector(let v): hasher.combine(v.count)
        }
    }
}

/// Type alias for field-based B-tree index storing UUIDs
public typealias FieldBTreeIndex = BTreeIndex<ComparableField, UUID>

// MARK: - BTreeIndexManager

/// Manages B-tree indexes for a collection
public final class BTreeIndexManager: @unchecked Sendable {
    private var indexes: [String: FieldBTreeIndex] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    /// Create or get a B-tree index for a field
    public func getOrCreateIndex(for field: String) -> FieldBTreeIndex {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = indexes[field] {
            return existing
        }
        
        let index = FieldBTreeIndex(name: field)
        indexes[field] = index
        return index
    }
    
    /// Get an existing index (returns nil if not created)
    public func getIndex(for field: String) -> FieldBTreeIndex? {
        lock.lock()
        defer { lock.unlock() }
        
        return indexes[field]
    }
    
    /// Check if a B-tree index exists for a field
    public func hasIndex(for field: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return indexes[field] != nil
    }
    
    /// Remove an index
    public func removeIndex(for field: String) {
        lock.lock()
        defer { lock.unlock() }
        
        indexes.removeValue(forKey: field)
    }
    
    /// Get all index names
    public var indexNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(indexes.keys)
    }
    
    /// Clear all indexes
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        
        for index in indexes.values {
            index.clear()
        }
    }
    
    /// Update indexes for an inserted record
    public func indexRecord(id: UUID, fields: [String: BlazeDocumentField]) {
        lock.lock()
        let currentIndexes = indexes
        lock.unlock()
        
        for (fieldName, index) in currentIndexes {
            if let value = fields[fieldName] {
                index.insert(key: ComparableField(value), value: id)
            }
        }
    }
    
    /// Remove record from all indexes
    public func deindexRecord(id: UUID, fields: [String: BlazeDocumentField]) {
        lock.lock()
        let currentIndexes = indexes
        lock.unlock()
        
        for (fieldName, index) in currentIndexes {
            if let value = fields[fieldName] {
                index.remove(key: ComparableField(value), value: id)
            }
        }
    }
}
