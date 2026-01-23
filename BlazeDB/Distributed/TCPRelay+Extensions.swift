//
//  TCPRelay+Extensions.swift
//  BlazeDB Distributed
//
//  Extensions for TCPRelay (UUID binary encoding, parallel map)
//

#if !BLAZEDB_LINUX_CORE
import Foundation

#if BLAZEDB_DISTRIBUTED
import BlazeDBCore
#endif

// MARK: - UUID Binary Encoding Extension

extension UUID {
    /// Get UUID as 16-byte binary data
    var binaryData: Data {
        let uuid = self.uuid
        return withUnsafeBytes(of: uuid) { Data($0) }
    }
    
    /// Create UUID from 16-byte binary data
    init(binaryData data: Data) {
        guard data.count == 16 else {
            self = UUID()
            return
        }
        // Convert to array to avoid any alignment issues
        let bytes = [UInt8](data)
        // Construct uuid_t tuple from bytes
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        self = UUID(uuid: uuid)
    }
}

// MARK: - Parallel Map Extension

extension Array {
    func concurrentMap<T: Sendable>(_ transform: @escaping @Sendable (Element) async throws -> T) async rethrows -> [T] {
        return try await withThrowingTaskGroup(of: T.self) { group in
            for item in self {
                group.addTask { @Sendable in
                    try await transform(item)
                }
            }
            
            var results: [T] = []
            results.reserveCapacity(self.count)
            
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
    }
}
#endif // !BLAZEDB_LINUX_CORE

