// MARK: - SwiftUI Binding Extensions

#if canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
import SwiftUI

extension BlazeDataRecord {
    
    /// Create a Binding to a field (for SwiftUI forms)
    ///
    /// Example:
    /// ```swift
    /// TextField("Title", text: bug.binding("title"))
    /// ```
    public func binding(_ field: String) -> Binding<String> {
        Binding(
            get: { self.storage[field]?.stringValue ?? "" },
            set: { newValue in
                var mutable = self
                mutable.storage[field] = .string(newValue)
            }
        )
    }
    
    /// Binding for Int field
    public func bindingInt(_ field: String) -> Binding<Int> {
        Binding(
            get: { self.storage[field]?.intValue ?? 0 },
            set: { newValue in
                var mutable = self
                mutable.storage[field] = .int(newValue)
            }
        )
    }
    
    /// Binding for Bool field
    public func bindingBool(_ field: String) -> Binding<Bool> {
        Binding(
            get: { self.storage[field]?.boolValue ?? false },
            set: { newValue in
                var mutable = self
                mutable.storage[field] = .bool(newValue)
            }
        )
    }
    
    /// Binding for Date field
    public func bindingDate(_ field: String) -> Binding<Date> {
        Binding(
            get: { self.storage[field]?.dateValue ?? Date() },
            set: { newValue in
                var mutable = self
                mutable.storage[field] = .date(newValue)
            }
        )
    }
}

// MARK: - List Helpers

extension Array where Element == BlazeDataRecord {
    
    /// Group records by field value (for SwiftUI sections)
    public func grouped(by field: String) -> [(key: String, records: [BlazeDataRecord])] {
        let dict = Dictionary(grouping: self) { record in
            record.storage[field]?.stringValue ?? ""
        }
        return dict.map { (key: $0.key, records: $0.value) }.sorted { $0.key < $1.key }
    }
    
    /// Sort by field (for SwiftUI lists)
    public func sorted(by field: String, descending: Bool = false) -> [BlazeDataRecord] {
        self.sorted { left, right in
            let leftValue = left.storage[field]
            let rightValue = right.storage[field]
            
            // Try to compare based on type
            if let l = leftValue?.stringValue, let r = rightValue?.stringValue {
                return descending ? l > r : l < r
            } else if let l = leftValue?.intValue, let r = rightValue?.intValue {
                return descending ? l > r : l < r
            } else if let l = leftValue?.dateValue, let r = rightValue?.dateValue {
                return descending ? l > r : l < r
            }
            
            return false
        }
    }
    
    /// Filter by field value (for SwiftUI search)
    public func filtered(by field: String, contains query: String) -> [BlazeDataRecord] {
        guard !query.isEmpty else { return self }
        
        return self.filter { record in
            let value = (record.storage[field]?.stringValue ?? "").lowercased()
            return value.contains(query.lowercased())
        }
    }
}

// MARK: - Observable Query (SwiftUI State Management)

@available(iOS 15.0, macOS 12.0, *)
@MainActor
public class ObservableQuery: ObservableObject {
    @Published public private(set) var records: [BlazeDataRecord] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?
    
    private let db: BlazeDBClient
    private let query: () -> QueryBuilder
    
    public init(db: BlazeDBClient, query: @escaping () -> QueryBuilder) {
        self.db = db
        self.query = query
    }
    
    public func load() async {
        isLoading = true
        error = nil
        
        do {
            records = try await query().all()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    public func refresh() async {
        await load()
    }
}

#endif // canImport(SwiftUI) && (os(macOS) || os(iOS) || os(watchOS) || os(tvOS))

