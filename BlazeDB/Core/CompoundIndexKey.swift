import Foundation

/// Compound index key for multi-field indexes
/// Used to index records by multiple fields simultaneously
public struct CompoundIndexKey: Hashable, Codable {
    public let components: [BlazeDocumentField]
    
    public init(_ components: [AnyBlazeCodable]) {
        self.components = components.map { codable in
            switch codable.value {
            case let v as String: return .string(v)
            case let v as Int: return .int(v)
            case let v as Double: return .double(v)
            case let v as Bool: return .bool(v)
            case let v as Date: return .date(v)
            case let v as UUID: return .uuid(v)
            case let v as Data: return .data(v)
            default: return .null
            }
        }
    }
    
    /// Create a compound index key from document fields
    public static func fromFields(_ document: [String: BlazeDocumentField], fields: [String]) -> CompoundIndexKey {
        let components = fields.compactMap { field -> BlazeDocumentField? in
            return document[field]
        }
        return CompoundIndexKey(components.map { field in
            switch field {
            case .string(let s): return AnyBlazeCodable(s)
            case .int(let i): return AnyBlazeCodable(i)
            case .double(let d): return AnyBlazeCodable(d)
            case .bool(let b): return AnyBlazeCodable(b)
            case .date(let d): return AnyBlazeCodable(d)
            case .uuid(let u): return AnyBlazeCodable(u)
            case .data(let d): return AnyBlazeCodable(d)
            default: return AnyBlazeCodable("")
            }
        })
    }
    
    public func hash(into hasher: inout Hasher) {
        for component in components {
            switch component {
            case .string(let s): hasher.combine(s)
            case .int(let i): hasher.combine(i)
            case .double(let d): hasher.combine(d)
            case .bool(let b): hasher.combine(b)
            case .date(let d): hasher.combine(d.timeIntervalSince1970)
            case .uuid(let u): hasher.combine(u)
            case .data(let d): hasher.combine(d)
            default: hasher.combine(0)
            }
        }
    }
    
    public static func == (lhs: CompoundIndexKey, rhs: CompoundIndexKey) -> Bool {
        guard lhs.components.count == rhs.components.count else { return false }
        for (l, r) in zip(lhs.components, rhs.components) {
            if !Self.compareFields(l, r) { return false }
        }
        return true
    }
    
    private static func compareFields(_ lhs: BlazeDocumentField, _ rhs: BlazeDocumentField) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)): return l == r
        case (.int(let l), .int(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.bool(let l), .bool(let r)): return l == r
        case (.date(let l), .date(let r)): return l == r
        case (.uuid(let l), .uuid(let r)): return l == r
        case (.data(let l), .data(let r)): return l == r
        case (.null, .null): return true
        default: return false
        }
    }
}
