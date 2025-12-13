import Foundation

public struct BlazeQueryContext {
    private let collection: DynamicCollection
    private let query = BlazeQueryLegacy<[String: BlazeDocumentField]>()
    
    public init(collection: DynamicCollection) {
        self.collection = collection
    }
    
    public func `where`(_ field: String) -> BlazeFieldQueryBuilder<[String: BlazeDocumentField]> {
        BlazeFieldQueryBuilder(builder: query, field: field)
    }
    
    public func execute() throws -> [BlazeDataRecord] {
        let all = try collection.fetchAll()
        let filtered = query.apply(to: all.map { $0.storage })
        return filtered.map { BlazeDataRecord($0) }
    }
}

public struct BlazeFieldQueryBuilder<T> {
    private let builder: BlazeQueryLegacy<T>
    private var field: String?
    
    public init(builder: BlazeQueryLegacy<T>, field: String? = nil) {
        self.builder = builder
        self.field = field
    }
    
    public func equals(_ value: BlazeDocumentField) -> BlazeQueryLegacy<T> {
        var copy = builder
        if let field = self.field {
            copy = copy.addPredicate { record in
                guard let dict = record as? [String: BlazeDocumentField] else { return false }
                return dict[field] == value
            }
        }
        return copy
    }
}

