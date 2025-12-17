//
//  DynamicCollection+Vector.swift
//  BlazeDB
//
//  Vector index integration for DynamicCollection
//
//  Created by Auto on 1/XX/25.
//

#if !BLAZEDB_LINUX_CORE

import Foundation

extension DynamicCollection {
    
    // MARK: - Vector Index Properties
    // Note: vectorIndex and cachedVectorIndexedField are now stored properties on DynamicCollection
    // This removes the need for Objective-C runtime associated objects
    
    /// Public accessor for vector index (delegates to stored property)
    public var vectorIndex: VectorIndex? {
        return queue.sync {
            return self._vectorIndex  // Accesses the stored property
        }
    }
    
    // MARK: - Vector Index Management
    
    /// Enable vector index for a field
    /// - Parameter fieldName: Field name containing vector embeddings
    public func enableVectorIndex(fieldName: String) throws {
        try queue.sync(flags: .barrier) {
            // Create or get existing index
            let index = _vectorIndex ?? VectorIndex()
            _vectorIndex = index
            cachedVectorIndexedField = fieldName
            
            // Rebuild index from existing records
            var indexedCount = 0
            for (id, pageIndices) in indexMap {
                guard let firstPageIndex = pageIndices.first else { continue }
                do {
                    let data = try store.readPageWithOverflow(index: firstPageIndex)
                    guard let data = data, !data.isEmpty else { continue }
                    
                    let record = try BlazeBinaryDecoder.decode(data)
                    if let vector = extractVector(from: record, fieldName: fieldName) {
                        index.insert(vector, id: id)
                        indexedCount += 1
                    }
                } catch {
                    continue
                }
            }
            
            // Save to layout
            try saveVectorIndexToLayout()
            
            BlazeLogger.info("Vector index enabled for field '\(fieldName)': \(indexedCount) vectors indexed")
        }
    }
    
    /// Disable vector index
    public func disableVectorIndex() throws {
        try queue.sync(flags: .barrier) {
            _vectorIndex = nil
            cachedVectorIndexedField = nil
            try saveVectorIndexToLayout()
            BlazeLogger.info("Vector index disabled")
        }
    }
    
    /// Rebuild vector index (useful after bulk updates)
    public func rebuildVectorIndex() throws {
        guard let fieldName = cachedVectorIndexedField else {
            throw BlazeDBError.invalidQuery(reason: "Vector index not enabled")
        }
        
        try queue.sync(flags: .barrier) {
            let index = VectorIndex()
            _vectorIndex = index
            
            var indexedCount = 0
            for (id, pageIndices) in indexMap {
                guard let firstPageIndex = pageIndices.first else { continue }
                do {
                    let data = try store.readPageWithOverflow(index: firstPageIndex)
                    guard let data = data, !data.isEmpty else { continue }
                    
                    let record = try BlazeBinaryDecoder.decode(data)
                    if let vector = extractVector(from: record, fieldName: fieldName) {
                        index.insert(vector, id: id)
                        indexedCount += 1
                    }
                } catch {
                    continue
                }
            }
            
            try saveVectorIndexToLayout()
            
            BlazeLogger.info("Vector index rebuilt: \(indexedCount) vectors indexed")
        }
    }
    
    /// Get vector index statistics
    public func getVectorIndexStats() -> VectorIndexStats? {
        return queue.sync {
            return _vectorIndex?.getStats()
        }
    }
    
    // MARK: - Internal Helpers
    
    /// Extract vector from record
    internal func extractVector(from record: BlazeDataRecord, fieldName: String) -> VectorEmbedding? {
        guard let fieldValue = record.storage[fieldName] else { return nil }
        
        switch fieldValue {
        case .data(let data):
            // Decode vector from data (array of floats)
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0 else { return nil }
            
            var vector: VectorEmbedding = []
            vector.reserveCapacity(count)
            
            data.withUnsafeBytes { bytes in
                let floats = bytes.bindMemory(to: Float.self)
                for i in 0..<count {
                    vector.append(floats[i])
                }
            }
            
            return vector
        case .array(let array):
            // Try to decode as array of doubles/floats
            var vector: VectorEmbedding = []
            for item in array {
                if case .double(let d) = item {
                    vector.append(Float(d))
                } else if case .int(let i) = item {
                    vector.append(Float(i))
                } else {
                    return nil  // Mixed types, not a valid vector
                }
            }
            return vector.isEmpty ? nil : vector
        default:
            return nil
        }
    }
    
    internal func updateVectorIndexOnInsert(_ record: BlazeDataRecord) {
        guard let index = _vectorIndex,
              let fieldName = cachedVectorIndexedField,
              let recordID = record.storage["id"]?.uuidValue,
              let vector = extractVector(from: record, fieldName: fieldName) else {
            return
        }
        index.insert(vector, id: recordID)
        BlazeLogger.trace("Updated vector index for inserted record \(recordID)")
    }
    
    internal func updateVectorIndexOnUpdate(_ record: BlazeDataRecord) {
        guard let index = _vectorIndex,
              let fieldName = cachedVectorIndexedField,
              let recordID = record.storage["id"]?.uuidValue else {
            return
        }
        // Remove old, add new
        index.remove(recordID)
        if let vector = extractVector(from: record, fieldName: fieldName) {
            index.insert(vector, id: recordID)
        }
        BlazeLogger.trace("Updated vector index for updated record \(recordID)")
    }
    
    internal func updateVectorIndexOnDelete(_ id: UUID) {
        guard let index = _vectorIndex else { return }
        index.remove(id)
        BlazeLogger.trace("Removed record \(id) from vector index")
    }
    
    private func saveVectorIndexToLayout() throws {
        // Note: vectorIndexedField is not stored in StorageLayout
        // Vector index state is maintained in memory only
        BlazeLogger.debug("Vector index state (field: \(cachedVectorIndexedField ?? "none")) - not persisted to layout")
    }
}

#endif // !BLAZEDB_LINUX_CORE
