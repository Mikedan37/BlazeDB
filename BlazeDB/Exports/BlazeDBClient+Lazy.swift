//
//  BlazeDBClient+Lazy.swift
//  BlazeDB
//
//  Lazy decoding convenience methods
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE
import Foundation

extension BlazeDBClient {
    
    /// Enable lazy decoding for this database
    public func enableLazyDecoding() throws {
        try collection.enableLazyDecoding()
    }
    
    /// Disable lazy decoding for this database
    public func disableLazyDecoding() throws {
        try collection.disableLazyDecoding()
    }
    
    /// Check if lazy decoding is enabled
    public func isLazyDecodingEnabled() -> Bool {
        return collection.isLazyDecodingEnabled()
    }
    
    /// Fetch record with lazy decoding
    ///
    /// - Parameter id: Record ID
    /// - Returns: LazyBlazeRecord if lazy decoding enabled, nil otherwise
    public func fetchLazy(id: UUID) throws -> LazyBlazeRecord? {
        return try collection.fetchLazy(id: id)
    }
}
#endif // !BLAZEDB_LINUX_CORE
